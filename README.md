# App::Hump

A module for workflow dependencies. Uses the power of `make` in the backend.

It might be useful as a very rudementary workflow engine.
It uses a hash of commands and dependencies to create a thoughtful
Makefile, which can then be executed.

This is not a real replacement for things like SnakeMake or NextFlow;
I wanted to make a sort of lightweight method of making a quick workflow
without thinking about things like an intense configuration file.

## Example

```perl
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
```

## Installation

```bash
git clone https://github.com/lskatz/perl-app-hump
cd perl-app-hump
perl Makefile.PL
make
make install
```

## Help

You can view more usage by running `perldoc lib/App/Hump.pm`
or by filing a ticket under the github issues tab.

