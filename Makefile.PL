use ExtUtils::MakeMaker;

my $VERSION = 0.02;

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
		    'Date::Format' => undef,
		    'File::Basename' => undef,
		    'Getopt::Long' => undef,
		    'Pod::Usage' => undef,
		    'English' => undef,

		    ##-- for cronit.perl
		    'POSIX' => undef,
		    'File::Temp' => undef,
		    'File::Copy' => undef,
		    'IPC::Run' => undef,

		    ##-- for speedlim.perl
		    'Event' => undef, # 1.21
		   },

   EXE_FILES   => [grep {$_ !~ /drip/} glob('*.perl')],
  );
