package Constant::Export::Lazy;
use strict;
use warnings;

sub import {
    my ($class, %args) = @_;
    my $caller = caller;

    # Are we wrapping an existing import subroutine?
    my $wrap_existing_import = (
        exists $args{options}
        ? exists $args{options}->{wrap_existing_import}
          ? $args{options}->{wrap_existing_import}
          : 0
        : 0
    );
    my $existing_import;
    my $caller_import_name = $caller . '::import';

    # Sanity check whether we do or don't have an existing 'import'
    # sub with the wrap_existing_import option:
    my $has_import_already = do { no strict 'refs'; *{$caller_import_name}{CODE} } ? 1 : 0;
    {
        if ($wrap_existing_import) {
            die "PANIC: We need an existing 'import' with the wrap_existing_import option" unless $has_import_already;
            $existing_import = \&{$caller_import_name};
        } else {
            die "PANIC: We're trying to clobber some existing 'import' subroutine without having the 'wrap_existing_import' option" if $has_import_already;
        }
    }

    # Munge the %args we're given so users can be lazy and give sub {
    # ... } as the value for the constants, but internally we support
    # them being a HashRef with options for each one. Allows us to be
    # lazy later by flattening this whole thing now.
    my $normalized_args = _normalize_arguments(%args);
    my $constants = $normalized_args->{constants};

    no strict 'refs';
    no warnings 'redefine'; # In case of $wrap_existing_import
    *{$caller_import_name} = sub {
        use strict;
        use warnings;

        my (undef, @gimme) = @_;
        my $pkg_importer = caller;

        my $ctx = Constant::Export::Lazy::Ctx->new(
            constants    => $constants,
            pkg_importer => $pkg_importer,

            # Note that when unpacking @_ above we threw away the
            # package we're imported as from the user's perspective
            # and are using our "real" calling package for $pkg_stash
            # instead.
            #
            # This is because if we have a My::Constants package as
            # $caller but someone subclasses My::Constants for
            # whatever reason as say My::Constants::Subclass we don't
            # want to be sticking generated subroutines in both the
            # My::Constants and My::Constants::Subclass namespaces.
            #
            # This is because we want to guarantee that we only ever
            # call each generator subroutine once, even in the face of
            # subclassing. Maybe I should lift this restriction or
            # make it an option, e.g. if you want to have a constant
            # for "when I was compiled" it would be useful if
            # subclassing actually re-generated constants.
            pkg_stash => $caller,

            # This is the symbol table for the package that's implementing
            # the constant exporter, not the user package requesting
            # constant to be exported to it.
            #
            # Really important distinction because we never want to
            # re-generate the same constant again when another package
            # requests it.
            symtab => do {
                no strict 'refs';
                \%{"${caller}::"};
            },
        );

        # Just doing ->call() like you would when you're using the API
        # will fleshen the constant, do this for all the constants
        # we've been requested to export.
        my @leftover_gimme;
        for my $gimme (@gimme) {
            if (exists $constants->{$gimme}) {
                $ctx->call($gimme);
            } elsif ($wrap_existing_import) {
                push @leftover_gimme => $gimme;
            } else {
                die "PANIC: We don't have the constant '$gimme' to export to you";
            }
        }

        if ($wrap_existing_import and @leftover_gimme) {
            # Because if we want to eliminate a stack frame *AND* only
            # dispatch to this for some things we have to partition
            # the import list into shit we can handle and shit we
            # can't. The list of things we're making the function
            # we're overriding handle is @leftover_gimme.
            @_ = ($caller, @leftover_gimme);
            goto &$existing_import;
        }

        return;
    };

    return;
}

