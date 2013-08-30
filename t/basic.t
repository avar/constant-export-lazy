package TestSimple;
use strict;
use warnings;
our $CALL_COUNTER;
our $AFTER_COUNTER;
our $AFTER_OVERRIDE_COUNTER;
use Exporter 'import';
use constant {
    CONST_OLD_1 => 123,
    CONST_OLD_2 => 456,
};
BEGIN {
    our @EXPORT_OK = qw(CONST_OLD_1 CONST_OLD_2);
}
use Constant::Export::Lazy (
    constants => {
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
        TEST_CONSTANT_RECURSIVE => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            $ctx->call('TEST_CONSTANT_VARIABLE') + 1;
        },
        DO_NOT_CALL_THIS => sub {
            $CALL_COUNTER++;
            die "This should not be called";
        },
        TEST_CONSTANT_OVERRIDDEN_ENV_NAME => {
            options => {
                override => sub {
                    my ($ctx, $name) = @_;

                    if (exists $ENV{OVERRIDDEN_ENV_NAME}) {
                        my $value = $ctx->call($name);
                        return $ENV{OVERRIDDEN_ENV_NAME} + $value;
                    }
                    return;
                },
            },
            call => sub {
                $CALL_COUNTER++;
                39;
            },
        },
        TEST_AFTER_OVERRIDE => {
            options => {
                after => sub {
                    $AFTER_COUNTER++;
                    $AFTER_OVERRIDE_COUNTER++;
                    return;
                },
            },
            call => sub {
                $CALL_COUNTER++;
                123456;
            },
        },
    },
    options => {
        wrap_existing_import => 1,
        override => sub {
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

package main;
use strict;
use warnings;
use lib 't/lib';
use Test::More 'no_plan';
BEGIN {
    $ENV{TEST_CONSTANT_VARIABLE} = 2;
    $ENV{OVERRIDDEN_ENV_NAME} = 3;
}
BEGIN {
    TestSimple->import(qw(
        CONST_OLD_1
        CONST_OLD_2
        TEST_CONSTANT_CONST
        TEST_CONSTANT_VARIABLE
        TEST_CONSTANT_RECURSIVE
        TEST_CONSTANT_OVERRIDDEN_ENV_NAME
        TEST_AFTER_OVERRIDE
    ))
}

is(CONST_OLD_1, 123, "We got a constant from the Exporter::import");
is(CONST_OLD_2, 456, "We got a constant from the Exporter::import");
is(TEST_CONSTANT_CONST, 1, "Simple constant sub");
is(TEST_CONSTANT_VARIABLE, 6, "Constant composed with some variables");
is(TEST_CONSTANT_RECURSIVE, 7, "Constant looked up via \$ctx->call(...)");
is(TEST_CONSTANT_OVERRIDDEN_ENV_NAME, 42, "We properly defined a constant with some overriden options");
is($TestSimple::CALL_COUNTER, 5, "We didn't redundantly call various subs, we cache them in the stash");
is($TestSimple::AFTER_COUNTER, $TestSimple::CALL_COUNTER, "Our AFTER counter is always the same as our CALL counter, we only call this for interned values");
is(TEST_AFTER_OVERRIDE, 123456, "We have TEST_AFTER_OVERRIDE defined");
is($TestSimple::AFTER_OVERRIDE_COUNTER, 1, "We correctly call 'after' overrides");
