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
        # This is the simplest way to go, just define plain constant
        # values.
        A => sub { 1 },
        B => sub { 2 },
        # You get a $ctx object that you can ->call() to retrieve the
        # values of other constants. This is how you can make some
        # constants depend on others without worrying about
        # ordering. Constants are still guaranteed to only be
        # fleshened once!
        SUM => sub {
            my ($ctx) = @_;
            $ctx->call('A') + $ctx->call('B'),
        },
        # We won't call this and die unless someone requests it when
        # they import us.
        DIE => sub { die },
        # These subroutines are always called in scalar context, and
        # thus We'll return [3..4] here.
        #
        # Unlike the constant.pm that ships with perl itself we don't
        # support returning lists (there's no such things as constant
        # list subroutines, constant.pm fakes it with a non-inlined
        # sub). So if you want to return lists you have to return a
        # reference to one.
        LIST => sub { wantarray ? (1..2) : [3..4] },
        # We can also supply a HashRef with "call" with the sub, and
        # "options" with options that clobber the global
        # options. Actually when you supply just a plain sub instead
        # of a HashRef we internally munge it to look like this more
        # verbose (and more flexible) structure.
        PI  => {
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
