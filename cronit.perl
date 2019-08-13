#!/usr/bin/perl -w

## File: cronit.perl
## Author: Bryan Jurish <moocow@cpan.org>
## Description:
##  + generic cron job wrapper

use Getopt::Long (':config'=>'no_ignore_case');
use File::Basename qw(basename dirname);
use Sys::Hostname;
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
our $VERSION = "0.15";
our $SVNID   = q(
  $HeadURL$
  $Id$
);

our $logfile=undef;
our ($logfh);
our $prefix='%F %T ';
our $workdir=undef;

our @cmd=qw();

our $prog    =basename($0);
our $verbose = 0;
our $echo    = 0;
our $dolog   = 1;
our $ignore_child_errors =0;
our $log_append =0;
our $log_gzip=0;
our @prune_globs = qw();
our $prune_age = -1;
our $ctxlines = 0;
our $umask = '';
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
	   'echo|e!' => \$echo,

	   ##-- process tweaking
	   'directory|dir|d|chdir|cd=s' => \$workdir,
	   'ignore-child-errors|ignore-errors|ignore|i!' => \$ignore_child_errors,
	   'dump-errors|logdump|ld|dump|D!' => sub {$ignore_child_errors=!$_[1]},
	   'context-lines|context|ctx|cl|L=i' => \$ctxlines,
	   'umask|u=s' => \$umask,

	   ##-- logging
	   'log-prefix|logprefix|lp|prefix|p=s' => \$prefix,
	   'log-file|logfile|lf|log|l=s' => \$logfile,
	   'nolog' => sub { $dolog=0 },
	   'log-append|append|la|a!' => \$log_append,
	   'log-truncate|truncate|t!' => sub {$log_append=!$_[1]},
	   'log-gzip|log-zip|lz|z!' => \$log_gzip,
	   'log-prune-glob|prune-glob|lpg|pg=s' => \@prune_globs,
	   'log-prune-age|prune-age|lpa|pa=i' => \$prune_age,
	   'nolog-prune|noprune|nop|P' => sub { $prune_age=-1; @prune_globs=qw() },
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
  $logfh->print($msg) if ($logfh);
  print STDOUT $msg if ($echo || $verbose >= 1);
}

## $bool = dumplog($logfile)
##  + dump $logfile to STDOUT, honoring $ctxlines
sub dumplog {
  my $logfile = shift;
  return if (!$logfile || !$dolog);

  ##-- full dump
  return File::Copy::copy($logfile,\*STDOUT) if ($ctxlines <= 0);

  ##-- dump up to $ctxlines initial, final lines of $logfile
  open(my $logfh, "<$logfile")
    or die("$prog: failed to open '$logfile' for dump: $!");

  ##-- dump initial context
  my $n = 0;
  while ($n < $ctxlines && defined($_=<$logfh>)) {
    print $_;
    ++$n if (!/\S+ \S+ \Q$prog\E: /);
  }

  ##-- churn through remaining lines, buffering as we go
  if ($n == $ctxlines) {
    my @buf = qw();
    while (defined($_=<$logfh>)) {
      ++$n;
      shift(@buf) if (@buf==$ctxlines);
      push(@buf,$_);
    }
    print "... [", ($n-$ctxlines-@buf), " line(s) truncated] ...\n";
    print @buf;
  }
  $logfh->close();
}


##======================================================================
## MAIN

