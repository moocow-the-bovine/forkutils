#!/usr/bin/perl -w

## File: speedlim.perl
## Author: Bryan Jurish <moocow@cpan.org>
## Description:
##  + speed limit: output watcher (e.g. as piped from `tail -f`)

use File::Basename qw(basename dirname);
use Getopt::Long (':config'=>'no_ignore_case');
use Event qw(loop unloop unloop_all);
use Fcntl qw(:seek);
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
my $blank_lines = 0;
my ($help);
GetOptions(##-- general
	   'h|help' => \$help,
	   'i|interval|l|limit|p|poll=i' => \$interval,
	   'w|watch!' => \$watch,
	   'b|blanks!' => \$blank_lines,
	  );

if ($help) {
  print STDERR <<EOF;

Usage: $prog \[OPTIONS] [FILE]

 Options:
   -h, -help        # this help message
   -l, -limit SECS  # maximum inter-message interval (default=1)
   -w, -[no]watch   # do/don't continue at EOF (stdin only, default=-nowatch)
   -b, -[no]blanks  # do/don't trim blank lines (default=do)

EOF
  exit 0;
}

##======================================================================
## globals

##======================================================================
## subs: file (for watching named files)

sub min2 { return $_[0] < $_[1] ? $_[0] : $_[1]; }
sub max2 { return $_[0] > $_[1] ? $_[0] : $_[1]; }

my $blksize = 1024;
sub last_line {
  my $fh = shift;
  ##-- get final chunk of file
  my ($chunksize,@bufs,$buf);
  seek($fh, 0, SEEK_END);
  while (tell($fh) > 0 && (!@bufs || $bufs[0] !~ /\n/)) {
    $chunksize = min2(tell($fh), $blksize);
    seek($fh, -$chunksize, SEEK_CUR);
    unshift(@bufs,'');
    read($fh, $bufs[0], $chunksize);
    $bufs[0] =~ s/\n+/\n/g if (!$blank_lines);
    chomp($bufs[0]) if (@bufs==1);
    seek($fh, -$chunksize, SEEK_CUR);
  }
  $buf = join('',@bufs);
  $buf =~ s/\n+/\n/g if (!$blank_lines);
  chomp($buf);
  $buf =~ s/.*\n//s;
  return $buf."\n";
}

sub watch_file {
  my $infile = shift;
  open(my $fh,"<$infile") or die("$0: open failed for $infile: $!");
  my ($line,$cur_size);
  my $prev_size = 0;
  while (1) {
    $cur_size = (-s $fh);
    print last_line($fh) if ($cur_size != $prev_size);
    $prev_size = $cur_size;
    sleep $interval;
  }
}

##======================================================================
## subs: Event (for watching stdin)

our $msg;
sub cb_timer {
  print $msg if (defined($msg));
  $msg = undef;
}

sub cb_io {
  my $line = <STDIN>;
  if (!defined($line)) {
    unloop_all(0) if (!$watch);
  } else {
    $msg = $line;
  }
}

sub watch_stdin {
  Event->timer(interval=>$interval, cb=>\&cb_timer);
  Event->io(fd=>fileno(STDIN), poll=>'r', cb=>\&cb_io);
  my $rc = loop();
  die("$0: loop failed with exit status $rc") if ($rc != 0);
  print $msg if (defined($msg));
}

##======================================================================
## MAIN
my $infile  = shift(@ARGV) || '-';
if ($infile ne '-') {
  watch_file($infile);
} else {
  watch_stdin();
}
