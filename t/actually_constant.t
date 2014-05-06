package TestConstant;
use strict;
use warnings;
use Constant::Export::Lazy (
    constants => {
        TRUE   => sub { 1 },
        FALSE  => sub { 0 },
        ARRAY  => sub { [qw/what like out/] },
        HASH   => sub {
            +{
                fmt => "The output from dumping the <%s> constant should match <%s>, full output is <%s>",
                out => "We shouldn't even have this in the syntax tree on -MO=Deparse",
            },
        },
    }
);

package main;
BEGIN {
    TestConstant->import(qw(
        TRUE
        FALSE
        ARRAY
        HASH
    ));
}
use Test::More 'no_plan';
use Data::Dump::Streamer;
# Maybe I'll want this later, but Data::Dump::Streamer is in
# TestRequires now, and I want to see where this actually works.
#
# BEGIN {
#     eval {
#         require Data::Dump::Streamer;
#         Data::Dump::Streamer->import;
#         1;
#     } or do {
#         my $error = $@ || "Zombie Error";
#         Test::More->import(skip_all => "We don't have Data::Dump::Streamer here, got <$error> trying to load it");
#     };
#     Test::More->import('no_plan');
# };

my @tests = (
    {
        what => 'TRUE',
        out => "" . Dump(\&TRUE)->Out,
        like => do {
            #use re 'debug';
            qr/^\$CODE1 = \\&Constant::Export::Lazy::Ctx::__ANON__;$/s;
        },
    },
    {
        what => 'FALSE',
        out => "" . Dump(\&FALSE)->Out,
        like => do {
            #use re 'debug';
            qr/^\$CODE1 = \\&Constant::Export::Lazy::Ctx::__ANON__;$/s;
        },
    },
    {
        what => 'ARRAY',
        out => "" . Dump(\&ARRAY)->Out,
        like => do {
            #use re 'debug';
            qr/^\$CODE1 = \\&Constant::Export::Lazy::Ctx::__ANON__;$/s;
        },
    },
    {
        what => 'HASH',
        out => "" . Dump(\&HASH)->Out,
        like => do {
            #use re 'debug';
            qr/^\$CODE1 = \\&Constant::Export::Lazy::Ctx::__ANON__;$/s;
        },
    },
);

if (TRUE) {
    for my $test (@tests) {
        my ($what, $like, $out) = @$test{@{ARRAY;}};
        chomp $out;
        like($out, qr/$like/, sprintf HASH->{fmt}, $what, $like, $out);
    }
} else {
    fail(HASH->{out});
}
