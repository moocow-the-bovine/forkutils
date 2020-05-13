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
our $VERSION = "0.23";
our $SVNID   = q(
  $HeadURL$
  $Id$
);

our $logfile=undef;
our ($logfh);
our $prefix='%F %T%z ';
our $workdir=undef;

our @cmd=qw();

our $prog    =basename($0);
our $verbose = 0;
our $echo    = 0;
our $echo_stamp = 1; ##-- echo timestamps?
our $dolog   = 1;
our $ignore_child_errors =0;
our $log_append =0;
our $log_gzip=0;
our @prune_globs = qw();
our $prune_age  = -1; ##-- maximum age (days) of old log-files to keep
our $prune_keep = -1; ##-- maximum number of old log-files to keep (most recent)
our $ctxlines = 0;
our $umask = '';

my $echo_filter = '';
my $log_filter  = '';
my ($echo_filter_re,$log_filter_re);
my %filter_presets = (
		      'make' => '\bmake\b|\*\*\*',
		      'make-error' => '\bmake\b|\*\*\*|FATAL|ERROR',
		      'make-errors' => '\bmake\b|\*\*\*|FATAL|ERROR',
		      'make-warn' => '\bmake\b|\*\*\*|FATAL|ERROR|WARN',
		      'make-warnings' => '\bmake\b|\*\*\*|FATAL|ERROR|WARN',
		      'make-info' => '\bmake\b|\*\*\*|FATAL|ERROR|WARN|INFO',
		      'make-debug' => '\bmake\b|\*\*\*|FATAL|ERROR|WARN|INFO|DEBUG',
		      'make-trace' => '\bmake\b|\*\*\*|FATAL|ERROR|WARN|INFO|DEBUG|TRACE',
		     );

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
	   'echo-stamp|es!' => \$echo_stamp,
	   'echo-filter-regex|echo-filter|echofilter|echo-regex|echoregex|efr|er=s' => \$echo_filter,
	   'echo-filter-preset|echo-preset|efp|eP=s' => sub {
	     $echo=1;
	     warn("$prog: unknown filter preset '$_[1]'") if (!defined($echo_filter=$filter_presets{$_[1]}));
	   },


	   ##-- process tweaking
	   'directory|dir|d|chdir|cd=s' => \$workdir,
	   'ignore-child-errors|ignore-errors|ignore|i!' => \$ignore_child_errors,
	   'dump-errors|logdump|ld|dump|D!' => sub {$ignore_child_errors=!$_[1]},
	   'context-lines|context|ctx|cl|L=i' => \$ctxlines,
	   'umask|u=s' => \$umask,

	   ##-- logging
	   'log-prefix|logprefix|lp|prefix|p=s' => \$prefix,
	   'log-file|logfile|lf|log|l=s' => \$logfile,
	   'log-filter-regex|log-filter|logfilter|log-regex|logregex|lfr|lr=s' => \$log_filter,
	   'log-filter-preset|log-preset|lfp|lP=s' => sub {
	     warn("$prog: unknown filter preset '$_[1]'") if (!defined($log_filter=$filter_presets{$_[1]}));
	   },

	   'nolog' => sub { $dolog=0 },
	   'log-append|append|la|a!' => \$log_append,
	   'log-truncate|truncate|t!' => sub {$log_append=!$_[1]},
	   'log-gzip|log-zip|lz|gzip|gz|z!' => \$log_gzip,
	   'log-prune-glob|prune-glob|lpg|pg=s' => \@prune_globs,
	   'log-prune-age|prune-age|lpa|pa=i' => \$prune_age,
           'log-prune-keep|prune-keep|lpk|pk=i' => \$prune_keep,
	   'nolog-prune|noprune|nop|P' => sub { $prune_age=$prune_keep=-1; @prune_globs=qw() },
	  );


if ($version) {
  print STDERR "${prog} version ${VERSION}${SVNID}";
  exit 0;
}
pod2usage({-exitval=>0, -verbose=>0}) if ($help);
@cmd = @ARGV;

