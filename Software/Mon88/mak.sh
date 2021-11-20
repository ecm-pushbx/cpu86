#! /bin/bash

# Usage of the works is permitted provided that this
# instrument is retained with the works, so that any entity
# that uses the works is notified of this instrument.
#
# DISCLAIMER: THE WORKS ARE WITHOUT WARRANTY.

[ -z "$NASM" ] && NASM=nasm

"$NASM" MON88.ASM -l mon88.lst -o mon88.bin "$@"
(($?)) && exit $?

gcc bin2mif.c -o bin2mif
(($?)) && exit $?
./bin2mif mon88.bin ../../mx_sdram/mon88.mif 32768
