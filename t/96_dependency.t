use Test::Dependencies
	exclude => [qw/Test::Dependencies Test::Base Test::Perl::Critic Plack::Middleware::ServerStatus/],
	style   => 'light';
ok_dependencies();
