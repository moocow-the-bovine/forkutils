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
    changing effective permissions of the daemon program. The scripts
    forkme.perl, forkme.py are pseudo-daemons for testing and debugging
    purposes.

  watchdog.perl
    Software watchdog for background daemon processes. Can itself be run as
    a persistent daemon under forkit.perl if desired.

  cronit.perl
    Wrapper script for use in cron jobs; appends a timestamp to all messages
    read from a user-specified command, logs them, and in case of abnormal
    exit status, dumps the entire log to stdout.

AUTHOR
    Bryan Jurish <jurish@uni-potsdam.de>

