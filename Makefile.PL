use inc::Module::Install;
name 'Plack-Middleware-ServerStatus';
all_from 'lib/Plack/Middleware/ServerStatus.pm';

requires 'parent';
requires 'Plack';
requires 'Text::MicroTemplate';
requires 'Net::CIDR::Lite';

build_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;
