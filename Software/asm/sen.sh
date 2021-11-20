#! /bin/bash

# Usage of the works is permitted provided that this
# instrument is retained with the works, so that any entity
# that uses the works is notified of this instrument.
#
# DISCLAIMER: THE WORKS ARE WITHOUT WARRANTY.

source="$1"
shift

nasm "$source" -f ith -o output.hex "$@"
(($?)) && exit $?

(echo "l:020000020000FC"; cat output.hex) | sed -re 's/:00000001FF/:0400000300000100F8/g' | tr -d '\n' | ./s1.pl -