##-- set umask if requested
if (($umask//'') ne '') {
  umask(oct($umask));
}

##-- change directory if requested
if ($workdir) {
  chdir($workdir) or die("$prog: could not chdir to '$workdir': $!");
}

##-- get logfile
our $logtmp  = 0;
if ($dolog && defined($logfile)) {
  ##-- auto-prune
  my $glob = $logfile;
  $glob =~ s{\{(?:DATE|TIME|DATETIME)\}}{*}g;
  push(@prune_globs,$glob) if (!@prune_globs && $glob ne $logfile);

  ##-- logfile escapes
  $logfile =~ s{{DATE}}{strftime("%F",localtime(time))}e;
  $logfile =~ s{{TIME}}{strftime("%T",localtime(time))}e;
  $logfile =~ s{{DATETIME}}{strftime("%F-%H%M%S",localtime(time))}e;

  ##-- open log filehandle
  my $logmode = $log_append ? '>>' : '>';
  $logfh = IO::File->new("${logmode}${logfile}") or die("$prog: open failed for logfile '$logfile', mode $logmode: $!");
} elsif ($dolog) {
  ##-- log to tempfile
  $logtmp = 1;
  my $tmpdir = ($ENV{TMPDIR}||$ENV{TMP}||'/tmp');
  push(@prune_globs, "$tmpdir/cronit*.log") if (!@prune_globs); ##-- auto-prune
  ($logfh,$logfile) = File::Temp::tempfile('cronitXXXXXXXX', DIR=>$tmpdir, SUFFIX=>'.log', UNLINK=>1);
  die("$prog: couldn't open temporary logfile: $!") if (!defined($logfh));
}
$logfh->autoflush(1) if ($logfh);

##-- report configuration
our $cmd_str = join(' ', map {/\s/ ? qq("$_") : $_} @cmd);
#my $user     = getlogin() || [getpwuid($<)]->[0]; ##-- getlogin() returns same as $ENV{SUDO_USER} under sudo
my $user     = $ENV{SUDO_USER} || [getpwuid( $< )]->[0] || getlogin() || '?';
my $e_user   = [getpwuid( $> )]->[0] || getlogin() || '?';
my $group    = [getgrgid( $( )]->[0] || '?';
my $e_group  = [getgrgid( $) )]->[0] || '?';
my $host     = Sys::Hostname::hostname();
my $hostname = (gethostbyname($host || 'localhost'))[0] || $host || '(unknown)';
my $prune_min_mtime = $prune_age >= 0 ? (time()-($prune_age*24*60*60)) : undef;
my $prune_timestamp = $prune_age >= 0 ? strftime("%F %T",localtime($prune_min_mtime)) : 'none';
logout("$prog: cmd=$cmd_str\n",
       "$prog: cwd=", cwd(), "\n",
       "$prog: user=$e_user".($user ne $e_user ? " (<$user)" : '')."\n",
       "$prog: group=$e_group".($group ne $e_group ? " (<$group)" : '')."\n",
       "$prog: umask=".(sprintf("%0.4o", umask))."\n",
       "$prog: host=$hostname\n",
       "$prog: echo=", ($echo ? 'yes' : 'no'), "\n",
       "$prog: dolog=", ($dolog ? 'yes' : 'no'), "\n",
       ($dolog
	? ("$prog: logfile=$logfile\n",
	   "$prog: log_gzip=", ($log_gzip ? 'yes' : 'no'), "\n",
	   "$prog: log_append=", ($log_append ? 'yes' : 'no'), "\n",
	  )
	: qw()),
       "$prog: prune_globs=", join(' ', @prune_globs), "\n",
       "$prog: prune_age=$prune_age \[~ $prune_timestamp]\n",
       "$prog: ignore_child_errors=", ($ignore_child_errors ? 1 : 0), "\n",
      );

##-- prune?
if ($prune_age >= 0) {
  my %pruned = qw();
  foreach my $glob (@prune_globs, ($log_gzip ? (map {"$_.gz"} @prune_globs) : qw())) {
    next if (exists($pruned{$glob}));
    $pruned{$glob}=undef;

    logout("$prog: pruning stale file(s): $glob\n");
    foreach my $file (grep {-w $_ && $_ ne ($logfile//'')} (glob($glob), $log_gzip ? "$glob.gz" : qw())) {
      my $mtime = (stat($file))[9];
      if (defined($mtime) && $mtime < $prune_min_mtime) {
	logout("$prog: PRUNE $file\n");
	unlink($file)
	  or logout("$prog: WARNING: failed to prune file '$file': $!\n");
      }
      #else {
      #  logout("$prog: KEEP $file\n");
      #}
    }
  }
}

##-- open subprocess
IPC::Run::run(\@cmd, '<', \undef, '>&', \&logout);
our $cmd_rc = ($?>>8);

if ($cmd_rc==0) {
  my $elapsed_s = time()-$t0;
  my ($elapsed_str);
  if ($elapsed_s >= 24*60*60) {
    my $elapsed_days = int($elapsed_s / (24*60*60));
    $elapsed_s      -= ($elapsed_days*24*60*60);
    $elapsed_str     = "$elapsed_days day(s) + ";
  }
  $elapsed_str .= strftime("%H:%M:%S", gmtime($elapsed_s))." (HH:MM:SS)";

  logout("$prog: command ($cmd_str) exited normally\n",
	 "$prog: total time elapsed = $elapsed_str\n",
	);
  $logfh->close() if ($logfh);
} else {
  $logfh->close() if ($logfh);
  if (!$ignore_child_errors) {
    print
      ("$prog: command ($cmd_str) exited abnormally with status $cmd_rc\n",
       "$prog: log dump ($logfile", ($ctxlines>=0 ? ", $ctxlines context line(s)" : qw()), "):\n",
       ("-" x 80), "\n",
      );
    dumplog($logfile);
  }
}

##-- gzip?
if ($log_gzip && !$logtmp && $dolog) {
  system(qw(gzip --force),$logfile)==0
    or warn("$0: failed to gzip log-file '$logfile': $!");
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
  -h,  -help               # this help message
  -V,  -version            # show version information and exit
  -v,  -verbose=LEVEL      # set verbosity level (default=0)
  -e,  -[no]echo           # do/don't echo commands to stdout
  -q,  -quiet              # alias for -verbose=0
  -d,  -dir=DIRECTORY      # set working directory
  -u,  -umask=UMASK        # override umask (octal string)
  -l,  -logfile=LOGFILE    # redirect stdout,stderr to LOGFILE (default=temporary)
       -nolog              # don't actually write a logfile
  -L,  -lines=LINES        # number of context lines to dump on error (default=-1: all)
  -p,  -prefix=PREFIX      # format logfile with strftime() PREFIX (default='%F %T ')
  -D,  -[no]dump           # do/don't dump log to stdout if CMD exits with nonzero status (default=do)
  -i,  -[no]ignore-errors  # inverse of -[no]dump
  -a,  -[no]append         # do/don't append to existing LOGFILE (default=don't)
  -t,  -[no]truncate       # inverse of -[no]append
  -z,  -[no]gzip           # do/don't gzip successful logs (default=don't)
  -pg, -prune-glob=GLOB    # select old log-files for potential pruning (default from LOGFILE)
  -pa, -prune-age=DAYS     # prune old files with mtime >= DAYS day(s) (default=-1: no pruning)
  -P,  -noprune            # don't prune any old files (default)

 Bells & Whistles:
  LOGFILE may contain substrings {DATE}, {TIME}, and/or {DATETIME}, which will be replaced
  by appropriate ISO strings.

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

