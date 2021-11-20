
	cpu 8086
	org 256
start:
	push cs
	pop es
	mov di, data
	mov ax, 0AA55h
	mov cx, data.length / 2
	repe scasw
	je good
bad:
	mov ax, 4CFFh
	int 21h

good:
	mov ax, 4C00h
	int 21h

	align 2
data:
.:
	times _AMOUNT dw 0AA55h
.length: equ $ - .
