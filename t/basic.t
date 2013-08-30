package TestSimple;
use strict;
use warnings;
our $CALL_COUNTER;
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
    },
    options => {
        override => sub {
            my ($ctx, $name) = @_;

            if (exists $ENV{$name}) {
                my $value = $ctx->call($name);
                return $ENV{$name} * $value;
            }
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
        TEST_CONSTANT_CONST
        TEST_CONSTANT_VARIABLE
        TEST_CONSTANT_RECURSIVE
        TEST_CONSTANT_OVERRIDDEN_ENV_NAME
    ))
}

is(TEST_CONSTANT_CONST, 1, "Simple constant sub");
is(TEST_CONSTANT_VARIABLE, 6, "Variadic, should still be constant, TODO check that");
is(TEST_CONSTANT_RECURSIVE, 7, "A constant sub that's recursive");
is(TEST_CONSTANT_OVERRIDDEN_ENV_NAME, 42, "We properly defined a constant with some overriden options");
is($TestSimple::CALL_COUNTER, 4, "We didn't redundantly call various subs, we cache them in the stash");
