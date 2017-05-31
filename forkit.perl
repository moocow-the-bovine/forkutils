#!/usr/bin/perl -w

## File: forkit.perl
## Author: Bryan Jurish <moocow@cpan.org>
## Description:
##  + generic forking daemon wrapper

use Getopt::Long (':config'=>'no_ignore_case');
use File::Basename qw(basename dirname);
use English; ##-- $UID=$<, $EUID=$>, $GID=$(, $EGID=$)
use Pod::Usage;
use strict;

##--------------------------------------------------------------
## Globals
our $VERSION = "0.11";
our $SVNID   = q(
  $HeadURL$
  $Id$
);


our $user=undef;
our $group=undef;
our $logfile=undef;
our $pidfile=undef;

our $act=undef;
our @cmd=qw();

##-- basic sanity checks
our $sleep_start=0;
our $sleep_stop=0;

our $prog = basename($0);
our $verbose=1;
our ($help,$version);


##--------------------------------------------------------------
## debug
sub show_config {
  ##-- report config
  print STDERR
    ("$0 config:\n",
     " GLOBALS: user='", ($user||''), "'; group='", ($group||''), "'; logfile='", ($logfile||''), "'; pidfile='", ($pidfile||''), "';\n",
     " \$#ARGV=$#ARGV\n",
     " \@ARGV=(", join(' ', @ARGV), ")\n",
     " act='$act'\n",
     " cmd=(", join(' ', @cmd), ")\n",
     "\n",
    );
}

##--------------------------------------------------------------
## Command-Line
GetOptions(##-- general
	   'help|h' => \$help,
	   'verbose|v=i' => \$verbose,
	   'version|V' => \$version,
	   'quiet|q' => sub { $verbose=0; },

	   ##-- checking
	   'sleep-start|ss=i' => \$sleep_start,
	   'sleep-kill|sk=i'  => \$sleep_stop,

	   ##-- process tweaking
	   'user|u=s' => \$user,
	   'group|g=s' => \$group,
	   'logfile|log|l=s' => \$logfile,
	   'pidfile|pid|p=s' => \$pidfile,
	  );


if ($version) {
  print STDERR "${prog} version ${VERSION}${SVNID}";
  exit 0;
}
pod2usage({-exitval=>0, -verbose=>0}) if ($help);
pod2usage({-exitval=>0, -verbose=>0, -msg=>'No action specified!'}) if (!@ARGV);
$act = shift(@ARGV);
@cmd = @ARGV;

pod2usage({-exitval=>1, -verbose=>0, -msg=>'You must specify either -p PIDFILE or CMD!'}) if (!defined($pidfile) && !@ARGV);


##--------------------------------------------------------------
## Functions: utilities

## @pids = getpids_ps()
##  + gets all pids for matching files using 'ps -C'
sub getpids_ps {
  ##-- scan for PID from `ps`
  my $cmdbase = basename($cmd[0]);
  open(PS,"ps -opid= -C'$cmdbase'|") or die("$prog: could not open pipe from \`ps\`: $!");
  my @pids = map {$_+0} <PS>;
  close(PS);
  return @pids;
}

## $pid_or_undef = getpid()
sub getpid {
  my ($pid);
  my $cmdbase = @cmd ? basename($cmd[0]) : undef;
  if ($pidfile && -r $pidfile) {
    ##-- read PID from a pid file
    open(PID,"<$pidfile");
    $pid=<PID>;
    close(PID);
  }
  elsif (!$pidfile) {
    ##-- scan for PID from `ps`
    $pid = (getpids_ps)[0];
  }
  $pid=($pid+0) if ($pid);

  ##-- check whether $pid is really an instance of @cmd
  if ($pid) {
    if (-r "/proc/$pid/cmdline") {
      open(CMD,"</proc/$pid/cmdline") or die("$prog: could not read /proc/$pid/cmdline: $!");
      my $cmd = <CMD>;
      close(CMD);
      $pid=undef if (!$cmd || ($cmdbase && $cmd !~ m/\Q$cmdbase\E/));
    }
    else {
      $pid=undef; ##-- pid found, but no process: probably a stale pidfile
    }
  }

  return $pid ? $pid : undef;
}


## $bool = try_open($filename_or_undef)
##  + just tries opening $filename in append mode
sub try_open {
  my $file = shift;
  return 1 if (!$file);
  my $rc = open(FILE,">>$file");
  close(FILE);
  return $rc;
}

## $rc = write_pidfile($pid)
sub write_pidfile {
  my $pid = shift;
  return 1 if (!$pidfile);
  my $rc = open(PID, ">$pidfile") or die("$prog: open failed for pidfile '$pidfile': $!");
  print PID $pid, "\n" if ($rc);
  close PID;
  return $rc;
}

## $rc = setids()
sub setids {
  if ((defined($user) || defined($group)) && $UID != 0) {
    warn("${prog}: WARNING: -user and -group options are ignored unless running as root!\n");
    return 1;
  }
  if (defined($group)) {
    my $gid = 0+($group =~ /^\d+$/ ? $group : scalar(getgrnam($group)));
    $EGID = $gid;
    die("${prog}: setids(group=$group): set EGID=$gid failed: $!") if ($! || $EGID != $gid);
    $GID = $gid;
    die("${prog}: setids(group=$group): set GID=$gid failed: $!") if ($! || $GID != $gid);
  }
  if (defined($user)) {
    my $uid = 0+($user  =~ /^\d+$/ ? $user  : scalar(getpwnam($user)));
    $EUID = $uid;
    die("${prog}: setids(user=$user): set EUID=$uid failed: $!") if ($! || $EUID != $uid);
    $UID = $uid;
    die("${prog}: setids(user=$user): set UID=$uid failed: $!") if ($! || $UID != $uid);
  }
  return 1;
}

