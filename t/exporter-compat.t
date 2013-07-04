package TestSimple;
use strict;
use warnings;
use Exporter 'import';
our $CALL_COUNTER;
our (@EXPORT, @EXPORT_OK);
BEGIN {
    @EXPORT    = qw(CONST_123 CONST_456);
    @EXPORT_OK = (@EXPORT, qw(CONST_789));
}
use constant {
    CONST_123 => 123,
    CONST_456 => 456,
    CONST_789 => 789,
};
use Constant::Export::Lazy (
    constants => {
        LAZY_123 => sub { $CALL_COUNTER++; 123 },
        LAZY_456 => sub { $CALL_COUNTER++; 456 },
        LAZY_579 => sub {
            $CALL_COUNTER++;
            my ($ctx) = @_;
            $ctx->call('LAZY_123') + $ctx->call('LAZY_456');
        },
    },
    options => {
        wrap_existing_import => 1,
    },
);

package main;
use strict;
use warnings;
use lib 't/lib';
use Test::More 'no_plan';
BEGIN { $ENV{TEST_CONSTANT_VARIABLE} = 2 }
BEGIN {
    TestSimple->import(qw(
        CONST_123
        CONST_456
        CONST_789
        LAZY_123
        LAZY_456
        LAZY_579
    ))
}

is(LAZY_123, 123, "Got lazy 123");
is(LAZY_456, 456, "Got lazy 456");
is(LAZY_579, 579, "Got lazy 579");
is(CONST_123, 123, "Got const 123");
is(CONST_456, 456, "Got const 456");
is(CONST_789, 789, "Got const 789");
