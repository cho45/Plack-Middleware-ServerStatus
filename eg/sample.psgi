#!/usr/bin/env STARMAN_DEBUG=1 PERL5LIB=/Users/cho45/project/Starman/lib SERVER_STATUS_CLASS=sample starman -p 5000 --workers=1
# :vim:set ft=perl:
use strict;
use warnings;
use lib 'lib';

use Plack::Builder;

builder {
    enable "Plack::Middleware::ServerStatus", path => '/ss';
    enable "Plack::Middleware::ContentLength";


    sub {
        my $env = shift;
        [ 200, [ 'Content-Type' => 'text/plain' ], [
            'Hello, World!'
        ] ];
    }
};

__END__

