package TestConstant;
use strict;
use warnings;
use Test::More 'no_plan';
use FindBin qw($Bin);

chomp(my $output = qx[$^X -I"$Bin/../lib" -MO=Deparse "$Bin/actually_constant.t" 2>/dev/null]);
ok($output, "The deparse output we got was: $output");
like($output, qr/use Constant::Export::Lazy/, "Is this thing on?");
unlike($output, qr/\bARRAY;/, "Our output should have the ARRAY; call optimized out");
like($output, qr/'what', 'like', 'out'/, "That ARRAY; call should be inlined");
unlike($output, qr/\bfail\b/, "Our output should have the fail() call optimized out");
