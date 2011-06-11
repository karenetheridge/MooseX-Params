package MooseX::Params;

# ABSTRACT: Subroutine signature declaration via attributes

use strict;
use warnings;
use 5.010;
use Attribute::Handlers;
use MooseX::Params::Util;
use MooseX::Params::Meta::Method;
use Moose::Meta::Class;

sub import
{
    no strict 'refs';
    push @{caller.'::ISA'}, __PACKAGE__;
    use strict 'refs';
}

sub Args :ATTR(CODE,RAWDATA)
{
    my ($package, $symbol, $referent, $attr, $data) = @_;

    my ($name)  = $$symbol =~ /.+::(\w+)$/;
    my $coderef = \&$symbol;

    my $parameters = MooseX::Params::Util::inflate_parameters($package, $data);

    my $wrapped_coderef = MooseX::Params::Util::wrap_method($coderef, $package, $parameters);

    my $method = MooseX::Params::Meta::Method->wrap(
        $wrapped_coderef,
        name         => $name,
        package_name => $package,
        parameters   => $parameters,
    );

    Moose::Meta::Class->initialize($package)->add_method($name, $method);
}

sub BuildArgs :ATTR(CODE,RAWDATA)
{
    my ($package, $symbol, $referent, $attr, $data) = @_;
    my ($name)  = $$symbol =~ /.+::(\w+)$/;
    $data = "_buildargs_$name" unless $data;

    my $method = Moose::Meta::Class->initialize($package)->get_method($name);
    $method->buildargs($data);
}

sub CheckArgs :ATTR(CODE,RAWDATA)
{
    my ($package, $symbol, $referent, $attr, $data) = @_;
    my ($name)  = $$symbol =~ /.+::(\w+)$/;
    $data = "_checkargs_$name" unless $data;

    my $method = Moose::Meta::Class->initialize($package)->get_method($name);
    $method->checkargs($data);
}

1;

=pod

=head1 SYNOPSIS

  # use Moose types for validation
  # positional arguments are by default required
  sub add :Args(Int first, Int second) {
    return $_{first} + $_{second};
  }

  say add(2, 3); # 5
  say add(2);    # error

  # @_ still works: you can ignore %_ if you want to
  sub add2 :Args(Int first, Int second) {
    my ($first, $second) = @_;
    return $first + $second;
  }

  say add2(2, 3); # 5

  # '&' before a type constraint enables coercion
  subtype 'HexNum', as 'Str', where { /[a-f0-9]/i };
  coerce 'Int', from 'HexNum', via { hex $_ };

  sub add3 :Args(&Int first, &Int second) {
    return $_{first} + $_{second};
  }

  say add3('A', 'B'); # 21

  # slurpy arguments consume the remainder of @_
  sub sum :Args(ArrayRef *values) {
    my $sum = 0;
    my @values = @{$_{values}};

    foreach my $value (@values) {
      $sum += $value;
    }
    return $sum;
  }

  say sum(2, 3, 4, 5); # 14

  # 'all' is optional:
  # if not present search the text within a file and return 1 if found, 0 if not
  # if present search the text and return number of lines in which text is found
  sub search :Args(text, fh, all?) {
    my $cnt = 0;

    while (my $line = $_{fh}->getline) {
      if ( index($line, $_{text}) > -1 ) {
        return 1 if not $_{all};
        $cnt++;
      }
    }

    return $cnt;
  }

  # named arguments
  sub foo :Args(a, :b) {
    return $_{a} + $_{b} * 2;
  }

  # say foo( 3, b => 2 ); # 7
  # say foo(4, 9);        # error
  # say foo(2);           # error
  # say foo(2, 3, 4);     # error

  # parameters are immutable, assign to a variable to edit
  sub trim :Args(Str string) {
      my $string = $_{string};
      $string =~ s/^\s*//;
      $string =~ s/\s*$//;
      return $string;
  }

  # parameters can have simple defaults
  sub find_clothes :Args(:size = 'medium', :color = 'white') { ... }

  # or builders for more complex tasks
  sub find_clothes :Args(
    :size   = _build_param_size,
    :color  = _build_param_color,
    :height = 170 )
  { ... }

  sub _build_param_color {
      return (qw(red green blue))[ int( rand 3 ) ];
  }

  # you can access all other parameters within a builder
  sub _build_param_size {
      return $_{height} > 200 ? 'large' : 'medium';
  }

  # preprocess @_ with buildargs
  sub process_template
    :Args(input, output, params)
    :BuildArgs(_buildargs_process_template)
  {
    say "open $_{input}";
    say "replace " . Dumper $_{params};
    say "save $_{output}";
  }

  # if 'output' is not provided, deduct it from input filename
  sub _buildargs_process_template {
    if (@_ == 2) {
      my ($input, $params) = @_;
      my $output = $input;
      substr($output, -4, 4, "html");
      return $input, $output, $params;
    } else {
      return @_;
    }
  }

  my %data = (
    fname => "Foo",
    lname => "Bar",
  );

  process_template("index.tmpl", \%data);
  # open index.tmpl
  # replace {"lname" => "Bar", "fname" => "Foo"}
  # save index.html

  process_template("from.tmpl", "to.html", \%data);
  # open from.tmpl
  # replace {"lname" => "Bar", "fname" => "Foo"}
  # save to.html

  # additional validation with checkargs
  sub process_person
    :Args(:first_name!, :last_name!, :country!, :ssn?)
    :CheckArgs # shortcut for :CheckArgs(_checkargs_${subname})
  { ... }

  sub _checkargs_process_person {
    if ( $_{country} eq 'USA' ) {
      die 'All US residents must have an SSN' unless $_{ssn};
    }
  }

  # in a class
  package User;

  use Moose;
  use MooseX::Params;
  use DateTime;

  extends 'Person';

  has 'password' => (
    is  => 'rw',
    isa => 'Str',
  );

  has 'last_login' => (
    is      => 'rw',
    isa     => 'DateTime',
  );

  # note the shortcut invocant syntax
  sub login :Args(self: Str pw) {
    return 0 if $_{pw} ne $_{self}->password;

    $_{self}->last_login( DateTime->now() );

    return 1;
  }

