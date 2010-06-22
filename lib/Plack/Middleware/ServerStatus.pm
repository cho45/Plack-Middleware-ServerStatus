package Plack::Middleware::ServerStatus;

use strict;
use warnings;
use parent qw(Plack::Middleware);
our $VERSION = '0.01';

use Plack::Util;
use Plack::Util::Accessor qw(header_name);
use Text::MicroTemplate;
use List::Util qw(reduce);
use Plack::Util::Accessor qw(renderer path cidr);
use Plack::Request;
use Net::CIDR::Lite;


sub TEMPLATE { <<'EOTMPL' }
% my $stash = $_[0];
% my $workers = $stash->{workers};

<!DOCTYPE html>
<title>Server Status</title>
<style type="text/css">
body {
    line-height: 1.33;
}

table {
    width: 100%;
}

table th,
table td {
    background: #efefef;
    padding: 0 1em;
}

dl.key-desc {
    background: #eee;
    padding: 1em;
}

dl dt {
    font-weight: bold;
}

td.pid,
td.cpu,
td.mem,
td.key,
td.client ,
td.method ,
td.host {
    text-align: center;
}

td.key {
    font-weight: bold;
}

td.uptime,
td.access,
td.proto {
    text-align: right;
}

tr.key-R td {
    background: #fed4d4;
}

tr.key-W td {
    background: #dafed4;
}

tr.key-K td {
    background: #dafed4;
}

tr.key-C td {
    background: #feecd4;
}

tr.key-_ td {
}

pre.scoreboard {
    padding: 1em;
    background: #efefef;
}

</style>

<h1>Server Status</h1>

<p>Server uptime:
    <%= sprintf '%d', $stash->{uptime}->[0] || 0 %> days
    <%= sprintf '%d', $stash->{uptime}->[1] || 0  %> hours
    <%= sprintf '%d', $stash->{uptime}->[2] || 0  %> minutes
    <%= sprintf '%d', $stash->{uptime}->[3] %> seconds</p>

<p><%= sprintf '%.1f', $stash->{avg_req_per_sec} %> requests/sec</p>
<p>
    <%= $stash->{busy_worker_num} %> requests currently being processed,
    <%= $stash->{idle_worker_num} %> idle workers
    <%= @$workers %> total workers
</p>

<pre class="scoreboard">
<%= $stash->{scoreboard} %>
</pre>

<table>
    <thead>
        <tr>
            <th class="pid">pid</th>
            <th class="uptime">uptime</th>
            <th class="access">access</th>
            <th class="cpu">cpu</th>
            <th class="mem">mem</th>
            <th class="key">key</th>
            <th class="client">client</th>
            <th class="host">host</th>
            <th class="method">method</th>
            <th class="path">path</th>
            <th class="proto">proto</th>
        </tr>
    </thead>
    <tbody>
        <% for my $worker (@$workers) { %>
        <tr class="key-<%= $worker->{key} %>">
            <td class="pid"><%= $worker->{pid} %></td>
            <td class="uptime"><%= $worker->{uptime} %></td>
            <td class="access"><%= $worker->{meta}->{req} %></td>
            <td class="cpu"><%= $worker->{cpu} %></td>
            <td class="mem"><%= $worker->{mem} %></td>
            <td class="key"><%= $worker->{key} %></td>
            <td class="client"><%= $worker->{client} %></td>
            <td class="host"><%= $worker->{host} %></td>
            <td class="method"><%= $worker->{method} %></td>
            <td class="path"><%= $worker->{path} %></td>
            <td class="proto"><%= $worker->{proto} %></td>
        </tr>
        <% } %>
    </tbody>
</table>

<dl class="key-desc">
    <dt>"_"</dt>
    <dd>Waiting for Connection</dd>
    <dt>"S"</dt>
    <dd>Starting up</dd>
    <dt>"R"</dt>
    <dd>Reading Request</dd>
    <dt>"W"</dt>
    <dd>Sending Reply</dd>
    <dt>"K"</dt>
    <dd>Keepalive (read)</dd>
    <dt>"C"</dt>
    <dd>Closing connection</dd>
    <dt>"G"</dt>
    <dd>Gracefully finishing</dd>
    <dt>"I"</dt>
    <dd>Idle cleanup of worker</dd>
    <dt>"."</dt>
    <dd>Open slot with no current process</dd>
</dl>

EOTMPL

sub prepare_app {
    my ($self) = @_;
    $self->renderer(
        Text::MicroTemplate->new(
            template   => $self->TEMPLATE,
            tag_start  => '<%',
            tag_end    => '%>',
            line_start => '%',
        )->build
    );
    $self->path('/server-status') unless $self->path;
}

sub call {
    my ($self, $env) = @_;
    return $self->_handle_server_status($env) if $env->{PATH_INFO} eq $self->path;
    my $res = $self->app->($env);
}