sub _normalize_arguments {
    my (%args) = @_;

    my %default_options = %{ $args{options} || {} };
    my $constants = $args{constants};
    my %new_constants;
    for my $constant_name (keys %$constants) {
        my $value = $constants->{$constant_name};
        if (ref $value eq 'CODE') {
            $new_constants{$constant_name} = {
                call    => $value,
                options => \%default_options,
            };
        } elsif (ref $value eq 'HASH') {
            $new_constants{$constant_name} = {
                call    => $value->{call},
                options => {
                    %default_options,
                    %{ $value->{options} || {} },
                },
            };
        } else {
            die sprintf "PANIC: The constant <$constant_name> has some value type we don't know about (ref = %s)",
                ref $value || 'Undef';
        }
    }

    $args{constants} = \%new_constants;

    return \%args;
}

package Constant::Export::Lazy::Ctx;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    bless \%args => $class;
}

our $CALL_SHOULD_NOT_ALIAS;
our $GETTING_VALUE_FOR_OVERRIDE = {};

sub call {
    my ($ctx, $gimme) = @_;

    # Unpack our options
    my $symtab       = $ctx->{symtab};
    my $pkg_importer = $ctx->{pkg_importer};
    my $pkg_stash    = $ctx->{pkg_stash};
    my $constants    = $ctx->{constants};

    my $glob_name = "${pkg_stash}::${gimme}";
    my $alias_as  = "${pkg_importer}::${gimme}";

    my $value;
    if (exists $symtab->{$gimme}) {
        my $symtab_value = $symtab->{$gimme};
        if (ref $symtab_value eq 'SCALAR') {
            # This is in case $ctx->call() is used on a constant
            # defined by constant.pm. See the giant comment about
            # constant.pm below.
            $value = $$symtab_value;
        } else {
            # TODO: Is there some better way to check if this is a
            # code value than just "ne 'SCALAR'"?
            $value = &$symtab_value();
        }
    } else {
        # We only want to alias constants into the importer's package
        # if the constant is on the import list, not if it's just
        # needed within some $ctx->call() when defining another
        # constant.
        local $CALL_SHOULD_NOT_ALIAS = 1;

        my $override = $constants->{$gimme}->{options}->{override};
        my $stash    = $constants->{$gimme}->{options}->{stash};

        # Only pass the stash around if we actually have it. Note that
        # "delete local $ctx->{stash}" is a feature new in 5.12.0, so
        # we can't use it. See
        # http://perldoc.perl.org/5.12.0/perldelta.html#delete-local
        local $ctx->{stash} = $stash;
        delete $ctx->{stash} unless ref $stash;

        my @overriden_value;
        my $source;
        if ($override and not exists $GETTING_VALUE_FOR_OVERRIDE->{$gimme}) {
            local $GETTING_VALUE_FOR_OVERRIDE->{$gimme} = undef;
            @overriden_value = $override->($ctx, $gimme);
        }
        if (@overriden_value) {
            die "PANIC: We should only get one value returned from the override callback" if @overriden_value > 1;

            # This whole single value as an array business is so we
            # can distinguish between "return;" meaning "I don't want
            # to override this" and "return undef;" meaning "I want to
            # override this, to undef".
            $source = 'override';
            $value = $overriden_value[0];
        } else {
            $source = 'callback';
            $value = $constants->{$gimme}->{call}->($ctx);
        }

        unless (exists $GETTING_VALUE_FOR_OVERRIDE->{$gimme}) {
            # Instead of doing `sub () { $value }` we could also
            # use the following trick that constant.pm uses if
            # it's true that `$] > 5.009002`:
            #
            #     Internals::SvREADONLY($value, 1);
            #     $symtab->{$gimme} = \$value;
            #
            # This would save some space for perl when producing
            # these inline constants. The reason I'm not doing
            # this is basically because it looks like evil
            # sorcery, and I don't want to go through the hassle
            # of efficiently and portibly invalidating the MRO
            # cache (see $flush_mro in constant.pm).
            #
            # Relevant commits in perl.git:
            #
            #  * perl-5.005_02-225-g779c5bc - first core support
            #    for these kinds of constants in the optree.
            #
            # * perl-5.8.0-6623-ge040ff7 - first use in
            #   constant.pm.
            #
            # * perl-5.8.0-6638-ge1234d8 - first attempts to
            #   invalidate the method cache with
            #   Internals::inc_sub_generation()
            #
            # * perl-5.8.0-10189-ge1a479c -
            #   Internals::inc_sub_generation() in constant.pm
            #   replaced with mro::method_changed_in($pkg)
            #
            #  * perl-5.8.0-10219-g41892db - Now unused
            #    Internals::inc_sub_generation() removed from the
            #    core.
            #
            # * v5.10.0-3508-gf7fd265 (and v5.10.0-3523-g81a8de7)
            #   - MRO cache is changed to be flushed after all
            #   constants are defined.
            #
            # * v5.19.2-130-g94d5c17, v5.19.2-132-g6f1b3ab,
            #   v5.19.2-133-g15635cb, v5.19.2-134-gf815dc1 -
            #   Father Chrysostomos making various list constant
            #   changes, backed out in v5.19.2-204-gf99a5f0 due to
            #   perl #119045:
            #   https://rt.perl.org/rt3/Public/Bug/Display.html?id=119045
            #
            # So basically it looks like a huge can of worms that
            # I don't want to touch now. So just create constants
            # in the more portable and idiot-proof way instead so
            # I don't have to duplicate all the logic in
            # constant.pm
            {
                # Make the disabling of strict have as small as scope
                # as possible.
                no strict 'refs';
                *$glob_name = sub () { use strict; $value };
            }

            # Maybe we have a callback that wants to know when we define
            # our constants, e.g. for printing something out, keeping taps
            # of what constants we have etc.
            if (my $after = $constants->{$gimme}->{options}->{after}) {
                # Future-proof so we can do something clever with the
                # return value in the future if we want.
                my @ret = $after->($ctx, $gimme, $value, $source);
                die "PANIC: Don't return anything from 'after' routines" if @ret;
            }
        }
    }

    unless ($CALL_SHOULD_NOT_ALIAS) {
        no strict 'refs';
        # Alias e.g. user::CONSTANT to YourExporter::CONSTANT
        *$alias_as = *$glob_name;
    }

    return $value;
}

