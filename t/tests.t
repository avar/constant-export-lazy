package TestSimple;
use strict;
use warnings;
our $CALL_COUNTER;
our $AFTER_COUNTER;
our $OVERRIDE_COUNTER;
our $AFTER_OVERRIDE_COUNTER;
use Exporter 'import';
use constant {
    CONST_OLD_1 => 123,
    CONST_OLD_2 => 456,
    CONST_OLD_3 => [123, 456],
    CONST_OLD_4 => {int => 789},
};
use constant CONST_OLD_5 => (123, 456, 789);
sub CONST_OLD_6 () { 123 }
sub CONST_OLD_7 () { 456 }
sub CONST_OLD_8 () { [123, 456] }
sub CONST_OLD_9 () { +{int => 789} }
sub CONST_OLD_10 () { [123, 456, 789] }
sub CONST_OLD_10_bad () { +(123, 456, 789) }
BEGIN {
    our @EXPORT_OK = qw(CONST_OLD_1 CONST_OLD_2);
}
use Constant::Export::Lazy (
    constants => {
        TEST_CONSTANT_USE_CONSTANT_PM => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            my $refs_sum = (
                $ctx->call('CONST_OLD_1')
                +
                $ctx->call('CONST_OLD_2')
                +
                $ctx->call('CONST_OLD_3')->[0]
                +
                $ctx->call('CONST_OLD_3')->[1]
                +
                $ctx->call('CONST_OLD_4')->{int}
            );
            my $list_sum;
            $list_sum += $_ for @{$ctx->call('CONST_OLD_5')};
            return $refs_sum + $list_sum;
        },
        TEST_CONSTANT_MANUAL_CONSTANT => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            my $refs_sum = (
                $ctx->call('CONST_OLD_6')
                +
                $ctx->call('CONST_OLD_7')
                +
                $ctx->call('CONST_OLD_8')->[0]
                +
                $ctx->call('CONST_OLD_8')->[1]
                +
                $ctx->call('CONST_OLD_9')->{int}
            );
            my $list_sum;
            # Unlike CONST_OLD_5 this isn't some magical ArrayRef in
            # the symbol table, it's just a list, so we'll get the
            # last item.
            $list_sum += $_ for @{$ctx->call('CONST_OLD_10')};
            return $refs_sum + $list_sum;
        },
        CONST_OLD_10_BAD_WRAPPER => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            my $error = '';
            eval {
                $ctx->call('CONST_OLD_10_bad');
                1;
            } or do {
                $error = $@;
            };
            return $error;
        },
        TEST_CONSTANT_CONST => sub {
            $CALL_COUNTER++;
            1;
        },
        TEST_CONSTANT_VARIABLE => sub {
            $CALL_COUNTER++;
            my $x = 1;
            my $y = 2;
            $x + $y;
        },
        TEST_CONSTANT_REQUESTED => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            $ctx->call('TEST_CONSTANT_NOT_REQUESTED');

        },
        TEST_CONSTANT_NOT_REQUESTED => sub {
            $CALL_COUNTER++;
            98765;
        },
        TEST_CONSTANT_RECURSIVE => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            $ctx->call('TEST_CONSTANT_VARIABLE') + 1;
        },
        TEST_LIST => sub {
            $CALL_COUNTER++;
            wantarray ? (1..2) : [3..4];
        },
        DO_NOT_CALL_THIS => sub {
            $CALL_COUNTER++;
            die "This should not be called";
        },
        TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME => {
            # We should not only call but also intern this constant.
            options => {
                after => sub {
                    $AFTER_COUNTER++;
                    return;
                },
                override => sub {
                    $OVERRIDE_COUNTER++;
                    my ($ctx, $name) = @_;
                    # We should still call overrides for things that
                    # are called from *other* stuff that's being
                    # overriden.
                    return 1 + $ctx->call($name);
                },
            },
            call => sub {
                $CALL_COUNTER++;
                1;
            },
        },
        TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME_NAME_MUNGED => {
            # We should not only call but also intern this constant.
            options => {
                after => sub {
                    $AFTER_COUNTER++;
                    return;
                },
                override => sub {
                    $OVERRIDE_COUNTER++;
                    my ($ctx, $name) = @_;
                    # We should still call overrides for things that
                    # are called from *other* stuff that's being
                    # overriden.
                    return 1 + $ctx->call($name);
                },
                private_name_munger => sub {
                    my ($gimme) = @_;
                    return '__INTERNAL__' . $gimme;
                },
            },
            call => sub {
                $CALL_COUNTER++;
                1;
            },
        },
        TEST_CONSTANT_OVERRIDDEN_ENV_NAME => {
            options => {
                override => sub {
                    $OVERRIDE_COUNTER++;
                    my ($ctx, $name) = @_;

                    if (exists $ENV{OVERRIDDEN_ENV_NAME}) {
                        my $value = (
                            $ctx->call($name)
                            +
                            $ctx->call('TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME')
                            +
                            $ctx->call('TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME_NAME_MUNGED')
                        );
                        return $ENV{OVERRIDDEN_ENV_NAME} + $value;
                    }
                    return;
                },
            },
            call => sub {
                $CALL_COUNTER++;
                37;
            },
        },
        TEST_AFTER_OVERRIDE => {
            options => {
                after => sub {
                    $AFTER_COUNTER++;
                    $AFTER_OVERRIDE_COUNTER++;
                    return;
                },
                stash => {
                    some_value => 123456,
                },
            },
            call => sub {
                my ($ctx) = @_;
                $CALL_COUNTER++;
                $ctx->stash->{some_value};
            },
        },
        TEST_NO_STASH => {
            call => sub {
                my ($ctx) = @_;
                $CALL_COUNTER++;
                $ctx->stash;
            },
        },
        TEST_NO_AFTER_NO_OVERRIDE => {
            call => sub {
                $CALL_COUNTER++;
                'no_after_no_override';
            },
            options => {
                after => undef,
                override => undef,
            },
        },
        TEST_BAD_CALL_PARAMETER => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            my $error = '';
            eval {
                $ctx->call('THIS_CONSTANT_DOES_NOT_EXIST');
                1;
            } or do {
                $error = $@;
            };
            return $error;
        },
    },
    options => {
        wrap_existing_import => 1,
        override => sub {
            $OVERRIDE_COUNTER++;
            my ($ctx, $name) = @_;

            if (exists $ENV{$name}) {
                my $value = $ctx->call($name);
                return $ENV{$name} * $value;
            }
            return;
        },
        after => sub {
            my ($ctx, $name, $value, $source) = @_;
            $AFTER_COUNTER++;

            return;
        },
    },
);

