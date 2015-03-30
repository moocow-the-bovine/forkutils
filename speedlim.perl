#!/usr/bin/perl -w

## File: speedlim.perl
## Author: Bryan Jurish <moocow@cpan.org>
## Description:
##  + speed limit: output watcher (e.g. as piped from `tail -f`)

use File::Basename qw(basename dirname);
use Getopt::Long (':config'=>'no_ignore_case');
use Event qw(loop unloop unloop_all);
use strict;

BEGIN {
  select(STDIN); $|=1;
  select(STDERR); $|=1;
  select(STDOUT); $|=1;
}

##======================================================================
## Command-line

our $prog = basename($0);
my $interval = 1;
my $watch = 0;
my ($help);
GetOptions(##-- general
	   'help|h' => \$help,
	   'interval|i|limit|l=i' => \$interval,
	   'watch|w!' => \$watch,
	  );

if ($help) {
  print STDERR <<EOF;

Usage: $prog \[OPTIONS] [FILE]

 Options:
   -help        # this help message
   -limit SECS  # maximum inter-message interval (default=1)
   -[no]watch   # do/don't continue at EOF (default=-nowatch)

EOF
  exit 0;
}

##======================================================================
## MAIN
my $infile  = (shift(@ARGV) || '-');
open(IN, "<$infile") or die("$prog: open failed for '$infile': $!");
our $msg;

sub cb_timer {
  print $msg if (defined($msg));
  $msg = undef;
}
sub cb_io {
  my $line = <IN>;
  if (!defined($line)) {
    unloop_all(0) if (!$watch);
  } else {
    $msg = $line;
  }
}
Event->timer(interval=>$interval, cb=>\&cb_timer);
Event->io(fd=>\*IN, poll=>'r', cb=>\&cb_io);
my $rc = loop();

die("$0: loop failed with exit status $rc") if ($rc != 0);
print $msg if (defined($msg));
