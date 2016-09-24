package TestImportingBase;
use strict;
use warnings;

sub import { die "Calling the base class's import routine!" }

package TestImportingWithBase;
use strict;
use warnings;
use base qw(TestImportingBase);
use Test::More tests => 4;
BEGIN {
    my @warnings;
    eval {
        local $SIG{__WARN__} = sub {
            chomp(my ($warn) = @_);
            push @warnings => $warn;
            return;
        };
        require Constant::Export::Lazy;
        Constant::Export::Lazy->import(
            constants => {
                CONSTANT => sub { 1234 },
            },
            options => {
                wrap_existing_import => 1,
            },
        );
        pass "We managed to import() into a class that has a base class with an import()!";
        1;
    } or do {
        my $error = $@ || "Zombie Error";
        fail "We failed to import: <$error>";
    };
    cmp_ok(scalar @warnings, '==', 0, "We should get no warnings when importing into a class that has a base class with an import()");

    TestImportingWithBase->import('CONSTANT');
    is(CONSTANT(), 1234, "We got the right value for CONSTANT");
    eval {
        TestImportingWithBase->import('UNKNOWN');
        1;
    } or do {
        my $error = $@ || "Zombie Error";
        like($error, qr/^Calling the base class's import routine/, "We called the base class's import routine on UNKNOWN");
    };
}