package TestSimple::Subclass;
use strict;
use warnings;
BEGIN { our @ISA = qw(TestSimple) }

package TestSimple::NoOptions;
use strict;
use warnings;

use Constant::Export::Lazy (
    constants => {
        TEST_CONSTANT_NO_OPTIONS => sub { "no options" }
    },
);

package TestSimple::NoWrapExistingImport;
use strict;
use warnings;

use Constant::Export::Lazy (
    constants => {
        TEST_BAD_CALL_PARAMETER_NO_WRAP_EXISTING_IMPORT => sub {
            my ($ctx) = @_;
            my $error = '';
            eval {
                $ctx->call('THIS_CONSTANT_DOES_NOT_EXIST');
                1;
            } or do {
                $error = $@;
            };
            return $error;
        },
    },
    options => {
        # Just an empty hash to provide more coverage
    },
);

package TestSimple::InvalidWrapExistingImport;
use strict;
use warnings;

BEGIN {
    eval {
        Constant::Export::Lazy->import(
            constants => {},
            options => {
                wrap_existing_import => 1,
            },
        );
        1;
    } or do {
        $main::InvalidWrapExistingImport_error = $@;
    };
}

package TestSimple::ClobberingWithoutWrapExistingImport;
use strict;
use warnings;

sub import {}

