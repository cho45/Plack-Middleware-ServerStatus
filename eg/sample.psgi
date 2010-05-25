#!/usr/bin/env PERL5LIB=/Users/cho45/project/Starman/lib SERVER_STATUS_CLASS=sample plackup -s Starman -p 5000 --workers=10 
# :vim:set ft=perl:
use strict;
use warnings;
use lib 'lib';

use Plack::Builder;

builder {
    enable "Plack::Middleware::ServerStatus";

    sub {
        my $env = shift;
        [ 200, [ 'Content-Type' => 'text/plain' ], [
            'Hello, World!'
        ] ];
    }
};

__END__

