use strict;
use warnings;
use File::Basename qw/dirname/;
use File::Temp qw/tempdir/;
use FindBin qw/$RealBin/;
use IO::Uncompress::Gunzip qw/gunzip $GunzipError/;
use Data::Dumper qw/Dumper/;
use Pod::Checker qw/podchecker/;

use Test::More tests=>3;

use lib "$RealBin/../lib";
use_ok 'App::Hump';

use App::Hump qw/$make_target $make_deps/;

subtest 'linter' => sub{
  # Returns the number of errors found or -1 if no pod found
  my $pod_ok = podchecker("lib/App/Hump.pm");
  is($pod_ok, 0, "POD check");
};

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

  subtest 'make results' => sub{
    my $makeHash = $hump->make();
    my $stdout = $$makeHash{stdout};

    # whitespace trim
    $stdout =~ s/^\s+|\s+$//g;

    is($stdout, "Hello World", "Hello World!");

    my $err = $hump->cp("hello.txt", "./hello.txt.tmp");
    END{unlink("./hello.txt.tmp");}
    is($err, "", "Check \$hump->cp error");

    open(my $fh, "./hello.txt.tmp") or BAIL_OUT("Reading ./hello.txt.tmp failed: $!");
    my $hello = <$fh>;
    chomp($hello);
    close $fh;

    is($hello, "Hello", "Check hello.txt content");
    
  };

  subtest 'dag' => sub{
    plan tests=>3;

    my $dag = $hump->dag();
    my @line = split(/\n/, $dag);
    
    is(scalar(grep {/hello.txt\s+-->\s+all/} @line), 1, "hello.txt --> all");
    is(scalar(grep {/world.txt\s+-->\s+all/} @line), 1, "world.txt --> all");
    is(scalar(grep {/graph\s+(TB|TD|BT|RL)/} @line), 1, "graph TD");
  };

  subtest 'makefile file' => sub{
    plan tests=>3;
    my $makefileContent = `cat $$hump{makefile}`;
    my $stringified = "$hump";
    is($stringified, $makefileContent, "stringify object");
    is($hump->toString, $makefileContent, "toString()");

    # Check for targets in makefile
    my @makeLine = split(/\n/, $makefileContent);
    is(scalar(grep {/all:\s+hello.txt\s+world.txt/} @makeLine), 1, "rule for 'all'");
  };

};