sub stash {
    my ($ctx) = @_;

    # We used to die here but that makes e.g. having a global "after"
    # callback tedious. Just return an empty list instead so we can do
    # things like:
    #
    #    if (defined(my $stash = $ctx->stash)) { ... }
    #
    return $ctx->{stash};
}

1;

__END__

=encoding utf8

=head1 NAME

Constant::Export::Lazy - Utility to write lazy exporters of constant subroutines

=head1 DESCRIPTION

This is a utility to write lazy exporters of constant
subroutines. It's not meant to be a user-facing constant exporting
API, it's something you use to write user-facing constant exporting
APIs.

There's dozens of similar constant defining modules and exporters on
the CPAN, why did I need to write this one?

=over

=item * It's lazy

Our constants fleshened via callbacks that are guaranteed to be called
only once for the lifetime of the process (not once per importer or
whatever), and we only call the callbacks lazily if someone actually
requests that a constant of ours be defined.

This makes it easy to have one file that runs in different
environments and generates some subset of its constants with a module
that you may not want to use, or may not be available in all your
environments. You can just C<require> it in the callback that
generates the constant that requires it.

=item * It makes it easier to manage creating constants that require other constants

Maybe you have one constant indicating whether you're running in a dev
environment, and a bunch of other constants that are defined
differently if the dev environment constant is true.

Now say you have several hundred constants like that, managing the
inter-dependencies and that everything is defined in the right order
quickly gets messy.

Constant::Import::Lazy takes away all this complexity. When you define
a constant you get a callback object that can give you the value of
other constants, and will either generate them if they haven't been
generated, or look them up in the symbol table if they have.

Thus we end up with a Makefile-like system where you can freely use
whatever other constants you like when defining your constants, just
be careful not to introduce circular dependencies.

=back

=head1 SYNOPSIS

