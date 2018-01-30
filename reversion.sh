#!/bin/bash

## + requires perl-reversion from Perl::Version (debian package libperl-version-perl)
## + example call:
##    ./reversion.sh -bump -dryrun

pmfiles=(Makefile.PL cronit.perl forkit.perl watchdog.perl sockrelay.perl)

exec perl-reversion "$@" "${pmfiles[@]}"
