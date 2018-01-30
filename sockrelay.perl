#!/usr/bin/perl -w

## File: sockrelay.perl
## Author: Bryan Jurish <moocow@cpan.org>
## Description:
##  + socket relay using socat

use Getopt::Long (':config'=>'no_ignore_case');
use File::Basename qw(basename dirname);
use Sys::Syslog qw(:standard :macros);
use POSIX qw(strftime);
use IPC::Run;
use strict;

##======================================================================
## Globals
our $VERSION = '0.12';
our $prog = basename($0);

our @vlevels = qw(fatal error warning notice info debug);
our %vlevels = (map {($vlevels[$_]=>$_)} (0..$#vlevels));
$vlevels{$_} = $vlevels{fatal} foreach (qw(F));
$vlevels{$_} = $vlevels{error} foreach (qw(errors errs err e E));
$vlevels{$_} = $vlevels{warning} foreach (qw(warnings warn w W));
$vlevels{$_} = $vlevels{notice} foreach (qw(notice notify not n N));
$vlevels{$_} = $vlevels{info} foreach (qw(inf i I));
$vlevels{$_} = $vlevels{debug} foreach (qw(debug trace d D t T));

our (@sysprio);
$sysprio[$vlevels{fatal}] = LOG_CRIT;
$sysprio[$vlevels{error}] = LOG_ERR;
$sysprio[$vlevels{warning}] = LOG_WARNING;
$sysprio[$vlevels{notice}] = LOG_NOTICE;
$sysprio[$vlevels{info}] = LOG_INFO;
$sysprio[$vlevels{debug}] = LOG_DEBUG;

##======================================================================
## Command-line

our ($help,$version);
our $daemon    = 0;
our $pidfile   = undef;
our $log_label = $prog;
our $log_syslog = undef;
our $log_stderr = undef;
our $log_promote_connect = 1;
our $log_trace = 0;
our $log_verbose = $vlevels{notice};

GetOptions(
	   'h|help' => \$help,
	   'd|daemon!' => \$daemon,
	   'c|connect!' => \$log_promote_connect,
	   'p|pidfile=s' => \$pidfile,
	   'l|label=s' => \$log_label,
	   'y|syslog|log-syslog!' => \$log_syslog,
	   's|stderr|log-stderr!' => \$log_stderr,
	   't|trace!' => \$log_trace,
	   'v|verbose=s' => sub { $log_verbose=$vlevels{$_[1]} // $_[1] },
	  );

##-- log target defaults
if (!defined($log_syslog) && !defined($log_stderr)) {
  $log_syslog = $daemon;
  $log_stderr = !$daemon;
}

if ($help || @ARGV < 2) {
  print STDERR <<EOF;

Usage: $0 [OPTIONS] [--] SOCAT_ARG(s)...

Options:
  -h, -help           # this help message
  -l, -label LABEL    # log label (default=$prog)
  -p, -pidfile FILE   # write daemon PID to FILE
  -v, -verbose LEVEL  # set log verbosity level (default=$log_verbose)
  -d, -[no]daemon     # do/don't run in background as daemon (default=don't)
  -y, -[no]syslog     # do/don't log to syslog (default in daemon mode)
  -s, -[no]stderr     # do/don't log to stderr (default in foreground mode)
  -t, -[no]trace      # do/don't log traffic trace (default=don't)
  -c, -[no]connect    # do/don't promote log messages for new connections (default=do)

Verbosity levels:
  0, FATAL
  1, ERROR
  2, WARNING
  3, INFO
  4, NOTICE
  5, DEBUG

See also:
  See socat(1) for details on SOCAT_ARG(s), and ensure that you have the 'socat'
  program installed on your system.

EOF
  exit($help ? 0 : 1);
}

our ($h); ##-- IPC::Run harness object

##======================================================================
## Logging

if ($log_syslog) {
  openlog($log_label, 'pid,ndelay', LOG_DAEMON)
    or die("$prog: failed to open syslog: $!");
  setlogmask( LOG_UPTO($sysprio[$log_verbose]//LOG_DEBUG) );
}

## undef = vmsg($level, $msg)
sub vmsg {
  my $level = shift;
  $level = $vlevels{lc($level)} if (exists($vlevels{lc($level)}));

  if ($log_verbose >= $level) {
    if ($log_stderr) {
      print STDERR strftime("%F %T",localtime()), " $log_label\[$$\]: ", @_, "\n";
    }
    if ($log_syslog) {
      syslog( ($sysprio[$level]//LOG_DEBUG), join('',@_) );
    }
  }
  return 1;
}

##======================================================================
## Subroutines

sub logcatcher {
  my $msg = join('',@_);
  $msg =~ s/\R+\z//;
  $msg =~ s/^.*?(?=\bsocat)//;

  if ($msg =~ /^(.*?\]) ([A-Z]) (.*$)/) {
    my ($tag,$level,$content) = ($1,$2,$3);

    ##-- log connection messages as 'notice', all other notices get bumped down to 'info'
    $level = 'I' if ($log_promote_connect && $level eq 'N' && $content !~ /^accepting connection/);
    vmsg($level,$msg);
  }
  else {
    vmsg('debug',$msg);
  }

  return 0;
}

sub catcher {
  my $signame = shift;
  vmsg(0, "caught signal $signame");
  $h->kill_kill if ($h);
  vmsg(0, "exiting");
  exit 0;
}
$SIG{TERM} = $SIG{HUP} = $SIG{KILL} = \&catcher;

##======================================================================
## MAIN

my ($child);
if ($daemon && ($child=fork())) {
  ##-- parent: report & exit
  undef $pidfile;
  $log_syslog = 0;
  $log_stderr = 1;
  vmsg('notice', "spawned child process #$child");
  exit 0;
} else {
  ##-- child: log die() messages
  $SIG{__DIE__} = sub {
    vmsg('fatal',@_);
    die(@_);
  };
}

##-- write pid-file
if ($pidfile) {
  open(PIDFILE,">$pidfile")
    or die("open failed for pid-file '$pidfile': $!");
  print PIDFILE "$$\n";
  close(PIDFILE)
    or die("close failed for pid-file '$pidfile': $!");
}
END {
  unlink($pidfile) if ($pidfile && -e $pidfile);
}

##-- default socat flags
if (@ARGV==2) {
  unshift(@ARGV, '-d') if ($log_verbose >= $vlevels{warning});
  unshift(@ARGV, '-d') if ($log_verbose >= $vlevels{notice});
  unshift(@ARGV, '-d') if ($log_verbose >= $vlevels{info});
  unshift(@ARGV, '-d') if ($log_verbose >= $vlevels{debug});
  unshift(@ARGV, '-v') if ($log_trace);
}
our @socat_cmd = ('socat','-s',@ARGV);

vmsg('notice', "starting relay: ".join(' ',@socat_cmd));

$h = IPC::Run::start(\@socat_cmd, '<', \undef, '>&', IPC::Run::new_chunker, \&logcatcher);
if (!$h->finish()) {
  my @results = $h->results;
  my $rc = 0;
  foreach (0..$#results) {
    $rc ||= $results[$_];
    vmsg(0, "child #".($_+1). " exited with nonzero status $results[$_]") if ($results[$_] != 0);
  }
  vmsg(0, "bailing out!");
  $h->kill_kill;
  exit($rc);
}

vmsg(1, "exiting normally");

END {
  $h->kill_kill if ($h);
}