=head1 DESCRIPTION

This modules provides an attributes-based interface for parameter processing in Perl 5. For the original rationale see L<http://mechanicalrevolution.com/blog/parameter_apocalypse.html>.

The proposed interface is based on three cornerstone propositions:

=over 4

=item *

Parameters are first-class entities that deserve their own meta protocol. A common meta protocol may be used by different implementations (e.g. this library, L<MooseX::Params::Validate>, L<MooseX::Method::Sigantures>) and allow them to coexist better. It is also the necessary foundation for more advanced features such as multimethods and extended role validation.

=item *

Parameters should benefit from the same power and flexibility that L<Moose> attributes have. This module implements most of this functionality, including laziness.

=item *

The global variable C<%_> is used as a placeholder for processed parameters. It is considered by the author of this module as an intuitive alternative to manual unpacking of C<@_> while staying within the limits of traditional Perl syntax.

=back

=head1 USE WITH CARE

This is still an experimental module and is subject to backwards incompatible changes. It is barely tested and most certainly has serious lurking bugs, has a lot of room for performance optimizations, and its error reporting could be vastly improved.

=head1 BACKWARDS INCOMPATIBLE CHANGES

Version 0.005 removes the interface based on the C<method> keyword, and retains only the attributes-based interface. Also, C<$self> is no longer localized inside methods, you must use C<$_{self}> instead.

=head1 SIGNATURE SYNTAX

Signatures are declared with the C<:Args> attribute. All parsed parameters are made available inside your subroutine within the special C<%_> hash. All elements of C<%_> are read-only, and an attempt to modify them will throw an exception. An attempt to use a hash element which is not a valid parameter name for this subroutine will also throw an exception. C<@_> is not affected by the use of signagures, so you can still use it to manually unpack arguments if you want to.

=head2 Parameter names

Parameter names can by any valid perl identifiers, and they are separated by commas.

  sub rank :Args(first, second, third) {
    say "$_{first} is first, $_{second} is second, and $_{third} is third";
  }

=head2 Invocant

Method signatures can specify their invocant as the first parameter, followed by a colon:

  sub rank :Args(self: first, second, third) {
    my $competition = $_{self}->competition;
    ...
  }

=head2 Type constraints

Moose type constraints may be used for validation.

  sub rank :Args(Str first, Str second, Str third) { ... }

An ampersand before a type enables coercion for this type.

  subtype 'Name' ...;

  coerce 'Name', from 'Str', via { ... };

  sub rank :Args(&Name first, &Name second, &Name third) { ... }

=head2 Positional and named parametrs

Parameters are by default positional.

  sub rank :Args(first, second, third) { ... }
  # rank('Peter', 'George', 'John')

Named parameters are prefixed by a colon.

  sub rank :Args(:first, :second, :third) { ... }
  # rank( first => 'Peter', second => 'George', third => 'John')

Named parameters may be passed by one name and accessed by another.

  sub rank :Args(:gold(first), :silver(second), :bronze(third)) {
    say "$_{first} is first, $_{second} is second, and $_{third} is third";
  }
  # rank( gold => 'Peter', silver => 'George', bronze => 'John')

Positional and named parameters may be mixed, but positional parameters must come first.

  sub rank :Args(first, :second, :third) {
    say "$_{first} is first, $_{second} is second, and $_{third} is third";
  }
  # rank( 'Peter', second => 'George', third => 'John')

=head2 Required parameters

An exclamation mark (C<!>) after the name denotes a required parameter, and a question mark (C<?>) denotes an optional parameter.

  sub rank :Args(first!, second?, third?) { ... }

Positional parameters are by default required, and named parameters are by default optional.

=head2 Slurpy parameters

