package Constant::Export::Lazy;
use 5.006;
use strict;
use warnings;
use warnings FATAL => "recursion";

our $_CALL_SHOULD_ALIAS_FROM_TO  = {};

sub import {
    my ($class, %args) = @_;
    my $caller = caller;

    # Are we wrapping an existing import subroutine?
    my $wrap_existing_import = (
        exists $args{options}
        ? exists $args{options}->{wrap_existing_import}
          ? $args{options}->{wrap_existing_import}
          : undef
        : undef
    );

    # Sanity check whether we do or don't have an existing 'import'
    # sub with the wrap_existing_import option.
    #
    # Note that if someone has foolishly imported the UNIVERSAL
    # package there'll be an import subroutine in every package which
    # actually won't do anything.
    #
    # I consider it a feature that this'll die anyway, previous
    # versions of this code would only check if the "import" name
    # existed in the symbol table of the caller, but by doing that
    # we're arbitrarily restricting object inheritance just for our
    # own internal check.
    #
    # Arguably I should just drop this wrap_existing_import sanity
    # check too and just do it automatically if we ->can("import"),
    # but it's probably a useful sanity check, particularly in the
    # face of something like UNIVERSAL::import.
    #
    # If someone really *does* want to "use UNIVERSAL" and this
    # package they can just supply "wrap_existing_import => 1" in
    # their program.
    my $existing_import = $caller->can("import");
    {
        my $has_import_already = $existing_import ? 1 : 0;
        if ($wrap_existing_import) {
            die "PANIC: We need an existing 'import' with the wrap_existing_import option" unless $has_import_already;
        } else {
            die "PANIC: We're trying to clobber an existing 'import' subroutine without having the 'wrap_existing_import' option" if $has_import_already;
        }
    }

    # Munge the %args we're given so users can be lazy and give sub {
    # ... } as the value for the constants, but internally we support
    # them being a HashRef with options for each one. Allows us to be
    # lazy later by flattening this whole thing now.
    my $normalized_args = _normalize_arguments(%args);
    my $constants = $normalized_args->{constants};

    my $constants_cb = sub {
        my ($gimme, $action) = @_;

        if ($action eq 'exists') {
            return exists $constants->{$gimme};
        } elsif ($action eq 'options.private_name_munger') {
            return exists $constants->{$gimme}->{options}
              ? $constants->{$gimme}->{options}->{private_name_munger}
              : undef;
        } elsif ($action eq 'options.override') {
            return exists $constants->{$gimme}->{options}
              ? $constants->{$gimme}->{options}->{override}
              : undef;
        } elsif ($action eq 'options.stash') {
            return exists $constants->{$gimme}->{options}
              ? $constants->{$gimme}->{options}->{stash}
              : undef;
        } elsif ($action eq 'options.after') {
            return exists $constants->{$gimme}->{options}
              ? $constants->{$gimme}->{options}->{after}
              : undef;
        } elsif ($action eq 'call') {
            return $constants->{$gimme}->{call};
        } else {
            die "UNKNOWN: $action";
        }
    };

    # This is a callback that can be used to munge the import list, to
    # e.g. provide a facility to provide import tags.
    my $buildargs = (
        exists $args{options}
        ? exists $args{options}->{buildargs}
          ? $args{options}->{buildargs}
          : undef
        : undef
    );

    no strict 'refs';
    no warnings 'redefine'; # In case of $wrap_existing_import
    *{$caller . '::import'} = sub {
        use strict;
        use warnings;

        my (undef, @gimme) = @_;
        my $pkg_importer = caller;

        my $ctx = bless {
            constants_cb => $constants_cb,
            __constants  => $constants,
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

            # If we're not wrapping an existing import subroutine we
            # don't need to bend over backwards to support constants
            # generated by e.g. constant.pm, we know we've made all
            # the constants in the package to our liking.
            wrap_existing_import => $wrap_existing_import,
        } => 'Constant::Export::Lazy::Ctx';

        # We've been provided with a callback to be used to munge
        # whatever we actually got provided with in @gimme to a list
        # of constants, or if $wrap_existing_import is enabled any
        # leftover non-$gimme names it's going to handle.
        if ($buildargs) {
            my @overriden_gimme = $buildargs->(\@gimme, $constants);
            die "PANIC: We only support subs that return zero or one values with buildargs, yours returns " . @overriden_gimme . " values"
                if @overriden_gimme > 1;
            @gimme = @{$overriden_gimme[0]} if @overriden_gimme;
        }

        # Just doing ->call() like you would when you're using the API
        # will fleshen the constant, do this for all the constants
        # we've been requested to export.
        my @leftover_gimme;
        for my $gimme (@gimme) {
            if ($constants_cb->($gimme, 'exists')) {
                # We only want to alias constants into the importer's
                # package if the constant is on the import list, not
                # if it's just needed within some $ctx->call() when
                # defining another constant.
                #
                # To disambiguate these two cases we maintain a
                # globally dynamically scoped variable with the
                # constants that have been requested, and we note
                # who've they've been requested by.
                local $_CALL_SHOULD_ALIAS_FROM_TO->{$pkg_importer}->{$gimme} = undef;

                $ctx->call($gimme);
            } elsif ($wrap_existing_import) {
                # We won't even die on $wrap_existing_import if that
                # importer doesn't know about this $gimme, but
                # hopefully they're just about to die with an error
                # similar to ours if they don't know about the
                # requested constant.
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
    my $has_default_options = keys %default_options ? 1 : 0;
    my %constants = %{$args{constants}};
    my %new_constants;
    for my $constant_name (keys %constants) {
        my $value = $constants{$constant_name};
        if (ref $value eq 'CODE') {
            $new_constants{$constant_name} = {
                call    => $value,
                ($has_default_options
                 ? (options => \%default_options)
                 : ()),
            };
        } elsif (ref $value eq 'HASH') {
            my %options = %{ $value->{options} || {} };
            $new_constants{$constant_name} = {
                (exists $value->{call}
                 ? (call => $value->{call})
                 : ()),
                (($has_default_options or keys %options)
                 ? (
                     options => {
                         %default_options,
                         %options,
                     }
                 )
                 : ()),
            };
        } else {
            die sprintf "PANIC: The constant <$constant_name> has some value type we don't know about (ref = %s)",
                ref $value || 'Undef';
        }
    }

    $args{constants} = \%new_constants;

    return \%args;
}

our $_GETTING_VALUE_FOR_OVERRIDE = {};

sub Constant::Export::Lazy::Ctx::call {
    my ($ctx, $gimme) = @_;

    # Unpack our options
    my $pkg_importer         = $ctx->{pkg_importer};
    my $pkg_stash            = $ctx->{pkg_stash};
    my $constants_cb         = $ctx->{constants_cb};
    my $wrap_existing_import = $ctx->{wrap_existing_import};

    # Unless we're wrapping an existing import ->call($gimme) should
    # always be called with a $gimme that we know about.
    unless ($constants_cb->($gimme, 'exists')) {
        die "PANIC: You're trying to get the value of an unknown constant ($gimme), and wrap_existing_import isn't set" unless $wrap_existing_import;
    }

    my ($private_name, $glob_name, $alias_as);
    my $make_private_glob_and_alias_name = sub {
        # Checking "exists $constants->{$gimme}" here to avoid
        # autovivification would be redundant since we won't call this
        # if $wrap_existing_import is true, otherwise
        # $constants->{$gimme} is guaranteed to exist. See the
        # assertion just a few lines above this code.
        #
        # If $wrap_existing_import is true and we're handling a
        # constant we don't know about we'll have called the import()
        # we're wrapping, or we're being called from ->call(), in
        # which case we won't be calling this sub unless
        # $constants->{$gimme} exists.
        $private_name = $constants_cb->($gimme, 'options.private_name_munger')
          ? $constants_cb->($gimme, 'options.private_name_munger')->($gimme)
          : $gimme;

        # In case the ->($gimme) part of the above returns undef, we
        # fallback to $gimme.
        $private_name = defined $private_name ? $private_name : $gimme;

        $glob_name = "${pkg_stash}::${private_name}";
        $alias_as  = "${pkg_importer}::${gimme}";

        return;
    };

    my $value;
    if ($wrap_existing_import and not $constants_cb->($gimme, 'exists')) {
        # This is in case $ctx->call() is used on a constant defined
        # by constant.pm. See the giant comment about constant.pm
        # below.
        if (my $code = $pkg_stash->can($gimme)) {
            my @value = $code->();
            die "PANIC: We only support subs that return one value with wrap_existing_import, $gimme returns " . @value . " values" if @value > 1;
            $value = $value[0];
        } else {
            die "PANIC: We're trying to fallback to a constant we don't know about under wrap_existing_import, but $gimme has no symbol table entry";
        }
    } elsif (do {
        # Check if this is a constant we've defined already, in which
        # case we can just return its value.
        #
        # If we got this far we know we're going to want to call
        # $make_private_glob_and_alias_name->(). It'll also be used by
        # the "else" branch below if we end up having to define this
        # constant.
        $make_private_glob_and_alias_name->();

        $pkg_stash->can($private_name);
    }) {
        # This is for constants that *we've* previously defined, we'll
        # always use our own $private_name.
        $value = $pkg_stash->can($private_name)->();
    } else {
        my $override = $constants_cb->($gimme, 'options.override');
        my $stash    = $constants_cb->($gimme, 'options.stash');

        # Only pass the stash around if we actually have it. Note that
        # "delete local $ctx->{stash}" is a feature new in 5.12.0, so
        # we can't use it. See
        # http://perldoc.perl.org/5.12.0/perldelta.html#delete-local
        local $ctx->{stash} = $stash;
        delete $ctx->{stash} unless ref $stash;

        my @overriden_value;
        my $source;
        if ($override and
            not (exists $_GETTING_VALUE_FOR_OVERRIDE->{$pkg_importer} and
                 exists $_GETTING_VALUE_FOR_OVERRIDE->{$pkg_importer}->{$gimme})) {
            local $_GETTING_VALUE_FOR_OVERRIDE->{$pkg_importer}->{$gimme} = undef;
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
            $value = $constants_cb->($gimme, 'call')->($ctx);
        }

        unless (exists $_GETTING_VALUE_FOR_OVERRIDE->{$pkg_importer} and
                exists $_GETTING_VALUE_FOR_OVERRIDE->{$pkg_importer}->{$gimme}) {
            # Instead of doing `sub () { $value }` we could also
            # use the following trick that constant.pm uses if
            # it's true that `$] > 5.009002`:
            #
            #     Internals::SvREADONLY($value, 1);
            #     my $stash = \%{"$pkg_stash::"};
            #     $stash->{$gimme} = \$value;
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
            # * perl-5.9.2-1966-ge040ff7 - first use in constant.pm.
            #
            # * perl-5.9.2-1981-ge1234d8 - first attempts to
            #   invalidate the method cache with
            #   Internals::inc_sub_generation()
            #
            # * perl-5.9.4-1684-ge1a479c -
            #   Internals::inc_sub_generation() in constant.pm
            #   replaced with mro::method_changed_in($pkg)
            #
            # * perl-5.9.4-1714-g41892db - Now unused
            #   Internals::inc_sub_generation() removed from the
            #   core.
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

                # Future-proof against changes in perl that might not
                # optimize the constant sub if $value is used
                # elsewhere, we're passing it to the $after function
                # just below. See the "Is it time to separate pad
                # names from SVs?" thread on perl5-porters.
                my $value_copy = $value;
                *$glob_name = sub () { $value_copy };
            }

            # Maybe we have a callback that wants to know when we define
            # our constants, e.g. for printing something out, keeping taps
            # of what constants we have etc.
            my $after = $constants_cb->($gimme, 'options.after');
            if ($after) {
                # Future-proof so we can do something clever with the
                # return value in the future if we want.
                my @ret = $after->($ctx, $gimme, $value, $source);
                die "PANIC: Don't return anything from 'after' routines" if @ret;
            }
        }
    }

    # So? What's this entire evil magic about?
    #
    # Early on in the history of this module I decided that everything
    # that needed to call or define a constant would just go through
    # $ctx->call($gimme), including things called via the import().
    #
    # This makes some parts of this module much simpler, since we
    # don't have e.g. a $ctx->call_and_intern($gimme) to define
    # constants for the first time, v.s. a
    # $ctx->get_interned_value($gimme). We just have one
    # $ctx->call($gimme) that DWYM. You just request a value, it does
    # the right thing, and you don't have to worry about it.
    #
    # However, we have to worry about the following cases:
    #
    # * Someone in "user" imports YourExporter::CONSTANT, we define
    #   YourExporter::CONSTANT and alias user::CONSTANT to it. Easy,
    #   this is the common case.
    #
    # * Ditto, but YourExporter::CONSTANT needs to get the value of
    #   YourExporter::CONSTANT_NESTED to define its own value, we want
    #   to export YourExporter::CONSTANT to user::CONSTANT but *NOT*
    #   YourExporter::CONSTANT_NESTED. We don't want to leak dependent
    #   constants like that.
    #
    # * The "user" imports YourExporter::CONSTANT, this in turns needs
    #   to call Some::Module::function() and Some::Module::function()
    #   needs YourExporter::UNRELATED_CONSTANT
    #
    # * When we're in the "override" callback for
    #   YourExporter::CONSTANT we don't want to intern
    #   YourExporter::CONSTANT, but if we call some unrelated
    #   YourExporter::ANOTHER_CONSTANT while in the override we want
    #   to intern (but not export!) that value.
    #
    # So to do all this we're tracking on a per importer/constant pair
    # basis who requested what during import()-time, and whether we're
    # currently in the scope of an "override" for a given constant.
    if (not (exists $_GETTING_VALUE_FOR_OVERRIDE->{$pkg_importer} and
             exists $_GETTING_VALUE_FOR_OVERRIDE->{$pkg_importer}->{$gimme}) and
        exists $_CALL_SHOULD_ALIAS_FROM_TO->{$pkg_importer} and
        exists $_CALL_SHOULD_ALIAS_FROM_TO->{$pkg_importer}->{$gimme}) {
        no strict 'refs';
        # Alias e.g. user::CONSTANT to YourExporter::CONSTANT (well,
        # actually YourExporter::$private_name)
        *$alias_as = \&$glob_name;
    }

    return $value;
}

sub Constant::Export::Lazy::Ctx::stash {
    my ($ctx) = @_;

    # We used to die here when no $ctx->{stash} existed, but that
    # makes e.g. having a global "after" callback tedious. Just return
    # undef instead so we can do things like:
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

=head1 SYNOPSIS

This is an example of a C<My::Constants> package that you can write
using C<Constant::Export::Lazy> that demonstrates most of its main
features. This is from the file F<t/lib/My/Constants.pm> in the source
distro:

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
            # support returning lists. So if you want to return lists you
            # have to return a reference to one.
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

By default we only support importing constants explicitly by their own
names and not something like L<Exporter>'s C<@EXPORT>, C<@EXPORT_OK>
or C<%EXPORT_TAGS>, but you can trivially add support for that (or any
other custom import munging) using the L</buildargs> callback. This
example is from F<t/lib/My/Constants/Tags.pm> in the source distro:

    package My::Constants::Tags;
    use v5.10;
    use strict;
    use warnings;
    use Constant::Export::Lazy (
        constants => {
            KG_TO_MG => sub { 10**6 },
            SQRT_2 => {
                call    => sub { sqrt(2) },
                options => {
                    stash => {
                        export_tags => [ qw/:math/ ],
                    },
                },
            },
            PI => {
                call    => sub { atan2(1,1) * 4 },
                options => {
                    stash => {
                        export_tags => [ qw/:math/ ],
                    },
                },
            },
            map(
                {
                    my $t = $_;
                    +(
                        $_ => {
                            call => sub { $t },
                            options => {
                                stash => {
                                    export_tags => [ qw/:alphabet/ ],
                                },
                            }
                        }
                    )
                }
                "A".."Z"
            ),
        },
        options => {
            buildargs => sub {
                my ($import_args, $constants) = @_;

                state $export_tags = do {
                    my %export_tags;
                    for my $constant (keys %$constants) {
                        my @export_tags = @{$constants->{$constant}->{options}->{stash}->{export_tags} || []};
                        push @{$export_tags{$_}} => $constant for @export_tags;
                    }
                    \%export_tags;
                };

                my @gimme = map {
                    /^:/ ? @{$export_tags->{$_}} : $_
                } @$import_args;

                return \@gimme;
            },
        },
    );

    1;

And this is an example of using it in some user code (from
F<t/synopsis_tags.t> in the source distro):

    package My::More::User::Code;
    use strict;
    use warnings;
    use Test::More qw(no_plan);
    use lib 't/lib';
    use My::Constants::Tags qw(
        KG_TO_MG
        :math
        :alphabet
    );

    is(KG_TO_MG, 10**6);
    is(A, "A");
    is(B, "B");
    is(C, "C");
    like(PI, qr/^3\.14/);

And running it gives:

    $ perl -Ilib t/synopsis_tags.t
    ok 1
    ok 2
    ok 3
    ok 4
    ok 5
    1..5

=head1 DESCRIPTION

This is a library to write lazy exporters of constant
subroutines. It's not meant to be a user-facing constant exporting
API, it's something you use to write user-facing constant exporting
APIs.

There's dozens of modules on the CPAN that define constants in one way
or another, why did I need to write this one?

=head2 It's lazy

Our constants are fleshened via callbacks that are guaranteed to be
called only once for the lifetime of the process (not once per
importer or whatever), and we only call the callbacks lazily if
someone actually requests that a constant of ours be defined.

This makes it easy to have one constant exporting module that runs in
different environments, and generates some subset of its constants
depending on what the program that's using it actually needs.

Some data that you may want to turn into constants may require modules
that aren't available everywhere, queries to databases that aren't
available everywhere, or make certain assumptions about the
environment they're running under that may not be true across all your
environments.

By only defining those constants you actually need via callbacks
managing all these special-cases becomes a lot easier.

=head2 It makes it easier to manage creating constants that require other constants

Maybe you have one constant indicating whether you're running in a dev
environment, and a bunch of other constants that are defined
differently if the dev environment constant is true.

Now say you have several hundred constants like that, managing the
inter-dependencies and ensuring that they're all defined in the right
order with dependencies before dependents quickly gets messy.

All this complexity becomes a non-issue when you use this module. When
you define a constant you get a callback object that can give you the
value of other constants.

When you look up another constant we'll either generate it if it
hasn't been materialized yet, or look up the materialized value in the
symbol table if it has.

Thus we end up with a Makefile-like system where you can freely use
whatever other constants you like when defining your constants, and
we'll lazily define the entire tree of constants on-demand.

You only have to be careful not to introduce circular dependencies.

=head1 API

Our API is exposed via a nested key-value pair list passed to C<use>,
see the L</SYNOPSIS> for an example. Here's description of the data
structure you can pass in:

=head2 constants

This is a key-value pair list of constant names to either a subroutine
or a hash with L</call> and optional L<options|/options
(local)>. Internally we just convert the former type of call into the
latter, i.e. C<< CONST => sub {...} >> becomes C<< CONST => { call =>
sub { ... } } >>.

=head3 call

The subroutine we'll call with a L<context
object|Constant::Export::Lazy/"CONTEXT OBJECT"> to fleshen the
constant.

It's guaranteed that this sub will only ever be called once for the
lifetime of the process, except if you manually call it multiple times
during an L</override>.

Providing this callback subroutine can be omitted if the L</override>
callback always fleshens the value by itself. See the L</override>
documentation for more details.

=head3 options (local)

Our options hash to override the global L</options>. The semantics are
exactly the same as for the global hash.

=head2 options

We support various options, most of these can be defined either
globally if you want to use them for all the constants, or locally to
one constant at a time with the more verbose hash invocation to
L</constants>.

The following options are supported:

=head3 buildargs

A callback that can only be supplied as a global option. If you
provide this the callback we'll call it to munge any parameters to
import we might get. This can be used (as shown in the
L<synopsis|/SYNOPSIS>) to strip or map parameters to e.g. implement
support for C<%EXPORT_TAGS>, or to do any other arbitrary mapping.

This callback will be called with a reference to the parameters passed
to import, and for convenience with the L<constants hash|/constants>
you provided (e.g. for introspecting the stashes of constants, see the
L<synopsis|/SYNOPSIS> example.

This is expected to return an array with a list of constants to
import, or the empty list if we should discard the return value of
this callback and act is if it wasn't present at all.

This plays nice with the L</wrap_existing_import> parameter. When it's
in force any constant names (or tag names, or whatever) you return
that we don't know about ourselves we'll pass to the fallback import
subroutine we're wrapping as we would if buildargs hadn't been
defined.

=head3 wrap_existing_import

A boolean that can only be supplied as a global option. If you provide
this the package you're importing us into has to already have a
defined an C<import> subroutine which we'll locate via C<<
->can("import") >>.

When provided we'll first run our own C<import> subroutine to export
all the constants we know about (i.e. the ones passed to
L</constants>), but anything we don't know about will be passed to the
existing C<import> subroutine found.

Note that if existing C<import> subroutine was in the package we're
being imported into we'll of course need to clobber it with our own
routine (which'll call the previous routine we found by
reference). This is perfectly fine and the common way to use this
facility.

But we also work perfectly well with inheritance, so
C<wrap_existing_import> can be used to wrap an C<import> subroutine
that exists in a parent class of the importing package, in which case
we won't be clobbering anything, just inserting a new C<import>
subroutine.

This facility is handy for converting existing packages that use
e.g. a combination of L<Exporter> to export a bunch of L<constant>
constants without having to port them all over to
C<Constant::Export::Lazy> at the same time. This allows you to do so
incrementally.

For convenience we also support calling these foreign subroutines with
C<< $ctx->call($name) >>. This is handy because when migrating an
existing package you can already start calling existing constants with
our interface, and then when you migrate those constants over you
won't have to change any of the old code.

We'll handle calling subroutines generated with perl's own
L<constant.pm|constant> (including "list" constants), but we'll die in
C<call> if we call a foreign subroutine that returns more than one
value, i.e. constants defined as C<use constant FOO => (1, 2, 3)>
instead of C<use constant FOO => [1, 2, 3]>.

If this isn't set and the class we're being imported into already has
an C<import> subroutine we'll die.

If you think you shouldn't be getting that error because you didn't
have any import subroutine it's likely that you've used L</UNIVERSAL>
somewhere in your program.

To us that'll look just like any other C<import> subroutine, so you'll
either need to stop using the horror that is C<UNIVERSAL::import>, if
you don't want to do that for some reason I can't imagine you can
toggle C<wrap_existing_import> so it'll work with it.

=head3 override

This callback can be defined either globally or locally and will be
called instead of your C<call>. In addition to the L<context
object|Constant::Export::Lazy/"CONTEXT OBJECT"> this will also get an
argument to the C<$name> of the constant that we're requesting an
override for.

This can be used for things like overriding default values based on
entries in C<%ENV> (see the L</SYNOPSIS>), or anything else you can
think of.

In an override subroutine C<return $value> will return a value to be
used instead of the value we'd have retrieved from L</call>, doing a
C<return;> on the other hand means you don't want to use the
subroutine to override this constant, and we'll stop trying to do so
and just call L</call> to fleshen it.

You can also get the value of L</call> by doing
C<< $ctx->call($name) >>. We have some magic around override ensuring
that we only B<get> the value, we don't actually intern it in the
symbol table.

This means that calling C<< $ctx->call($name) >> multiple times in the
scope of an override subroutine is the only way to get
C<Constant::Export::Lazy> to call a L</call> subroutine multiple
times. We otherwise guarantee that these subs are only called once (as
discussed in L</It's lazy> and L</call>).

It also means that if you guarantee that you B<don't> call C<<
$ctx->call($name) >> at all in your override subroutine you can omit
the L</call> callback. This is useful e.g. if the L</stash> passes
some option like C<fleshen_from_file> which the C<override> callback
picks up. In that case the constant would always be fleshened from the
content of the file by the C<override> callback, and we'd never call
the callback subroutine, so providing it would be pointless and
confusing.

If you don't provide L</call> as described above and screw up your
C<override> definition such that the override doesn't provide an
override, we'll end up dying with the same error you'd get if you
called C<< undef()->() >> as we try to fleshen your non-overridden
contestant in vain.

=head3 after

This callback will be called after we've just interned a new constant
into the symbol table. In addition to the L<context
object|Constant::Export::Lazy/"CONTEXT OBJECT"> this will also get
C<$name>, C<$value> and C<$source> arguments. The C<$name> argument is
the name of the constant we just defined, C<$value> is its value, and
C<$source> is either C<"override"> or C<"callback"> depending on how
the constant was defined. I.e. via L</override> or directly via
L</call>.

This was added to support replacing modules that in addition to just
defining constants might also want to check them for well-formedness
after they're defined, or push known constants to a hash somewhere so
they can all be retrieved by some complimentary API that e.g. spews
out "all known settings".

You must C<return:> from this subroutine, if anything's returned from
it we'll die, this is to reserve any returning of values for future
use.

=head3 stash

This is a reference that you can provide for your own use, we don't
care what's in it. It'll be accessible via the L<context
object|Constant::Export::Lazy/"CONTEXT OBJECT">'s C<stash> method
(i.e. C<< my $stash = $ctx->stash >>) for L</call>, L</override> and
L</after> calls relevant to its scope, i.e. global if you define it
globally, otherwise local if it's defined locally.

=head3 private_name_munger

This callback can be defined either globally or locally. When it's
provided it'll be used to munge the internal name of the subroutine we
define in the exporting package.

This allows for preventing the anti-pattern of user code not importing
constants before using them. To take the example in the
L<synopsis|/SYNOPSIS> it's for preventing C<My::Constants::PI> and
C<My::User::Code::PI> interchangeably, using this facility we can
change C<My::Constants::PI> to
e.g. C<My::Constants::SOME_OPAQUE_VALUE_PI>.

This is useful because users used to using other constant modules
might be in the habit of using non-imported and imported names
interchangeably.

This is fine when the constant exporting module isn't lazy, however
with Constant::Export::Lazy this relies on someone else having
previously defined the constant at a distance, and if that someone
goes away this'll silently turn into an error at a distance.

By using the C<private_name_munger> option you can avoid this
happening in the first place by specifying a subroutine like:

    private_name_munger => sub {
        my ($gimme) = @_;

        # We guarantee that these constants are always defined by us,
        # and we don't want to munge them because legacy code calls
        # them directly for historical reasons.
        return if $gimme =~ /^ALWAYS_DEFINED_/;

        state $now = time();
        return $gimme . '_TIME_' . $now;
    },

Anyone trying to call that directly from your exporting package as
opposed to importing into their package will very quickly discover
that it doesn't work.

Because this is called really early on this routine doesn't get passed
a C<$ctx> object, just the name of the constant you might want to
munge. To skip munging it return the empty list, otherwise return a
munged name to be used in the private symbol table.

We consider this a purely functional subroutine and you B<MUST> return
the same munged name for the same C<$gimme> because we might resolve
that C<$gimme> multiple times. Failure to do so will result your
callbacks being redundantly re-defined.

=head1 CONTEXT OBJECT

As discussed above we pass around a context object to all callbacks
that you can define. See C<$ctx> in the L</SYNOPSIS> for examples.

This objects has only two methods:

=over

=item * C<call>

This method will do all the work of fleshening constants via the sub
provided in the L</call> option, taking the L</override> callback into
account if provided, and if applicable calling the L</after> callback
after the constant is defined.

If you call a subroutine you haven't defined yet (or isn't being
imported directly) we'll fleshen it if needed, making sure to only
export it to a user's namespace if explicitly requested.

See L</override> for caveats with calling this inside the scope of an
override callback.

=item * C<stash>

An accessor for the L</stash> reference, will return the empty list if
there's no stash reference defined.

=back

=head1 AUTHOR

Ævar Arnfjörð Bjarmason <avar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013-2016 by Ævar Arnfjörð Bjarmason
<avar@cpan.org>

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

