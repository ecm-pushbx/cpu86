
%if 0

Load a ROM-BIOS for a cpu86-based design
 by C. Masloch, 2021

Usage of the works is permitted provided that this
instrument is retained with the works, so that any entity
that uses the works is notified of this instrument.

DISCLAIMER: THE WORKS ARE WITHOUT WARRANTY.

%endif

	cpu 8086
	org 256
start:
	jmp relocate
	align 16

image:
	incbin "c86bios.bin"

	align 16
.end:

relocate:
	cld
	push cs
	pop ds
	mov si, image
	mov cx, (image.end - image) / 2
	xor di, di
	mov es, di
	mov ss, di
	mov sp, 2000h
	mov di, 2000h
	push es
	push di
	rep movsw
	retf