##--------------------------------------------------------------
## Functions: status

## undef = do_status()
sub do_status {
  my $pid = getpid();
  print (($pid ? "UP (pid=$pid)" : "DOWN"), "\n");
}


##--------------------------------------------------------------
## Functions: start

## $bool = do_start()
sub do_start {
  ##-- check for command
  pod2usage({-exitval=>1, -verbose=>0, -msg=>'You must specify CMD for "start" action!'}) if (!@cmd);

  ##-- check if we're already running
  my $pid=getpid;
  die("FAILED: command already running (pid=$pid)") if ($pid);

  ##-- sanity checks: logfile, pidfile
  try_open($logfile) or die("$prog: could not open logfile '$logfile' for write: $!\n");
  try_open($pidfile) or die("$prog: could not open pidfile '$pidfile' for write: $!\n");

  ##-- startup: fork
  if ( ($pid=fork()) ) {
    ##-- parent code
    write_pidfile($pid);
    print STDERR "START (pid=$pid)\n" if ($verbose);

    ##-- check for successful startup
    if ($sleep_start) {
      sleep $sleep_start;
      my $newpid=(getpid||'');
      die "FAILED: no process with pid=$pid?\n" if (!$newpid || $newpid != $pid);
      return 1;
    }
    return 1;
  }
  else {
    ##-- child code
    $logfile = '/dev/null' if (!$logfile);
    open(LOG, ">>$logfile") or die("$prog\[$$]: could not open '$logfile' for append: $!");
    select(LOG); $|=1;
    setids();
    open(STDOUT, ">&LOG") or die("$prog\[$$]: could not redirect STDOUT to '$logfile': $!");
    select(STDOUT); $|=1;
    open(STDERR, ">&LOG") or die("$prog\[$$]: could not redirect STDERR to '$logfile': $!");
    select(STDERR); $|=1;
    local $, = ' ';
    exec(@cmd) or die("$prog: could not exec @cmd: $!\n");
    close(LOG);
    exit 0;
  }
}

##--------------------------------------------------------------
## Functions: stop

## $rc = do_stop
sub do_stop {
  ##-- check if we're already running
  my $pid = getpid;
  if ($pid) {
    print STDERR "STOP (pid=$pid)\n" if ($verbose);
    kill('TERM',$pid) or die "FAILED: could not send TERM signal to PID=$pid\n";
    sleep($sleep_stop) if ($sleep_stop);
  }

  if ($sleep_stop) {
    my $newpid=getpid;
    die "FAILED: process '$newpid' still running?\n" if ($newpid);
  }

  if ($pidfile && -e $pidfile) {
    unlink($pidfile) or die("FAILED: could not remove pidfile '$pidfile': $!\n");
  }

  return 1;
}

##--------------------------------------------------------------
## Functions: killall

sub do_killall {
  my @pids = getpids_ps;
  foreach my $pid (@pids) {
    print STDERR "KILL (pid=$pid)\n" if ($verbose);
    kill('TERM',$pid) or warn("FAILED: could not send TERM signal to PID=$pid\n");
  }
  return !getpids_ps;
}


##--------------------------------------------------------------
## Functions: listall

sub do_listall {
  pod2usage({-exitval=>1, -verbose=>0, -msg=>"You must specifiy CMD for 'listall' action!"}) if (!@cmd);
  my $cmdbase = basename($cmd[0]);
  exec(qw(ps -C), $cmdbase, '-opid,user,group,cmd');
}


##--------------------------------------------------------------
## MAIN

#show_config();

if ($act eq 'start') {
  do_start || exit 1;
}
elsif ($act eq 'stop') {
  do_stop || exit 1;
}
elsif ($act eq 'restart') {
  (do_stop && do_start) || exit 1;
}
elsif ($act eq 'status' || $act eq 'stat' || $act eq 'st') {
  do_status;
}
elsif ($act eq 'listall' || $act eq 'list' || $act eq 'l') {
  do_listall;
}
elsif ($act eq 'stopall' || $act eq 'killall' || $act eq 'kill') {
  do_killall || exit 1;
}
else {
  pod2usage({-exitval=>1, -verbose=>0, -msg=>"Unknown action '$act'"});
}


__END__

=pod

=head1 NAME

forkit.perl - generic wrapper for non-forking daemons

=head1 SYNOPSIS

 forkit.perl [OPTIONS] [--] {start|stop|restart|status|listall|killall} CMD...

 Options:
  -help               # this help message
  -version	      # show version information and exit
  -logfile=LOGFILE    # redirect stdout,stderr to LOGFILE (default=/dev/null)
  -pidfile=PIDFILE    # write PID to PIDFILE (default=none)
  -user=USER          # chuid to USER (default=none)
  -group=GROUP        # chgid to GROUP (default=none)
  -sleep-start=SECS   # sleep SECS and re-check for process on start (default=0:no check)
  -sleep-stop=SECS    # sleep SECS and re-check for process on stop (default=0:no check)

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

Copyright (c) 2010, Bryan Jurish.  All rights reserved.

This package is free software.  You may redistribute it
and/or modify it under the same terms as Perl itself.

=cut

##------------------------------------------------------------------------------
## Footer
##------------------------------------------------------------------------------
=pod

=head1 AUTHOR

Bryan Jurish E<lt>moocow@cpan.orgE<gt>

=cut