pod2usage({-exitval=>1, -verbose=>0, -msg=>'You must specify a command to run!'}) if (!@cmd);

##======================================================================
## IPC::Run overrides

##-- override IPC::Run::start() method to log child PID
BEGIN {
  no warnings 'redefine';
  *ipc_run_start_orig = \&IPC::Run::start;
  *IPC::Run::start = \&main::ipc_run_start_hacked;
}
sub ipc_run_start_hacked {
  my $self = ipc_run_start_orig(@_);
  logout("$prog: kids=", join(' ', map {($_->{PID}//'-1')} @{$self->{KIDS}//[]}), "\n") if ($self);
  return $self;
}


##======================================================================
## Subroutines

##--------------------------------------------------------------
## handle subprocess output

our $log_prefix = POSIX::strftime($prefix,localtime);
our $log_buf    = '';
sub logout {
  my @msg = split(/\R/,join('',$log_buf,@_));
  $log_buf = (@msg && $_[$#_] !~ /\R\z/) ? pop(@msg) : '';

  $log_prefix = POSIX::strftime($prefix,localtime);
  logout_fh($logfh,   $log_filter_re, @msg) if ($logfh);

  $log_prefix = '' if (!$echo_stamp);
  logout_fh(\*STDOUT, $echo_filter_re,@msg) if ($echo || $verbose >= 1);
}

sub logout_fh {
  my ($fh,$filter_re,@lines) = @_;
  print $fh map {$log_prefix.$_."\n"} grep {!$filter_re || $_ =~ $filter_re} @lines;
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
       ($echo_filter ? "$prog: echo_filter=$echo_filter\n" : qw()),
       "$prog: dolog=", ($dolog ? 'yes' : 'no'), "\n",
       ($dolog
	? ("$prog: logfile=$logfile\n",
	   "$prog: log_gzip=", ($log_gzip ? 'yes' : 'no'), "\n",
	   "$prog: log_append=", ($log_append ? 'yes' : 'no'), "\n",
	   ($log_filter ? "$prog: log_filter=$log_filter\n" : qw()),
	  )
	: qw()),
       "$prog: prune_globs=", join(' ', @prune_globs), "\n",
       "$prog: prune_age=$prune_age \[~ $prune_timestamp]\n",
       "$prog: prune_keep=$prune_keep\n",
       "$prog: ignore_child_errors=", ($ignore_child_errors ? 1 : 0), "\n",
       "$prog: pid=$$\n",
      );

##-- compile filter regexes if requested
$echo_filter_re = qr{$echo_filter} if ($echo_filter);
$log_filter_re  = qr{$log_filter} if ($log_filter);

##-- prune?
if ($prune_age >= 0 || $prune_keep >= 0) {

  ##-- get pruning candidates
  my (%old_files);
  foreach my $glob (@prune_globs, ($log_gzip ? (map {"$_.gz"} @prune_globs) : qw())) {
    logout("$prog: searching for stale file(s): $glob\n");
    foreach my $file (grep {-w $_ && $_ ne ($logfile//'')} (glob($glob), $log_gzip ? "$glob.gz" : qw())) {
      $old_files{$file} = {file=>$file, prune=>undef, mtime=>(stat($file))[9]};
    }
  }
  my @old_files = sort {$b->{mtime} <=> $a->{mtime}} values(%old_files);

  ##-- only prune those old log-files which exceed $prune_age threshold (if specified)
  if ($prune_age >= 0) {
    $_->{prune} = ($_->{mtime} < $prune_min_mtime)||0 foreach (@old_files);
  }

  ##-- always keep up to $prune_keep old log-files (if specified)
  if ($prune_keep >= 0) {
    $_->{prune} //= 1 foreach (@old_files); ##-- in case user specified only $prune_keep
    for (my $fi=0; $fi < $prune_keep && $fi <= $#old_files; ++$fi) {
      $old_files[$fi]{prune} = 0;
    }
  }

  ##-- actually prune selected files
  foreach my $f (@old_files) {
    if ($f->{prune}) {
      logout("$prog: PRUNE $f->{file}\n");
      unlink($f->{file})
        or logout("$prog: WARNING: failed to prune file '$f->{file}': $!\n");
    }
    #else {
    #  logout("$prog: KEEP $f->{file}\n");
    #}
  }
}

##-- open & run subprocess
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
       ($logfile
	? (
	   "$prog: log dump ($logfile", ($ctxlines>=0 ? ", $ctxlines context line(s)" : qw()), "):\n",
	   ("-" x 80), "\n",
	  )
	: qw()));
      dumplog($logfile);
  }
}

##-- gzip?
if ($log_gzip && !$logtmp && $dolog) {
  if ($log_append && -e "$logfile.gz") {
    ##-- append + gzip
    open(my $oldfh, '-|', qw(gunzip -c),"$logfile.gz")
      or die("$0: failed to open previous logfile '$logfile.gz' for append+gzip: $!");
    open(my $tmpfh, ">$logfile.tmp")
      or die("$0: failed to open temporary logfile '$logfile.tmp' for append+gzip: $!");
    File::Copy::copy($oldfh, $tmpfh)
	or die("$0: failed to copy old log data from '$logfile.gz' to '$logfile.tmp' for append+gzip: $!");
    File::Copy::copy($logfile, $tmpfh)
	or die("$0: failed to copy current log data from '$logfile.gz' to '$logfile.tmp' for append+gzip: $!");
    close($oldfh);
    close($tmpfh)
      or die("$0: failed to close temporary logfile '$logfile.tmp' for append+gzip: $!");
    unlink($logfile)
      or die("$0: failed to unlink current logfile '$logfile' for append+gzip: $!");
    rename("$logfile.tmp",$logfile)
      or die("$0: failed to rename temporary logfile '$logfile.tmp' to '$logfile' for append+gzip: $!");
  }
  ##-- truncate+gzip: easy
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
  -es, -[no]echo-stamp     # do/don't echo timestamps to stdout (default: do)
  -er, -echo-regex=REGEX   # only echo lines matching REGEX (default: all)
       -echo-preset=CLASS  # echo-filter preset aliases:
                           #  Preset     Filter-Regex
		           #  make       \bmake\b|\*\*\*
		           #  make-error \bmake\b|\*\*\*|FATAL|ERROR
		           #  make-warn  \bmake\b|\*\*\*|FATAL|ERROR|WARN
		           #  make-info  \bmake\b|\*\*\*|FATAL|ERROR|WARN|INFO
		           #  make-debug \bmake\b|\*\*\*|FATAL|ERROR|WARN|INFO|DEBUG
		           #  make-trace \bmake\b|\*\*\*|FATAL|ERROR|WARN|INFO|DEBUG|TRACE
  -q,  -quiet              # alias for -verbose=0
  -d,  -dir=DIRECTORY      # set working directory
  -u,  -umask=UMASK        # override umask (octal string)
  -l,  -logfile=LOGFILE    # redirect stdout,stderr to LOGFILE (default=temporary)
       -nolog              # don't actually write a logfile
  -lr, -log-regex=REGEX    # only log lines matching REGEX (default: all)
  -L,  -lines=LINES        # number of context lines to dump on error (default=-1: all)
  -p,  -prefix=PREFIX      # format logfile with strftime() PREFIX (default='%F %T%z ')
  -D,  -[no]dump           # do/don't dump log to stdout if CMD exits with nonzero status (default=do)
  -i,  -[no]ignore-errors  # inverse of -[no]dump
  -a,  -[no]append         # do/don't append to existing LOGFILE (default=don't)
  -t,  -[no]truncate       # inverse of -[no]append
  -z,  -[no]gzip           # do/don't gzip successful logs (default=don't)
  -pg, -prune-glob=GLOB    # select old log-files for potential pruning (default from LOGFILE)
  -pa, -prune-age=DAYS     # prune old files with mtime >= DAYS day(s) (default=-1: no pruning)
  -pk, -prune-keep=NKEEP   # keep NKEEP most recent old files (default=-1: no pruning)
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

Copyright (c) 2012-2020, Bryan Jurish.  All rights reserved.

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

