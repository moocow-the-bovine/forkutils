#!/usr/bin/perl -w

## File: watchdog.perl
## Author: Bryan Jurish <jurish@uni-potsdam.de>
## Description:
##  + generic software watchdog

use Getopt::Long (':config'=>'no_ignore_case');
use File::Basename qw(basename dirname);
use Pod::Usage;
use strict;

##--------------------------------------------------------------
## Globals
our $VERSION = "0.01";

##-- basic sanity checks
our $sleep_interval = 300;  ##-- sleep interval (seconds)

##-- testing
our $watch_pid  = undef;   ##-- watch for a pid
our $watch_pfile =  undef; ##-- watch for a pid from $watch_pfile
our $watch_cmd  = undef;   ##-- watch for a command regex (maybe together with $watch_pid)
our $watch_test = undef;   ##-- call an external script to test

our $do_ifup = undef;
our $do_ifdown  = undef;

our $prog = basename($0);
our $verbose=1;
our ($help);


##--------------------------------------------------------------
## Command-Line
GetOptions(##-- general
	   'help|h' => \$help,
	   'verbose|v=i' => \$verbose,
	   'quiet|q' => sub { $verbose=0; },

	   ##-- checking
	   'sleep|s=i' => \$sleep_interval,

	   ##-- target selection
	   'pid|p=i' => \$watch_pid,
	   'pidfile|pf=s' => \$watch_pfile,
	   'cmdline|c=s' => \$watch_cmd,
	   'test|t=s' => \$watch_test,

	   ##-- actions
	   'on-success|ifup=s' => \$do_ifup,
	   'on-failure|ifdown=s' => \$do_ifdown,
	  );


pod2usage({-exitval=>0, -verbose=>0}) if ($help);
pod2usage({-exitval=>1, -verbose=>0, -msg=>'You must specify one of the -pid , -cmdline , or -test options!'})
  if (!(defined($watch_pid) || defined($watch_pfile) || defined($watch_cmd) || defined($watch_test)));


##--------------------------------------------------------------
## Functions: messages

## undef = vmsg($level,@msg)
sub vmsg {
  my $level = shift;
  print STDERR @_ if ($level <= $verbose);
}


##--------------------------------------------------------------
## Functions: utilities

## \$bufr = slurp($filename,\$bufr)
sub slurp {
  my ($filename,$bufr) = @_;
  if (!defined($bufr)) {
    my ($buf);
    $bufr = \$buf;
  }
  open(SLURP,"<$filename") or die("$0: open failed for '$filename': $!");
  local $/=undef;
  $$bufr = <SLURP>;
  close SLURP;
  return $$bufr;
}

## $bool = probe_pid($pid,$cmd_regex)
sub probe_pid {
  my ($pid,$cmdre) = @_;
  vmsg(3,"$prog: probe_pid(pid=", ($pid||''), ", cmd=", ($cmdre||''), ")\n");
  return 0 if (!defined($pid) || !-d "/proc/$pid");
  return 1 if (!$cmdre);
  my ($buf);
  eval { slurp("/proc/$pid/cmdline",\$buf); };
  if ($@) {
    warn("$prog: could not slurp /proc/$pid/cmdline: $@");
    $@=undef;
    return 0;
  }
  return defined($buf) && $buf =~ $cmdre;
}

## $bool = probe()
sub probe {
  if (defined($watch_pid)) {
    ##-- target: pid (maybe +command)
    return probe_pid($watch_pid,$watch_cmd);
  }
  elsif (defined($watch_pfile)) {
    ##-- target: pid file
    my ($pid);
    eval { slurp($watch_pfile,\$pid); };
    return defined($pid) && probe_pid($pid+0,$watch_cmd);
  }
  elsif (defined($watch_cmd)) {
    ##-- target: command
    my (@pids);
    eval {
      open(PS,"ps -opid= -C'$watch_cmd'|") or die("could not open pipe from 'ps': $!");
      @pids = map {$_+0} <PS>;
      close(PS);
    };
    if ($@) {
      warn("$prog: could not check for '$watch_cmd': $@");
      return 0;
    }
    return scalar(@pids);
  }
  elsif (defined($watch_test)) {
    ##-- target: user test script
    my ($rc);
    eval { $rc = system($watch_test); };
    if ($@) {
      warn("$prog: could not check for '$watch_cmd': $@");
      return 0;
    }
    return $rc==0;
  }
  warn("$prog: no check to perform!");
  return 0;
}

##--------------------------------------------------------------
## MAIN

#show_config();

##-- setup config string
our $confstr = '???';
if (defined($watch_pid)) {
  ##-- config: pid
  $confstr = "pid=\'$watch_pid\'";
  $confstr .= ", cmd=/$watch_cmd/" if (defined($watch_cmd));
}
elsif (defined($watch_pfile)) {
  $confstr = "pidfile=\'$watch_pfile\'";
  $confstr .= ", cmd=/$watch_cmd/" if (defined($watch_cmd));
}
elsif (defined($watch_cmd)) {
  $confstr = "cmd='$watch_cmd'";
}
elsif (defined($watch_test)) {
  $confstr = "test=\'$watch_test\'";
}

my ($running);
while (1) {
  vmsg(3,"$prog [$confstr]: probing...\n");
  $running = probe();
  vmsg(2,"$prog [$confstr]: probe: ", ($running ? 'ok' : 'NOT ok'), "\n");
  if ($running && defined($do_ifup)) {
    vmsg(1,"$prog [$confstr]: probe succeeded, running '$do_ifup'\n");
    system($do_ifup);
  }
  elsif (!$running && defined($do_ifdown)) {
    vmsg(1,"$prog [$confstr]: probe failed, running '$do_ifdown'\n");
    system($do_ifdown);
  }
  sleep($sleep_interval);
}



__END__

=pod

=head1 NAME

watchdog.perl - generic software watchdog

=head1 SYNOPSIS

 watchdog.perl [OPTIONS]

 General Options:
  -help               ##-- this help message
  -verbose LEVEL      ##-- set verbosity level (default=1)
  -quiet              ##-- alias for -verbose=0

 Target Selection Options:
  -pid PID            ##-- set target process with pid=PID
  -pidfile PIDFILE    ##-- read target process pid from PIDFILE at each probe
  -cmdline CMDLINE    ##-- match target process CMDLINE (also with -pid or -pidfile)
  -test COMMANDS      ##-- check with COMMANDS (0 exit status indicates success)

 Post-Probe Actions:
  -ifup COMMANDS      ##-- run COMMANDS after successful probe
  -ifdown COMMANDS    ##-- run COMMANDS after a failed probe

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

Bryan Jurish E<lt>jurish@uni-potsdam.deE<gt>

=cut

