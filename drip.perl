#!/usr/bin/perl -w

BEGIN {
  select(STDIN); $|=1;
  select(STDERR); $|=1;
  select(STDOUT); $|=1;
}

my $rate = shift || 1;
my $n    = shift || 0;
my $i = 0;
while (1) {
  print "drip: ", ++$i, "\n";
  print "INFO: i=$i\n" if (($i % 10)==0);
  last if ($i==$n);
  select(undef,undef,undef, $rate);
}
