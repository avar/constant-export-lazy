package My::User::Code;
use strict;
use warnings;
use Test::More qw(no_plan);
use lib 't/lib';
BEGIN {
    # Supply a more accurate PI
    $ENV{PI} = 3.14159;
    # Override B
    $ENV{B} = 3;
}
use My::Constants qw(
    X
    Y
    A
    B
    SUM
    PI
);

is(X, -2);
is(Y, -1);
is(A, 1);
is(B, 3);
is(SUM, 4);
is(PI,  "Pi is = 3.14159");
