
	org 256

start:
	push cs
	pop ds

	mov ax, 0
	stc
	inc ax
	inc ax
	inc ax
	dec ax
	jc .carry
.nocarry:
	mov si, nocarry
	call print
	jmp exit
.carry:
	mov si, carry
	call print

exit:
	mov ax, 4C26h
	int 21h

print:
	mov ah, 0Eh
	mov bx, 7
.loop:
	lodsb
	test al, al
	jz .end
	int 10h
	jmp .loop

.end:
	retn

carry:		db 13,10,"Carry",13,10,0
nocarry:	db 13,10,"No Carry",13,10,0