sub _handle_server_status {
    my ($self, $env) = @_;
    unless ($self->is_allowed($env->{REMOTE_ADDR})) {
        return [403, ['Content-Type' => 'text/plain'], [ 'Forbidden' ]]
    }

    my $workers = _collect_worker_info();
    my $total_accesses = reduce { $a + $b->{meta}->{'req'} } 0, @$workers;
    my $avg_req_per_sec = (reduce { $a + ($b->{meta}->{'req'} / $b->{uptime}) } 0, @$workers) / @$workers;
    my $idle_worker_num = scalar grep { $_->{key} eq '_'  } @$workers;
    my $busy_worker_num = @$workers - $idle_worker_num;
    my $scoreboard = join '', map { $_->{key} } @$workers;

    my $ppid   = $workers->[0]->{ppid};
    my $uptime = `ps -p $ppid -o etime=`;
    my ($day, $hour, $min, $sec) = ($uptime =~ /(?:(?:(?:(\d+)-)(\d+):)?(\d+):)?(\d+)/);
    my $uptime_sec = _uptime_sec($uptime);

    $avg_req_per_sec = sprintf('%.2f', $avg_req_per_sec);

    if ($env->{QUERY_STRING} eq 'auto') {
        [ 200, ['Content-Type' => 'text/plain'], [
            "Total Accesses: $total_accesses\n",
            "Total kBytes: n/a\n",
            "CPULoad: n/a\n",
            "Uptime: $uptime_sec\n",
            "ReqPerSec: $avg_req_per_sec\n",
            "BytesPerSec: n/a\n",
            "BytesPerReq: n/a\n",
            "BusyWorkers: $busy_worker_num\n",
            "IdleWorkers: $idle_worker_num\n",
            "Scoreboard: $scoreboard\n",
        ] ];
    } else {
        [ 200, ['Content-Type' => 'text/html'], [
            $self->renderer->({
                uptime          => [$day, $hour, $min, $sec],
                workers         => $workers,
                scoreboard      => $scoreboard,
                busy_worker_num => $busy_worker_num,
                idle_worker_num => $idle_worker_num,
                avg_req_per_sec => $avg_req_per_sec,
            })
        ] ];
    }
}

sub _collect_worker_info {
    my $ps = `LC_ALL=C command ps -o ppid,etime,pid,%cpu,%mem,command`;
    $ps =~ s/^\s+//mg;

    my $workers = [];
    for my $line (split /\n/, $ps) {
        next unless $line =~ /server-status/;
        my ($ppid, $etime, $pid, $cpu, $mem, $command) = split /\s+/, $line, 6;
        my ($name, $meta, $key, $client, $host, $method, $path, $proto) =
            $command =~ qr{^server-status\[([^]]+?)\] \(([^)]+?)\) (.)(?: ([^\s]+) ([^\s]+) ([^\s]+) ([^\s]+) ([^\s]+))?};

        next unless $name eq $ENV{SERVER_STATUS_CLASS};

        push @$workers, +{
            ppid   => $ppid,
            pid    => $pid,
            cpu    => $cpu,
            mem    => $mem,
            uptime => _uptime_sec($etime),

            name   => $name,
            meta   => +{ map { split /=/, $_, 2  } split /\s+/, $meta },
            key    => $key,
            client => $client || '',
            host   => $host   || '',
            method => $method || '',
            path   => $path   || '',
            proto  => $proto  || ''
        };
    }

    wantarray? @$workers : $workers;
}

sub _uptime_sec {
    my ($etime) = @_;
    # 5-10:10:10
    my ($day, $hour, $min, $sec) = ($etime =~ /(?:(?:(?:(\d+)-)(\d+):)?(\d+):)?(\d+)/);
    $day ||= 0; $hour ||= 0; $min ||= 0;
    my $uptime_sec = ($day * 24 * 60 * 60) + ($hour * 60 * 60) + ($min * 60) + $sec;
}

sub is_allowed {
    my ($self, $address) = @_;

    $self->{_cidr} ||= do {
        my $cidr = Net::CIDR::Lite->new;
        if ($self->cidr) {
            $cidr->add($_) for @{$self->cidr};
        } else {
            $cidr->add('10.0.0.0/8');
            $cidr->add('172.16.0.0/12');
            $cidr->add('192.168.0.0/16');
            $cidr->add('127.0.0.0/8');
        }
    };

    $self->{_cidr}->find($address);
}

1;
__END__

=head1 NAME

Plack::Middleware::ServerStatus - Show server status like Apache's mod_status

=head1 SYNOPSIS

  use Plack::Builder;

  builder {
      enable "Plack::Middleware::ServerStatus",
          path => '/server-status',
          cidr => [qw[127.0.0.0/8]];
      $app;
  };

=head1 DESCRIPTION

Show server status like Apache's mod_status which helps you to find best configuration of backend servers.

This middleware just parses C<ps> result as following:

  $ ps | grep server-status
  47167  7.8  0.4 S+ 0:00.15 server-status[let] (req=2) R ?       
  47164  0.0  0.5 S+ 0:00.35 server-status[let] (req=2) _ 127.0.0.1 local.hatena.ne.jp:5000 GET /debug_toolbar/jquery.js HTTP/1.1       
  47163  0.0  0.5 S+ 0:00.34 server-status[let] (req=2) _ 127.0.0.1 local.hatena.ne.jp:5000 GET /favicon.ico HTTP/1.1       
  47162  0.0  0.1 S+ 0:00.01 server-status[let] (req=1) _ 127.0.0.1 local.hatena.ne.jp:5000 GET /debug_toolbar/information.gif HTTP/1.1       
  47161  0.0  0.1 S+ 0:00.02 server-status[let] (req=1) _ 127.0.0.1 local.hatena.ne.jp:5000 GET /debug_toolbar/jquery.js HTTP/1.1       

Starman and Starlet (forked) supports this C<ps> format. You have to use C<server-status> branch of following repository because it is not include original repository master.

http://github.com/cho45/Starman/tree/server-status , http://github.com/cho45/Starlet/tree/server-status

Anyone not from LAN can't access this middleware, will get 403 forbidden response. You can customize it by C<cidr> option.

=head1 AUTHOR

cho45

=head1 SEE ALSO

L<Plack::Middleware> L<Plack::Builder>

=cut

