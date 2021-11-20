#! /bin/bash

# Usage of the works is permitted provided that this
# instrument is retained with the works, so that any entity
# that uses the works is notified of this instrument.
#
# DISCLAIMER: THE WORKS ARE WITHOUT WARRANTY.

s1opt=""
if [[ "$1" == --* ]]
then
  s1opt="$1"
  shift
fi

source="$1"
shift

nasm "$source" -f ith -o output.hex "$@"
(($?)) && exit $?

# :02 0000 02 0000 FC
# 02: length
# 0000: address
# 02: EAD
# 0000: CS
# FC: checksum
(echo "l:020000020000FC"; cat output.hex) | sed -re 's/:00000001FF/:0400000300000100F8/g' | tr -d '\n' | ./s1.pl $s1opt -
# :04 0000 03 00 00 01 00 F8
# 04: length
# 0000: address
# 03: SSA
# 0000: CS
# 0100: IP
# F8: checksum