So how does all this work? This increasingly verbose example of your
C<My::Constants> package that you write using
C<Constant::Export::Lazy> demonstrates all our features (from
F<t/lib/My/Constants.pm> in the source distro):

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
            # For convenience you can also access other constants,
            # e.g. those defined with constant.pm
            SUM_INTEROP => sub {
                my ($ctx) = @_;
                $ctx->call('X') + $ctx->call('Y'),
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
            PI => {
                call    => sub { 3.14 },
                options => {
                    override => sub {
                        my ($ctx, $name) = @_;
                        # You can simply "return;" here to say "I don't
                        # want to override", and "return undef;" if you
                        # want the constant to be undef.
                        return $ENV{PI} ? "Pi is = $ENV{PI}" : $ctx->call($name);
                    },
                    # This is an optional ref that'll be accessible via
                    # $ctx->stash in any subs relevant to this constant
                    # (call, override, after, ...)
                    stash => {
                        # This `typecheck_rx` is in no way supported by
                        # Constant::Export::Lazy, it's just something
                        # we're passing around to the 'after' sub below.
                        typecheck_rx => qr/\d+\.\d+/s, # such an epicly buggy typecheck...
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
            after => sub {
                my ($ctx, $name, $value, $source) = @_;

                if (defined(my $stash = $ctx->stash)) {
                    my $typecheck_rx = $stash->{typecheck_rx};
                    die "PANIC: The value <$value> for <$name> doesn't pass <$typecheck_rx>"
                        unless $value =~ $typecheck_rx;
                }

                print STDERR "Defined the constant <$name> with value <$value> from <$source>\n" if $ENV{DEBUG};
                return;
            },
        },
    );

    1;

And this is an example of using it in some user code (from
F<t/synopsis.t> in the source distro):

    package My::User::Code;
    use strict;
    use warnings;
    use Test::More qw(no_plan);
    use lib 't/lib';
    BEGIN {
        # Supply a more accurate PI
        $ENV{PI} = 3.14159;
        # Override B
        $ENV{B} = 3;
    }
    use My::Constants qw(
        X
        Y
        A
        B
        SUM
        SUM_INTEROP
        PI
        LIST
    );

    is(X, -2);
    is(Y, -1);
    is(A, 1);
    is(B, 3);
    is(SUM, 4);
    is(SUM_INTEROP, -3);
    is(PI,  "Pi is = 3.14159");
    is(join(",", @{LIST()}), '3,4');

And running it gives:

    $ DEBUG=1 perl -Ilib t/synopsis.t
    Defined the constant <A> with value <1> from <callback>
    Defined the constant <B> with value <3> from <override>
    Defined the constant <SUM> with value <4> from <callback>
    Defined the constant <SUM_INTEROP> with value <-3> from <callback>
    Defined the constant <PI> with value <Pi is = 3.14159> from <override>
    Defined the constant <LIST> with value <ARRAY(0x16b8918)> from <callback>
    ok 1
    ok 2
    ok 3
    ok 4
    ok 5
    ok 6
    ok 7
    ok 8
    1..8

Things to note about this example:

=over

=item *

We're using C<$ctx->call($name)> to get the value of other constants
while defining ours.

=item *

That you can use either a global C<override> option or a local per-sub
one to override your constants via C<%ENV> variables, or anything else
you can think of.

=item *

We're using the global C<wrap_existing_import> option, and L<Exporter>
to export some of our constants via L<constant>.

This demonstrates migrating an existing module that takes a list of
constants (or labels) that don't overlap with our list of constants to
C<Constant::Export::Lazy>.

As well as supplying this option you have to C<use
Constant::Export::Lazy> after the other module defines its C<import>
subroutine. Then we basically compose a list of constants we know we
can handle, and dispatch anything we don't know about to the C<import>
subroutine we clobbered.

=back

=head1 AUTHOR

Ævar Arnfjörð Bjarmason <avar@cpan.org>

=cut

