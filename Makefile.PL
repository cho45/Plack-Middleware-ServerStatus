use inc::Module::Install;
name 'Plack-Middleware-ServerStatus';
all_from 'lib/Plack/Middleware/ServerStatus.pm';

requires $_ for (qw/ /);

build_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;
