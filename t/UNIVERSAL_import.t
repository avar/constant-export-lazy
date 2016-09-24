package TestImportingWithUniversal;
use strict;
use warnings;
use Test::More tests => 3;
use UNIVERSAL; # Creates UNIVERSAL::import()
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
                UNUSED => sub { 1 },
            },
        );
        fail "We managed to import() under UNIVERSAL!";
        1;
    } or do {
        my $error = $@ || "Zombie Error";
        pass "We failed to import: <$error>";
        like($error, qr/We're trying to clobber an existing 'import' subroutine/, "We get a clobbering error without wrap_existing_import");
    };
    cmp_ok(scalar @warnings, '==', 0, "We should get no warnings when importing with UNIVERSAL in effect");
}
