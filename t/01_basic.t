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
  plan tests => 1;

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
};


