#!/usr/bin/python

from subprocess import call;
from time import sleep

sleep(5)

while 1:
  print "forkme: "
  call(["date","-R"])
  sleep(3)