A parameter prefixed by an asterix (C<*>) is slurpy, i.e. it consumes the remainder of the argument list. Slurpy parameters must come last in the signature.

  sub rank :Args(ArrayRef *winners) {
    say "$_{winners}[0] is first, $_{winners}[1] is second, and $_{winners}[2] is third";
  }

=head2 Default values

A parameter may be given a simple default value, which can be either a quoted string or an unsigned integer.

  sub rank :Args(first = 'Peter', second = 'George', third = 'John') { ... }

You may use either single or double quotes to quote a string, but they will always be interpreted as if single quotes were used.

=head2 Builders

Where a default value is not sufficient, parameters may specify builders instead. A builder is a subroutine whose return value will be used as default value for the parameter.

  sub rank :Args(ArrayRef *winners = calculate_winners) { ... }

  sub calculate_winners { ... }

The name of the builder may be optionally followed by a pair of parenthesis.

  sub rank :Args(ArrayRef *winners = calculate_winners()) { ... }

All builders are executed lazily, i.e. the first time the parameter is accessed. If a parameter name is followed by an equal sign, but neither a default value nor a builder is specified, it is assumed that the parameter has a builder named C<_build_param_${name}>. In this case the equal sign may also be placed before the name of the parameter.

  sub rank :Args(ArrayRef *winners=) { ... }
  # is equivalent to
  sub rank :Args(ArrayRef =*winners) { ... }
  # is equivalent to
  sub rank :Args(ArrayRef *winners = _build_param_winners) { ... }

  sub _build_param_winners { ... }

Within a parameter builder, you can access all other parameters in the C<%_> hash.

  sub connect :Args(=:dbh, :host, :port, :database) { ... }

  sub _build_param_dbh {
    return DBI->connect("dbi:mysql:host=$_{host};port=$_{port};database=$_{database}");
  }

=head1 BUILDARGS AND CHECKARGS

=head1 BuildArgs

The C<BuildArgs> attribute allows you to specify a subroutine that will be used to preprocess your arguments before they are validated against the supplied signature. It can be used as to create poor man's multimethods by coercing different types of arguments to a single signature. It is somewhat similar to what Moose's C<BUILDARGS> does for class constructors.

  sub rank
    :Args(:first :second :third)
    :BuildArgs(_buildargs_rank)
  { ... }

  # allow positional parameters as well
  sub _buildargs_rank {
    if (@_ == 3) {
      return first => $_[0], second => $_[1], third => $_[2];
    } else {
      return @_;
    }
  }

If C<BuildArgs> is specified without a subroutine name, C<_buildargs_${subname}> will be assumed.

  sub rank :Args(...) :BuildArgs { ... }
  # is equivalent to
  sub rank :Args(...) :BuildArgs(_buildargs_rank) { ... }

=head1 CheckArgs

The C<CheckArgs> attribute allows you to specify a subroutine that will be used to perform additional validation after the arguments are validated against the supplied signature. It can be used to perform more complex validations that cannot be expressed in a simple signature. It is somewhat similar to what Moose's C<BUILD> does for class constructors. Inside a C<CheckArgs> subroutine you can access the processed parameters in the C<%_> hash.

  sub rank
    :Args(:first :second :third)
    :CheckArgs(_checkargs_rank)
  { ... }

  # make sure names do not repeat
  sub _checkargs_rank {
    if (
      ($_{first}  eq $_{second}) or
      ($_{first}  eq $_{third} ) or
      ($_{second} eq $_{third} )
    ) { die "One player can only take one place!";  }
  }

If C<CheckArgs> is specified without a subroutine name, C<_checkargs_${subname}> will be assumed.

  sub rank :Args(...) :CheckArgs { ... }
  # is equivalent to
  sub rank :Args(...) :CheckArgs(_checkargs_rank) { ... }

=head1 META CLASSES

C<MooseX::Params> provides method and parameter metaroles, please see their sourcecode for details:

=for :list
* L<MooseX::Params::Meta::Method>
* L<MooseX::Params::Meta::Parameter>

=head1 TODO

=for :list
* return value validation (C<Returns> and C<ReturnsScalar>)
* subroutine traits (C<Does>)
* better error checking and reporting
* improved performance
* lightweight implementation without meta and magic

Whether or not these features will be implemented depends mostly on the community response to the proposed API. Currently the best way to contribute to this module would be to provide feedback and commentary - the L<Moose> mailing list will be a good place for this.

=head1 BUGS

Plenty. Some of the known ones are:

=for :list
* No checking for surplus arguments
* C<foreach my $value (@{$_{arrayref}})> attempts to modify C<$_{arrayref}> and triggers an exception
* May be incompatible with other modules that provide attributes, including L<Perl6::Export::Attrs>
* C<MooseX::Params::Meta::Method> is a class, should be a role

=head1 SEE ALSO

=for :list
* L<MooseX::Params::Validate>
* L<MooseX::Method::Signatures>
