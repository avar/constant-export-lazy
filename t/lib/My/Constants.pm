package My::Constants;
use strict;
use warnings;
use Exporter 'import';
use constant {
    X => -2,
    Y => -1,
};
our @EXPORT_OK = qw(X Y);
use Constant::Export::Lazy (
    constants => {
        A => sub { 1 },
        B => sub { 2 },
        SUM => sub {
            # You get a $ctx object that you can ->call() to retrieve
            # the values of other constants if some of your constants
            # depend on others. Constants are still guaranteed to only
            # be fleshened once!
            my ($ctx) = @_;
            $ctx->call('A') + $ctx->call('B'),
        },
        # We won't call this and die unless someone requests it when
        # they import us.
        DIE => sub { die },
        PI  => {
            # We can also supply a HashRef with "call" with the sub,
            # and "options" with options that clobber the global
            # options.
            call    => sub { 3.14 },
            options => {
                override => sub {
                    my ($ctx, $name) = @_;
                    # You can simply "return;" here to say "I don't
                    # want to override", and "return undef;" if you
                    # want the constant to be undef.
                    return $ENV{PI} ? "Pi is = $ENV{PI}" : $ctx->call($name);
                },
            },
        },
    },
    options => {
        # We're still exporting some legacy constants via Exporter.pm
        wrap_existing_import => 1,
        # A general override so you can override other constants in
        # %ENV
        override => sub {
            my ($ctx, $name) = @_;
            return unless exists $ENV{$name};
            return $ENV{$name};
        },
    },
);

1;
