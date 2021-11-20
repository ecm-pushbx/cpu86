#! /usr/bin/perl

# Usage of the works is permitted provided that this
# instrument is retained with the works, so that any entity
# that uses the works is notified of this instrument.
#
# DISCLAIMER: THE WORKS ARE WITHOUT WARRANTY.

use warnings;
use strict;

use Time::HiRes;
use Getopt::Long;

our $sleepduration = 0.008;

GetOptions(
	'sleepduration=f' => \$sleepduration,
) or die;

$| = 1;
$\ = '';
LINE:
  while (<>) {
    if (/^[\r\n]+$/) {
      next;
    }
    my @arr = split(//, $_);
    foreach my $char (@arr) {
      Time::HiRes::sleep($sleepduration);
      print ($char);
    }
  }
