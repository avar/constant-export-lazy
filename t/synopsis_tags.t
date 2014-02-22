package My::More::User::Code;
use strict;
use warnings;
use Test::More qw(no_plan);
use lib 't/lib';
use My::Constants::Tags qw(
    KG_TO_MG
    :math
    :alphabet
);

is(KG_TO_MG, 10**6);
is(A, "A");
is(B, "B");
is(C, "C");
like(PI, qr/^3\.14/);
