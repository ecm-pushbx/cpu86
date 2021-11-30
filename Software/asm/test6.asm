
	cpu 8086
	org 256
start:
	mov ax, 0FFEFh
	mov ds, ax
	xor si, si
	mov cx, _AMOUNT

	mov word [si + 4], _ADDRESS & 0FFFFh
	mov word [si + 6], _ADDRESS >> 16
loop:
	mov byte [si + 12], 1

	mov ax, word [si + 6]
	call disp_ax_hex
	mov al, '_'
	call disp_al
	mov ax, word [si + 4]
	call disp_ax_hex
	mov al, '='
	call disp_al
	mov ax, word [si + 2]
	call disp_ax_hex
	mov al, '_'
	call disp_al
	mov ax, word [si]
	call disp_ax_hex
	mov al, 13
	call disp_al
	mov al, 10
	call disp_al

	add word [si + 4], _STRIDE
	adc word [si + 6], 0
	loop loop

exit:
	xor ax, ax
	int 16h
	int 19h



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
