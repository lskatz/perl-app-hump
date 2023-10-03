use strict;
use warnings;
use File::Basename qw/dirname/;
use File::Temp qw/tempdir/;
use FindBin qw/$RealBin/;
use IO::Uncompress::Gunzip qw/gunzip $GunzipError/;
use Data::Dumper qw/Dumper/;

use Test::More tests=>2;

use lib "$RealBin/../lib";
use_ok 'App::Hump';

use App::Hump qw/$make_target $make_deps/;

subtest 'basic' => sub{
  plan tests => 3;

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
        "echo 'Hello' > $make_target",
      ],
    },
    "world.txt" => {
      DEP => [],
      CMD => [
        "echo 'World' > $make_target",
      ],
    },
  );

  my $hump = App::Hump->new();
  $hump->write_makefile(\%make);
  my $stdout = $hump->run_makefile();

  # whitespace trim
  $stdout =~ s/^\s+|\s+$//g;

  is($stdout, "Hello World", "Hello World!");

  my $dag = $hump->dag();

  #note `cat $hump->{makefile}`;
  #note ' ';
  #note $dag;

  subtest 'dag' => sub{
    plan tests=>3;
    my @line = split(/\n/, $dag);
    
    is(scalar(grep {/hello.txt\s+-->\s+all/} @line), 1, "hello.txt --> all");
    is(scalar(grep {/world.txt\s+-->\s+all/} @line), 1, "world.txt --> all");
    is(scalar(grep {/graph\s+(TB|TD|BT|RL)/} @line), 1, "graph TD");
  };

  subtest 'makefile file' => sub{
    plan tests=>2;
    my $makefileContent = `cat $$hump{makefile}`;
    my $stringified = "$hump";
    is($stringified, $makefileContent, "stringify object");
    is($hump->toString, $makefileContent, "toString()");
  };

};


