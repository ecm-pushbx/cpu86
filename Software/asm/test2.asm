
	org 256

start:
	push cs
	pop ds

	mov si, msgkey
	call disp_msg
.loop:
	mov ah, 1
	int 16h
	jz .loop
	call disp_ax_hex
	mov al, 13
	call disp_al
	mov al, 10
	call disp_al

	mov ah, 0
	int 16h
	call disp_ax_hex
	mov al, 13
	call disp_al
	mov al, 10
	call disp_al

exit:
	mov ax, 4C26h
	int 21h



disp_ax_hex:
		xchg ah, al
		call disp_al_hex
		xchg ah, al

disp_al_hex:
		push cx
		mov cl, 4
		ror al, cl
		call .nibble
		ror al, cl
		pop cx
.nibble:
		push ax
		and al, 0Fh
		add al, '0'
		cmp al, '9'
		jbe .isdigit
		add al, 'A'-('9'+1)
.isdigit:
		call disp_al
		pop ax
		retn


	; Following call: Display number in ax decimal
disp_ax_dec:			; ax (no leading zeros)
	; In: number in ax
	; Out: displayed
		push bx
		push dx
		xor bx, bx
.pushax:
		push ax
.pushend:
		test bl, bl
		jz .nobl
		sub bl, 5
		neg bl
.nobl:
		push cx
		mov cx, 10000
		call .divide_out
		mov cx, 1000
		call .divide_out
		mov cx, 100
		call .divide_out
		mov cl, 10
		call .divide_out
							; (Divisor 1 is useless)
		add al, '0'
		call disp_al
		pop cx
		pop ax
		pop dx
		pop bx					; Caller's register
		retn

.divide_out:
	; In: ax = number
	;     cx = divisor
	; Out: ax = remainder of operation
	;      result displayed
		push dx
		xor dx, dx
		div cx				; 0:ax / cx
		push dx				; remainder
		dec bl
		jnz .nobl2
		or bh, 1
.nobl2:
		or bh, al
		jz .leadingzero
		add al, '0'
		call disp_al
.leadingzero:
		pop ax				; remainder
		pop dx
		retn


disp_al:
	push ax
	push bx
	push bp
	mov ah, 0Eh
	mov bx, 7
	int 10h
	pop bp
	pop bx
	pop ax
	retn

disp_msg:
	push si
	push ax
.loop:
	lodsb
	test al, al
	jz .end
	call disp_al
	jmp .loop

.end:
	pop ax
	pop si
	retn

msgkey:	db 13,10,"Press any key: ",0
