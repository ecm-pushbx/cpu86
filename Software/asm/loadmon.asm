
	cpu 8086
	org 100h
start:
	push cs
	pop ds
	xor ax, ax
	mov es, ax
	mov di, 400h
	mov si, payload + 400h
	mov cx, (payload.length - 400h) / 2
	rep movsw
	jmp 0:400h

	align 16
payload:
.:
	incbin "mon88.bin"
	align 16
.length: equ $ - .
