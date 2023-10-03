#!/usr/bin/env perl

# App::Hump.pm - a dependency manager
# Author: Lee Katz <lkatz@cdc.gov>

package App::Hump;
require 5.10.0;

use strict;
use warnings;

use File::Basename qw/basename fileparse dirname/;
use File::Temp qw/tempdir tempfile/;
use Data::Dumper qw/Dumper/;
use File::Which qw/which/;
use Carp qw/croak carp confess/;
use FindBin qw/$RealBin/;

use version 0.77;
our $VERSION = '0.2.0';

use Exporter qw/import/;
our @EXPORT_OK = qw(
  $make_target $make_dep $make_deps
           );

use overload '""' => 'toString';

my $startTime = time();
sub logmsg{
  local $0 = basename $0; 
  my $elapsedTime = time() - $startTime;
  print STDERR "$0 $elapsedTime @_\n";
}

=pod

=head1 NAME

App::Hump - A module for workflow dependencies.
Uses the power of `make` in the backend.

=head1 SYNOPSIS

  use strict;
  use warnings;
  use App::Hump qw/$make_target $make_deps/;
  
  my %make = (
    all => {
      DEP => [
        "hello.txt",
        "world.txt",
      ],
      CMD => [
        "cat $make_deps | tr '\\n' ' '",
        "echo",
      ],
    },
    "hello.txt" => {
      DEP => [],
      CMD => [
        "echo 'hello' > $make_target",
      ],
    },
    "world.txt" => {
      DEP => [],
      CMD => [
        "echo 'world' > $make_target",
      ],
    },
  );

  my $hump = App::Hump->new();
  $hump->write_makefile(\%make);
  $hump->run_makefile();


=head1 DESCRIPTION

A module for helping with workflow dependencies.
It might be useful as a very rudementary workflow engine.
It uses a hash of commands and dependencies to create a thoughtful Makefile,
which can then be executed.

=head1 VARIABLES

Many of these variables come from
L<https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html>

=over

=item $make_target

This indicates the actual target that must be created, i.e., '$@'

=item $make_dep

This indicates the first dependency of the target, i.e., '$<'

=item $make_deps

This indicates all the dependencies of the target in the order that they are supplied, i.e., '$^'

=back

=cut

our $make_target = '$@';
our $make_dep    = '$<';
our $make_deps   = '$^';

=pod

=head1 METHODS

=over

=item App::Hump->new(\%options)

Create a new Hump.

  Applicable arguments for \%options:
  Argument     Default    Description
  numcpus      1          How many jobs to run at the same time
  tempdir      ''         A directory to store temporary files.
                          If not supplied, will create something in temp storage.

=back

=cut

sub new{
  my($class,$settings)=@_;

  # Set optional parameter defaults
  $$settings{numcpus}     ||= 1;
  $$settings{tempdir}     ||= tempdir("Hump.pm.XXXXXX",TMPDIR=>1,CLEANUP=>1);


  # Initialize the object and then bless it
  my $self={
    numcpus    => $$settings{numcpus},
    tempdir    => $$settings{tempdir},
    makefile   => "$$settings{tempdir}/Makefile",
  };

  open(my $fh, ">", $$self{makefile}) or croak "ERROR: could not create $$self{makefile}: $!";
  close $fh;

  bless($self);

  return $self;
}
=pod

=over

=item $hump->toString

Returns the entire contents of the Makefile.
This is also the method for when the object is stringified, 
e.g., 

    my $hump = App::Hump->new;
    print "$hump\n";

To get the actual Makefile path, use `$$hump{makefile}`.

=back

=cut

sub toString{
  my($self) = @_;

  local $/=undef;

  open(my $fh, "<", $$self{makefile}) or croak "ERROR: could not open $$self{makefile}: $!";
  my $content = <$fh>;
  close $fh;

  return $content;
}

=pod

=over

=item $hump->write_makefile(\%make)

