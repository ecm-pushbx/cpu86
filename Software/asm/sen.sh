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

nasm "$source" -f ith -o output.hex -l output.lst "$@"
(($?)) && exit $?

# :02 0000 02 0380 79
# 02: length
# 0000: address
# 02: EAD
# 0380: CS
# 79: checksum
echo -ne '\r'
sleep 0.02
(echo "l:02000002038079"; cat output.hex) | sed -re 's/:00000001FF/:040000030380010075/g' | tr -d '\n' | ./s1.pl $s1opt -
# :04 0000 03 0380 0100 75
# 04: length
# 0000: address
# 03: SSA
# 0380: CS
# 0100: IP
# 75: checksum