BEGIN {
    eval {
        Constant::Export::Lazy->import(
            constants => {},
        );
        1;
    } or do {
        $main::ClobberingWithoutWrapExistingImport_error = $@;
    };
}

package TestSimple::InvalidConstant;
use strict;
use warnings;

BEGIN {
    eval {
        Constant::Export::Lazy->import(
            constants => {
                CONSTANT_NAME => [], # can only be CODE or HASH
            },
        );
        1;
    } or do {
        $main::InvalidConstant_error = $@;
    };
}

package TestSimple::InvalidConstantMoarTestCoverage;
use strict;
use warnings;

BEGIN {
    eval {
        Constant::Export::Lazy->import(
            constants => {
                CONSTANT_NAME => undef, # can only be CODE or HASH, and not a non-ref
            },
        );
        1;
    } or do {
        $main::InvalidConstantMoarTestCoverage_error = $@;
    };
}

package main;
use strict;
use warnings;
use lib 't/lib';
use Test::More 'no_plan';
BEGIN {
    $ENV{TEST_CONSTANT_VARIABLE} = 2;
    $ENV{OVERRIDDEN_ENV_NAME} = 1;
}
BEGIN {
    TestSimple->import(qw(
        CONST_OLD_1
        CONST_OLD_2
        TEST_CONSTANT_USE_CONSTANT_PM
        TEST_CONSTANT_MANUAL_CONSTANT
        CONST_OLD_10_BAD_WRAPPER
        TEST_CONSTANT_CONST
        TEST_CONSTANT_VARIABLE
        TEST_CONSTANT_RECURSIVE
        TEST_CONSTANT_OVERRIDDEN_ENV_NAME
        TEST_AFTER_OVERRIDE
        TEST_CONSTANT_REQUESTED
        TEST_LIST
        TEST_NO_STASH
        TEST_NO_AFTER_NO_OVERRIDE
        TEST_BAD_CALL_PARAMETER
    ));
    for my $pkg (qw(TestSimple TestSimple::NoOptions)) {
        eval {
            $pkg->import('THIS_CONSTANT_DOES_NOT_EXIST');
            1;
        } or do {
            my $error = $@ || "Zombie Error";
            my $desc = "Calling import() with invalid constant";
            if ($pkg eq 'TestSimple') {
                like($error, qr/"THIS_CONSTANT_DOES_NOT_EXIST" is not exported by the $pkg module/, "$desc with wrap_existing_import");
            } elsif ($pkg eq 'TestSimple::NoOptions') {
                like($error, qr/PANIC: We don't have the constant 'THIS_CONSTANT_DOES_NOT_EXIST' to export to you/, "$desc without wrap_existing_import");
            } else {
                die "PANIC";
            }
        };
    }
    TestSimple::NoOptions->import(qw(
        TEST_CONSTANT_NO_OPTIONS
    ));
    TestSimple::NoWrapExistingImport->import(qw(
        TEST_BAD_CALL_PARAMETER_NO_WRAP_EXISTING_IMPORT
    ));
}

is(CONST_OLD_1, 123, "We got a constant from the Exporter::import");
is(CONST_OLD_2, 456, "We got a constant from the Exporter::import");
is(TEST_CONSTANT_USE_CONSTANT_PM, 123 + 456 + 123 + 456 + 789 + 123 + 456 + 789, "We can use ->call() on Exporter::import constant.pm constants");
is(TEST_CONSTANT_MANUAL_CONSTANT, 123 + 456 + 123 + 456 + 789 + 123 + 456 + 789, "We can use ->call() on Exporter::import manual constants");
like(CONST_OLD_10_BAD_WRAPPER, qr/^PANIC.*CONST_OLD_10_bad returns 3 values/, "We don't support non-scalar returning subs");
is(TEST_CONSTANT_CONST, 1, "Simple constant sub");
is(TEST_CONSTANT_VARIABLE, 6, "Constant composed with some variables");
is(TEST_CONSTANT_RECURSIVE, 7, "Constant looked up via \$ctx->call(...)");
is(TEST_CONSTANT_OVERRIDDEN_ENV_NAME, 42, "We properly defined a constant with some overriden options");
ok(exists &TestSimple::TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME, "We fleshened unrelated TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME though");
ok(exists &TestSimple::__INTERNAL__TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME_NAME_MUNGED, "..and its __INTERNAL__TEST_CONSTANT_CALLED_FROM_OVERRIDDEN_ENV_NAME_NAME_MUNGED sibling with an overridden name");
is(TEST_CONSTANT_REQUESTED, 98765, "Our requested constant has the right value");
ok(!exists &TEST_CONSTANT_NOT_REQUESTED, "We shouldn't import TEST_CONSTANT_NOT_REQUESTED into this namespace...");
is(TestSimple::TEST_CONSTANT_NOT_REQUESTED, 98765, "...but it should be defined in TestSimple::* so it'll be re-used as well");
is(join(",", @{TEST_LIST()}), '3,4');
is(TEST_NO_STASH, undef, "We'll return undef if we have no stash");
is(TEST_NO_AFTER_NO_OVERRIDE, 'no_after_no_override', "A constant that didn't call 'after' or 'override'");
like(TEST_BAD_CALL_PARAMETER, qr/^PANIC.*THIS_CONSTANT_DOES_NOT_EXIST has no symbol table entry/, "Non-existing constant under wrap_existing_import");

# Afterwards check that the counters are OK
our $call_counter = 16;
our $after_and_override_call_counter = $call_counter - 1;
is($TestSimple::CALL_COUNTER, $call_counter, "We didn't redundantly call various subs, we cache them in the stash");
is($TestSimple::AFTER_COUNTER, $after_and_override_call_counter, "Our AFTER counter is always the same as our CALL counter (unless 'after' is clobbered), we only call this for interned values");
is(TEST_AFTER_OVERRIDE, 123456, "We have TEST_AFTER_OVERRIDE defined");
is($TestSimple::AFTER_OVERRIDE_COUNTER, 1, "We correctly call 'after', except when they've been clobbered");
is($TestSimple::OVERRIDE_COUNTER, $after_and_override_call_counter, "We correctly call overrides, except when they've been clobbered");

# Other tests of custom Constant::Export::Lazy pacakges for added
# coverage.
is(TEST_CONSTANT_NO_OPTIONS, "no options", "A Constant::Export::Lazy with no options => {}");
like(TEST_BAD_CALL_PARAMETER_NO_WRAP_EXISTING_IMPORT, qr/^PANIC.*unknown constant/, "A Constant::Export::Lazy with no wrap_existing_import with invalid ->call()");
like($main::InvalidWrapExistingImport_error, qr/^PANIC.*We need an existing 'import' with the wrap_existing_import/, "wrap_existing_import assertion");
like($main::ClobberingWithoutWrapExistingImport_error, qr/^PANIC:.*trying to clobber an existing 'import' subroutine/, "Clobbering import without wrap_existing_import");
like($main::InvalidConstant_error, qr/^PANIC.*has some value type we don't know about.*ref = ARRAY/, "Calling import with invalid constants");
like($main::InvalidConstantMoarTestCoverage_error, qr/^PANIC.*has some value type we don't know about.*ref = Undef/, "Calling import with invalid constants (Undef)");

package main::frame;
use strict;
use warnings;
BEGIN {
    TestSimple::Subclass->import(qw(
        TEST_CONSTANT_CONST
    ))
}

main::is(TEST_CONSTANT_CONST, 1, "Simple constant sub for subclass testing");

# Afterwards check that the counters are OK
main::is($TestSimple::CALL_COUNTER, $main::call_counter, "We didn't redundantly call various subs, we cache them in the stash, even if someone subclasses the class");
main::is($TestSimple::AFTER_COUNTER, $main::after_and_override_call_counter, "Our AFTER counter is always the same as our CALL counter (unless 'after' is clobbered), we only call this for interned values, even if someone subclasses the class");
