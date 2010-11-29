#!/bin/sh

tic_sleep=5

do_tic() {
    echo "$0[$$]:stderr" "$@" ": TIC: " `date -R` 1>&2
    echo "$0[$$]:stdout" "$@" ": TIC: " `date -R`
}

while true ; do
  do_tic "$@"
  sleep "$tic_sleep"
done
