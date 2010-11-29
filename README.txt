    README for directory forkutils

ABSTRACT
    forkutils - generic daemon wrapper utility scripts

DESCRIPTION
    This directory contains some generic utility scripts for working with
    persistent daemon programs.

  forkit.perl
    Generic SysV-style init script for creating a persistent daemon from a
    standalone non-forking program. Takes care of forking the specified
    program to the background, redirecting stderr to a log file, and/or
    changing effective permissions of the daemon program.

  watchdog.perl
    Software watchdog for background daemon processes. Can itself be run as
    a persistent daemon under forkit.perl if desired.

AUTHOR
    Bryan Jurish <jurish@uni-potsdam.de>

