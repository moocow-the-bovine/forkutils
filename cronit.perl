#!/usr/bin/perl -w

## File: cronit.perl
## Author: Bryan Jurish <moocow@cpan.org>
## Description:
##  + generic cron job wrapper

use Getopt::Long (':config'=>'no_ignore_case');
use File::Basename qw(basename dirname);
use POSIX qw(strftime);
use Pod::Usage;
use File::Temp;
use File::Copy;
use IPC::Run;
use IO::File;
use Cwd;
use strict;

##--------------------------------------------------------------
## Globals
our $VERSION = "0.05";
our $SVNID   = q(
  $HeadURL$
  $Id$
);

our $logfile=undef;
our ($logfh);
our $prefix='%F %T ';
our $workdir=undef;

our @cmd=qw();

our $prog   =basename($0);
our $verbose=0;
our $ignore_child_errors =0;
our $log_append =0;
our ($help,$version);

##-- timing
our $t0 = time();
our ($t1);

BEGIN {
  select(STDERR); $|=1;
  select(STDOUT); $|=1;
}

##--------------------------------------------------------------
## Command-Line
GetOptions(##-- general
	   'help|h' => \$help,
	   'verbose|v=i' => \$verbose,
	   'version|V' => \$version,
	   'quiet|q' => sub { $verbose=0; },

	   ##-- process tweaking
	   'directory|dir|d|chdir|cd=s' => \$workdir,
	   'logfile|lf|log|l=s' => \$logfile,
	   'log-append|append|la|a!' => \$log_append,
	   'log-truncate|truncate|t!' => sub {$log_append=!$_[1]},
	   'prefix|p=s' => \$prefix,
	   'ignore-child-errors|ignore-errors|ignore|i!' => \$ignore_child_errors,
	   'dump-errors|logdump|ld|dump!' => sub {$ignore_child_errors=!$_[1]},
	  );


if ($version) {
  print STDERR "${prog} version ${VERSION}${SVNID}";
  exit 0;
}
pod2usage({-exitval=>0, -verbose=>0}) if ($help);
@cmd = @ARGV;

pod2usage({-exitval=>1, -verbose=>0, -msg=>'You must specify a command to run!'}) if (!@cmd);


##======================================================================
## Subroutines

##--------------------------------------------------------------
## handle subprocess output

our $eom=1;
sub logout {
  my $prf = POSIX::strftime($prefix,localtime);
  my @msg = split(/\R/,join('',@_));
  $_      = $prf.$_ foreach (@msg[($eom ? 0 : 1)..$#msg]);
  my $msg = join("\n",@msg);
  if ($_[0] =~ /\R\z/) {
    $eom = 1;
    $msg .= "\n";
  } else {
    $eom = 0;
  }
  $logfh->print($msg);
  print STDOUT $msg if ($verbose >= 1);
}


##======================================================================
## MAIN

##-- change directory if requested
if ($workdir) {
  chdir($workdir) or die("$prog: could not chdir to '$workdir': $!");
}

##-- get logfile
our $logtmp  = 0;
if (defined($logfile)) {
  my $logmode = $log_append ? '>>' : '>';
  $logfh = IO::File->new("${logmode}${logfile}") or die("$prog: open failed for logfile '$logfile', mode $logmode: $!");
} else {
  $logtmp = 1;
  ($logfh,$logfile) = File::Temp::tempfile('cronitXXXXXXXX', DIR=>($ENV{TMPDIR}||$ENV{TMP}||'/tmp'), SUFFIX=>'.log', UNLINK=>1);
  die("$prog: couldn't open temporary logfile: $!") if (!defined($logfh));
}
$logfh->autoflush(1);

##-- report configuration
our $cmd_str = join(' ', map {/\s/ ? qq("$_") : $_} @cmd);
logout("$prog: cmd=$cmd_str\n",
       "$prog: cwd=", cwd(), "\n",
       "$prog: logfile=$logfile\n",
       "$prog: log_append=", ($log_append ? 'yes' : 'no'), "\n",
       "$prog: ignore_child_errors=", ($ignore_child_errors ? 1 : 0), "\n",
      );

##-- open subprocess
IPC::Run::run(\@cmd, '<', \undef, '>&', \&logout);
our $cmd_rc = ($?>>8);

if ($cmd_rc==0) {
  logout("$prog: command ($cmd_str) exited normally\n",
	 "$prog: total time elapsed = ", strftime("%H:%M:%S", gmtime(time()-$t0)), " (HH:MM:SS)\n",
	);
  $logfh->close();
} else {
  $logfh->close();
  if (!$ignore_child_errors) {
    print
      ("$prog: command ($cmd_str) exited abnormally with status $cmd_rc\n",
       "$prog: log dump ($logfile):\n",
       ("-" x 80), "\n",
      );
    File::Copy::copy($logfile,\*STDOUT);
  }
}

#unlink($logfile) if ($logtmp);  ##-- File::Temp should take care of this
exit $cmd_rc;

__END__

=pod

=head1 NAME

cronit.perl - generic logging wrapper for cron jobs

=head1 SYNOPSIS

 cronit.perl [OPTIONS] [--] CMD...

 Options:
  -help               # this help message
  -version	      # show version information and exit
  -verbose=LEVEL      # set verbosity level (default=1)
  -quiet              # alias for -verbose=0
  -dir=DIRECTORY      # set working directory
  -logfile=LOGFILE    # redirect stdout,stderr to LOGFILE (default=temporary)
  -prefix=PREFIX      # format logfile with strftime() PREFIX (default='%F %T ')
  -[no]dump           # do/don't dump log to stdout if CMD exits with nonzero status (default=do)
  -[no]append	      # do/don't append to existing LOGFILE (default=don't)
  -[no]truncate	      # inverse of -[no]append

=cut

##------------------------------------------------------------------------------
## Options and Arguments
##------------------------------------------------------------------------------
=pod

=head1 OPTIONS AND ARGUMENTS

Not yet written.

=cut

##------------------------------------------------------------------------------
## Description
##------------------------------------------------------------------------------
=pod

=head1 DESCRIPTION

Not yet written.

=cut

##------------------------------------------------------------------------------
## See Also
##------------------------------------------------------------------------------
=pod

=head1 SEE ALSO

...

=cut

##------------------------------------------------------------------------------
## Footer
##------------------------------------------------------------------------------
=pod

=head1 COPYRIGHT

Copyright (c) 2012-2014, Bryan Jurish.  All rights reserved.

This package is free software.  You may redistribute it
and/or modify it under the same terms as Perl itself, either
Perl 5.14.2, or at your option any later version of Perl 5
available.

=cut

##------------------------------------------------------------------------------
## Footer
##------------------------------------------------------------------------------
=pod

=head1 AUTHOR

Bryan Jurish E<lt>moocow@cpan.org<gt>

=cut

