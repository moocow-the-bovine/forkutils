use ExtUtils::MakeMaker;

my $VERSION = 0.01;

##----------------------------------------------------------------------
## MAIN
##----------------------------------------------------------------------
WriteMakefile
  (
   NAME		=> 'forkutils',
   AUTHOR       => 'Bryan Jurish <jurish@uni-potsdam.de>',
   ABSTRACT	=> 'Useful daemon utilities',
   VERSION	=> $VERSION,

   PREREQ_PM    => {
		    'Date::Format' => undef,
		    'File::Basename' => undef,
		    'Getopt::Long' => undef,
		    'Pod::Usage' => undef,
		    'English' => undef,
		   },

   EXE_FILES   => [glob('*.perl')],
  );
