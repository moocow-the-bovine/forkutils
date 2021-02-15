use ExtUtils::MakeMaker;

my $VERSION = 0.12;

##----------------------------------------------------------------------
## MAIN
##----------------------------------------------------------------------
WriteMakefile
  (
   NAME		=> 'forkutils',
   AUTHOR       => 'Bryan Jurish <moocow@cpan.org>',
   ABSTRACT	=> 'Useful daemon utilities',
   VERSION	=> $VERSION,

   PREREQ_PM    => {
		    'Date::Format' => 0,
		    'File::Basename' => 0,
		    'Getopt::Long' => 0,
		    'Pod::Usage' => 0,
		    'English' => 0,

		    ##-- for cronit.perl
		    'POSIX' => 0,
		    'File::Temp' => 0,
		    'File::Copy' => 0,
		    'IPC::Run' => 0,

		    ##-- for speedlim.perl
		    'Event' => 0, # 1.21

		    ##-- for sockrelay.perl
		    'Sys::Syslog' => 0,
		   },

   EXE_FILES   => [grep {$_ !~ /drip/} glob('*.perl')],
  );
