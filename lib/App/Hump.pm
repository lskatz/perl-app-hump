#!/usr/bin/env perl

# App::Hump.pm - a dependency manager
# Author: Lee Katz <lkatz@cdc.gov>

package App::Hump;
require 5.10.0;

use strict;
use warnings;

use File::Basename qw/basename fileparse dirname/;
use File::Copy qw//; # We redefine cp and so we cannot import it without warnings
use File::Temp qw/tempdir tempfile/;
use File::Path qw/make_path/;
use Data::Dumper qw/Dumper/;
use File::Which qw/which/;
use Carp qw/croak carp confess/;
use FindBin qw/$RealBin/;

use version 0.77;
our $VERSION = '0.4.0';

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
  my $makeHash = $hump->make();
  print $$makeHash{stdout}."\n";
  print "STDERR was: ".$$makeHash{stderr}."\n";

  my $helloInfo = $hump->make("hello.txt");
  print $$helloInfo{stdout};

  my $err = $hump->("hello.txt", "./hello.txt");
  die $err if($err);

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

  These \%options variables (numcpus, etc) are exposed as, e.g., $hump->{numcpus}.
  Other exposed variables include:
  $hump->{makefile}       Path to the Makefile
  $hump->{workdir}        Where the Makefile is
  $hump->{logdir}         Where stderr and stdout get written to

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
    makefile   => "$$settings{tempdir}/work/Makefile",
    workdir    => "$$settings{tempdir}/work",
    logdir     => "$$settings{tempdir}/log",
  };

  # initialize directory structure
  mkdir($$self{workdir});
  mkdir($$self{logdir});

  open(my $fh, ">", $$self{makefile}) or die "ERROR: could not create $$self{makefile}: $!";
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

  open(my $fh, "<", $$self{makefile}) or die "ERROR: could not open $$self{makefile}: $!";
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
    # todo consider supporting PHONY in the documentation but for now it's
    # undocumented and therefore I will not support it here.
    #print $fh ".PHONY: $target\n" if $rule->{PHONY} or ! $rule->{DEP};

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

=item $hump->make($target)

Runs the makefile that was created by $hump->write_makefile.
If $target is not supplied, it defaults to 'all'.

Returns a reference to a hash of information:

    stdout
    stderr
    path     Path to the target
    cmd      The make command used

stdout is also saved into `$$hump{tempdir}/$target.out`.

stderr is saved in `$$hump{tempdir}/$target.log`.

=back

=cut

sub make{
  my($self, $target) = @_;

  $target //= 'all';

  my $stdout = "$$self{logdir}/$target.out";
  my $stderr = $stdout;
  $stderr =~ s/out$/log/;

  if(!-d dirname($stdout)){
    make_path(dirname($stdout), {error => \my $err});
    if($err){
      die "ERROR: could not make a directory for $stdout: ".Dumper $err;
    }
  }

  my $cmd = "nice make -C $$self{workdir} --quiet -f $$self{makefile} $target -j $$self{numcpus} >> $stdout 2>>$stderr";
  system($cmd);
  confess "ERROR running $cmd: $!\n\nStderr was:\n".`cat $stderr` if($?);

  open(my $stdoutFh, "<", $stdout) or die "ERROR: could not open $stdout for reading: $!";
  local $/=undef;
  my $stdoutContent = <$stdoutFh>;
  close $stdoutFh;
  
  open(my $stderrFh, "<", $stderr) or die "ERROR: could not open $stderr for reading: $!";
  local $/=undef;
  my $stderrContent = <$stderrFh>;
  close $stderrFh;
  
  return {
    stdout => $stdoutContent,
    stderr => $stderrContent,
    path   => "$$self{workdir}/$target",
    cmd    => $cmd,
  }
}

=pod

=over

=item $hump->cp($target, $to)

Copies a target to a directory that is not in the temporary directory.
Useful if you want to hold onto any temporary files.
Returns empty string on success.
If error, returns a string explaining the error.

=back

=cut

sub cp{
  my($self, $from, $to) = @_;

  my $path = "$$self{workdir}/$from";
  if(!-e $path){
    return "ERROR: could not copy target $from because it does not exist at $path";
  }

  File::Copy::cp($path, $to)
    or return "ERROR copying file $path => $to: $!";

  return "";
}

=pod

=over

=item $hump->dag

Creates a directed acyclic graph (DAG) and returns it in a string.
This string is formatted as Mermaid.

=back

=cut

# Define a subroutine to convert Makefile to Mermaid format
sub dag{
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