Writes a makefile with the make hash.

Inspired by and copied from Nullarbor at L<https://github.com/tseemann/nullarbor/blob/master/bin/nullarbor.pl#L348>

=back

=cut

sub write_makefile {
  my($self, $make) = @_;

  open(my $fh, ">", $$self{makefile}) or die "ERROR: could not write to $$self{makefile}: $!";

  #print $fh "# Command line:\n# cd ".getcwd()."\n# @CMDLINE\n\n";

  print $fh "BINDIR := $RealBin\n";
  print $fh "CPUS := $$self{numcpus}\n";
  print $fh "SHELL := /bin/bash
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables

.SUFFIXES:
.DELETE_ON_ERROR:
.SECONDARY:
.ONESHELL:
.DEFAULT: all
.PHONY: all

";

  for my $target ('all', sort grep { $_ ne 'all' } keys %$make) {
    print $fh "\n";
    my $rule = $make->{$target}; # short-hand
    # dependencies are an array ref
    my $dep = $rule->{DEP};

    # If there is an entry for PHONY, then show that this target is phony
    print $fh ".PHONY: $target\n" if $rule->{PHONY} or ! $rule->{DEP};

    # Make the actual Makefile rule here
    print $fh "$target: " . join(" ", @$dep) . "\n";
    if (my $cmd = $rule->{CMD}) {
      for my $c(@$cmd){
        print $fh "\t$c\n";
      }
    }
  }

  close $fh;
}

=pod

=over

=item $hump->run_makefile()

Runs the makefile that was created by $hump->write_makefile.
Returns any stdout.
stdout is also saved into `$$hump{tempdir}/make.out`.

stderr is saved in `$$hump{tempdir}/make.log`.

=back

=cut

sub run_makefile{
  my($self) = @_;

  my $mode = 'all';
  my $cmd = "nice make -C $$self{tempdir} --quiet -f $$self{makefile} $mode -j $$self{numcpus} > $$self{tempdir}/make.out 2>$$self{tempdir}/make.log";
  system($cmd);
  croak "ERROR running $cmd: $!\n\nStderr was:\n".`cat $$self{tempdir}/make.log` if($?);

  open(my $fh, "<", "$$self{tempdir}/make.out") or croak "ERROR: could not open $$self{tempdir}/make.out for reading: $!";
  local $/=undef;
  my $stdout = <$fh>;
  close $fh;
  
  return $stdout;
}

=pod

=over

=item $hump->write_dag

Creates a directed acyclic graph (DAG) and returns it in a string

=back

=cut

# Define a subroutine to convert Makefile to Mermaid format
sub write_dag{
    my($self) = @_;

    my $makefile_path = $$self{makefile};

    # Read the Makefile and extract dependency information
    my %reverse_dependencies;
    my $target;
    open(my $makefile, '<', $makefile_path) or die "Could not open Makefile: $!";
    while (<$makefile>) {
        chomp;
        if (/^(\S+):(.*)$/) {
            # Extract target and dependencies
            $target = $1;
            my @deps = grep{length($_) > 0}
                         split /\s+/, $2;

            for my $dep(@deps){
              push(@{$reverse_dependencies{$dep}}, $target);
            }
        }
    }
    close($makefile);

    # Generate Mermaid syntax
    my $mermaid_code = "graph TD;\n";
    foreach my $dep(sort keys %reverse_dependencies) {
        if(scalar(@{$reverse_dependencies{$dep}}) < 1){
          next;
        }
        foreach my $target (@{$reverse_dependencies{$dep}}) {
            $mermaid_code .= "  $dep --> $target;\n";
        }
    }

    return $mermaid_code;
}

=pod

=head1 COPYRIGHT AND LICENSE

MIT license.  Go nuts.

=head1 AUTHOR

Author: Lee Katz <lkatz@cdc.gov>

For additional help, go to https://github.com/lskatz/perl-app-hump

=cut

1;

