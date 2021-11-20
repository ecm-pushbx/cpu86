;**********************************************************************
; 
; MON88 (c) HT-LAB
;
; - Simple Monitor for 8088/86
; - Some bios calls
; - Disassembler based on David Moore's "disasm.c - x86 Disassembler v 0.1"
; - Requires roughly 14K, default segment registers set to 0380h
; - Assembled using A86 assembler (ported to NASM by ecm)
;
;----------------------------------------------------------------------
;
; Copyright (C) 2005-2008 Hans Tiggeler - http://www.ht-lab.com
; Send comments and bugs to http://www.ht-lab.com/misc/feedback.html
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or 
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful, but
; WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
; General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software Foundation,
; Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
;----------------------------------------------------------------------
;
; Ver 0.1     30 July 2005  H.Tiggeler   
;             First version  
; Ver 0.11    03 Sept 2005  H.Tiggeler   
;             Added support for Watcom wcl
; Ver 0.12    11 Nov 2006 H. Tiggeler
;             Support added for Opencores 16550 UART
;**********************************************************************
LF          EQU     0Ah
CR          EQU     0Dh
ESC         EQU     01Bh

;----------------------------------------------------------------------
; 16550 UART settings, use COM1
;----------------------------------------------------------------------

; Actel 9.8421MHz
;   Xtal=40MHz-> 9.8421E6/38400/16=16
;BRATE_LOW   EQU 16
;BRATE_HIGH  EQU 0

; Assume Clk=40MHz
;   Xtal=40MHz-> 40MHz/38400/16=65.10->65
;BRATE_LOW   EQU 65
;BRATE_HIGH  EQU 0

; Clock is apparently 5 MHz for the MAX1000 build
CLOCK		equ 5_000_000
BAUD		equ 9600
BRATE		equ ((CLOCK + (BAUD * 16 / 2)) / (BAUD * 16))

BRATE_LOW	equ BRATE & 255
BRATE_HIGH	equ BRATE >> 8


; UART settings, COM1
COM1        EQU     03F8h 
COM2        EQU     02F8h 
COMPORT     EQU     COM1

THRE        EQU     020h                        ; Transmit Holding Register Empty (bit5)
TEMT        EQU     040h                        ; Transmitter Empty (bit6 or LSR)
DR          EQU     001h                        ; Data Ready (bit1 of LSR)

THR         EQU     COMPORT                     ; point to Transmit data port
RBR         EQU     COMPORT                     ; point to Receive data port
LSR         EQU     COMPORT+5                   ; Line Status Register
MCR         EQU     COMPORT+4                   ; Modem, control register
DLL         EQU     COMPORT+0                   ; LSB Divisor, DLAB=1
DLM         EQU     COMPORT+1                   ; MSB Divisor, DLAB=1
LCR         EQU     COMPORT+3                   ; Line Control Register     
FCR         EQU     COMPORT+2                   ; Fifo Control Register
IIR         EQU     COMPORT+2                   ; Interrupt Identification register
IER         EQU     COMPORT+1                   ; Interrupt Enable register, DLAB=0

;----------------------------------------------------------------------
; Used for Load Hex file command
;----------------------------------------------------------------------
EOF_REC     EQU     01                          ; End of file record
DATA_REC    EQU     00                          ; Load data record
EAD_REC     EQU     02                          ; Extended Address Record, use to set CS
SSA_REC     EQU     03                          ; Execute Address

;----------------------------------------------------------------------
; PIO Base Address
;----------------------------------------------------------------------
PIO         EQU     0398h

;----------------------------------------------------------------------
; Real Time Clock 
;---------------------------------------------------------------------- 
RTC_BASE    EQU     0070h
RTC_DATA    EQU     0071h

;----------------------------------------------------------------------
; Hardware Single Step Monitor, CPU86 IP Core only!
; Single Step Registers
;
; bit3 bit2 bit1 bit0   HWM_CONFIG
;  |    |    |     \--- '1' =Enable Single Step     
;  |    |     \-------- '1' =Select TXMON output for UARTx  
;  \-----\------------- '00'=No Step    
;                       '01'=Step   
;                       '10'=select step_sw input   
;                       '11'=select not(step_sw) input
;----------------------------------------------------------------------
;HWM_CONFIG  EQU    0360h
;HWM_BITLOW  EQU    0362h                       ; 10 bits divider
;HWM_BITHIGH EQU    0363h                       ; bps=clk/HWM_BIT(9 downto 0)

;------------------------------------------------------------------------------------
; Default Base Segment Pointer
; All MON88 commands operate on the BASE_SEGMENT:xxxx address. 
; The base_segment value can be changed by the BS command
; This address should point to the end of the MON88 code (see mon88.lst file)
;------------------------------------------------------------------------------------
BASE_SEGMENT    EQU  0380h  


%macro WRSPACE 0                                ; Write space character
    MOV     AL,' '
    CALL    TXCHAR
%endmacro

%macro WREQUAL 0                                ; Write = character
    MOV     AL,'='
    CALL    TXCHAR
%endmacro

		org 0
		times 400h db 0
            ; ORG     0400h                     ; First 1024 bytes used for int vectors

INITMON:    CLI
            MOV     AX,CS                       ; Cold entry point
            MOV     DS,AX                       ; 

            MOV     SS, AX
            MOV     SP, TOS			; Set Stack pointer to Top of Stack

;----------------------------------------------------------------------
; Set baudrate for 16550
;----------------------------------------------------------------------
INITCOM:
		; Upon initialisation, the last byte written to
		;  the serial port was lost. Therefore we need to
		;  wait here until the byte is sent.
            MOV     DX,LSR                      ; Read Line Status Register
.WAITTX:    IN      AL,DX
            AND     AL,THRE                     ; Transmit Holding Register Empty?
            JZ      .WAITTX                     ; no, wait

            MOV     AL,080h                     ; Init 16550, DLAB=1
            MOV     DX,LCR
            OUT     DX,AL
                            
            MOV     AL,BRATE_LOW                ; 25MHz/(16*38400)=41 (40.6) 
            MOV     DX,DLL
            OUT     DX,AL                       ; Set low byte Latch Divisor

            MOV     AL,BRATE_HIGH               ; 
            MOV     DX,DLM
            OUT     DX,AL                       ; Set high byte Latch Divisor

            MOV     AL,03
            MOV     DX,LCR
            OUT     DX,AL                       ; 8 Bits, No Parity, 1 Stop Bit, DLAB=0
  
            MOV     AL,0C7h                     
            MOV     DX,FCR
            OUT     DX,AL                       ; FIFO Control Register
              
            MOV     AL,08h;                     ; out1 low, out2 high, for debug only   
            MOV     DX,MCR                   
            OUT     DX,AL   

;----------------------------------------------------------------------
; Set baudrate for Hardware Monitor
; 10 bits divider       
; Actel Board 9.8214/38400 -> BIT_LOW=255
; 192 for 7.3864MHz
;----------------------------------------------------------------------
;           MOV     DX,HWM_BITLOW
;           MOV     AL,255                      ; Set for Actel Board 9.8214         
;           OUT     DX,AL           ; 38400 bps
;
;           MOV     DX,HWM_BITHIGH
;           MOV     AL,00                           
;           OUT     DX,AL   

;----------------------------------------------------------------------
; Install Interrupt Vectors
; INT1 & INT3 used for single stepping and breakpoints
; INT# * 4     = Offset
; INT# * 4 + 2 = Segment
;----------------------------------------------------------------------

            XOR     AX,AX                       ; Segment=0000
            MOV     ES,AX                         

                                                ; Point all vectors to unknown handler!
            XOR     BX,BX                       ; 256 vectors * 4 bytes
NEXTINTS:   MOV     WORD [ES:BX], INTX          ; Spurious Interrupt Handler
            MOV     WORD [ES:BX+2], 0
            ADD     BX,4
            CMP     BX,0400h
            JNE     NEXTINTS                  
                         
            MOV     word [ES:04], INT1_3	; INT1 Single Step handler
            MOV     word [ES:12], INT1_3	; INT3 Breakpoint handler
            MOV     word [ES:64], INT10		; INT10h  
            MOV     word [ES:88], INT16		; INT16h  
            MOV     word [ES:104], INT1A	; INT1A, Timer functions  
            MOV     word [ES:132], INT21	; INT21h  
            mov word [es:19h * 4], int19


;----------------------------------------------------------------------
; Entry point, Display welcome message  
;----------------------------------------------------------------------
START:      CLD
            MOV     SI,WELCOME_MESS      ; -> SI
            CALL    PUTS                        ; String pointed to by DS:[SI]

            MOV     AX,BASE_SEGMENT             ; Get Default Base segment
            MOV     ES,AX 
            
;----------------------------------------------------------------------
; Process commands  
;----------------------------------------------------------------------
CMD:        MOV     SI,PROMPT_MESS       ; Display prompt >
            CALL    PUTS
                
            CALL    RXCHAR                      ; Get Command First Byte
            CALL    TO_UPPER
            MOV     DH,AL

            MOV     BX,CMDTAB1           ; Single Command?
CMPCMD1:    MOV     AL,[BX]
            CMP     AL,DH
            JNE     NEXTCMD1
            WRSPACE
            JMP     [BX+2]                      ; Execute Command
            
NEXTCMD1:   ADD     BX,4
            CMP     BX,ENDTAB1
            JNE     CMPCMD1                     ; Continue looking

            CALL    RXCHAR                      ; Get Second Command Byte, DX=command
            CALL    TO_UPPER
            MOV     DL,AL

            MOV     BX,CMDTAB2
CMPCMD2:    MOV     AX,[BX]
            CMP     AX,DX
            JNE     NEXTCMD2
            WRSPACE
            JMP     [BX+2]                      ; Execute Command
            
NEXTCMD2:   ADD     BX,4
            CMP     BX,ENDTAB2
            JNE     CMPCMD2                     ; Continue looking
            
            MOV     SI,ERRCMD_MESS       ; Display Unknown Command, followed by usage message
            CALL    PUTS                        
            JMP     CMD                         ; Try again 

		align 2, db 0
CMDTAB1     DW      'L',LOADHEX                 ; Single char Command Jump Table         
            DW      'R',DISPREG   
            DW      'G',EXECPROG
            DW      'N',TRACENEXT
            DW      'T',TRACEPROG
            DW      'U',DISASSEM
            DW      'H',DISPHELP
            DW      '?',DISPHELP
            DW      'Q',EXITMON
            DW      CR ,CMD
ENDTAB1     DW      ' '

		align 2, db 0
CMDTAB2     DW      'MF',FILLMEM                ; Double char Command Jump Table
            DW      'MD',DUMPMEM            
            DW      'PB',SETBREAKP              ; Set Breakpoint
            DW      'BC',CLRBREAKP              ; Clear Breakpoint
            DW      'BD',DISPBREAKP             ; Display Breakpoint
            DW      'RC',CHANGEREG              ; Change Register
            DW      'BO',OUTPORTB           
            DW      'SB',CHANGEBS               ; Change Base Segment Address
            DW      'WO',OUTPORTW
            DW      'BI',INPORTB
            DW      'WI',INPORTW
            DW      'BW',WRMEMB                 ; Write Byte to Memory
            DW      'WW',WRMEMW                 ; Write Word to Memory
ENDTAB2     DW      '??'

;----------------------------------------------------------------------
; Set Breakpoint
;----------------------------------------------------------------------
SETBREAKP:  MOV     BX,BPTAB             ; BX point to Breakpoint table
            CALL    GETHEX1                     ; Set Breakpoint, first get BP number
            AND     AL,07h                      ; Allow 8 breakpoints
            XOR     AH,AH
            SHL     AL,1                        ; *4 to get offset
            SHL     AL,1                        
            ADD     BX,AX                       ; point to table entry 
            MOV     BYTE [BX+3],1               ; Enable Breakpoint
            WRSPACE
            CALL    GETHEX4                     ; Get Address
            MOV     [BX],AX                     ; Save Address

            MOV     DI,AX
            MOV     AL,[ES:DI]                  ; Get the opcode
            MOV     [BX+2],AL                   ; Store in table
                        
            JMP     DISPBREAKP	; Display Enabled Breakpoints  

;----------------------------------------------------------------------
; Clear Breakpoint
;----------------------------------------------------------------------
CLRBREAKP:  MOV     BX,BPTAB             ; BX point to Breakpoint table
            CALL    GETHEX1                     ; first get BP number
            AND     AL,07h                      ; Only allow 8 breakpoints
            XOR     AH,AH
            SHL     AL,1                        ; *4 to get offset
            SHL     AL,1                        
            ADD     BX,AX                       ; point to table entry 
            MOV     BYTE [BX+3],0               ; Clear Breakpoint
                                    
            JMP     DISPBREAKP	; Display Remaining Breakpoints

;----------------------------------------------------------------------
; Display all enabled Breakpoints
; # Addr
; 0 1234
;----------------------------------------------------------------------
DISPBREAKP: CALL    NEWLINE
            MOV     BX,BPTAB
            MOV     CX,8

NEXTCBP:    MOV     AX,8
            SUB     AL,CL

            TEST    BYTE [BX+3],1               ; Check enable/disable flag
            JZ      NEXTDBP

            CALL    PUTHEX1                     ; Display Breakpoint Number
            WRSPACE
            MOV     AX,[BX]                     ; Get Address
            CALL    PUTHEX4                     ; Display it
            WRSPACE

            MOV     AX,[BX]                     ; Get Address
            CALL    DISASM_AX                   ; Disassemble instruction & Display it
            CALL    NEWLINE

NEXTDBP:    ADD     BX,4                        ; Next entry
            LOOP    NEXTCBP
            JMP     CMD                         ; Next Command  

;----------------------------------------------------------------------
; Breakpoint Table, Address(2), Opcode(1), flag(1) enable=1, disable=0
;----------------------------------------------------------------------
BPTAB       times 8 dd 0

;----------------------------------------------------------------------
; Disassemble Range
;----------------------------------------------------------------------
DISASSEM:   CALL    GETRANGE                    ; Range from BX to DX
            CALL    NEWLINE          
                        
LOOPDIS1:   PUSH    DX

            MOV     AX,BX                       ; Address in AX
            CALL    PUTHEX4                     ; Display it

            mov     BX,DISASM_CODE              ; Pointer to code storage
            mov     DX,DISASM_INST              ; Pointer to instr string
            CALL    disasm_                     ; Disassemble Opcode
            MOV     BX,AX                       ; 

            PUSH    AX                          ; New address returned in AX
            WRSPACE
            MOV     SI,DISASM_CODE
            CALL    PUTS
            CALL    STRLEN                      ; String in SI, Length in AL
            MOV     AH,15
            SUB     AH,AL
            CALL    WRNSPACE                    ; Write AH spaces
            MOV     SI,DISASM_INST
            CALL    PUTS
            CALL    NEWLINE
            POP     AX

            POP     DX
            CMP     DX,BX
            JNB     LOOPDIS1

EXITDIS:    JMP     CMD                         ; Next Command  

;----------------------------------------------------------------------
; Disassemble Instruction at AX and Display it
; Return updated address in AX
;----------------------------------------------------------------------
DISASM_AX:  PUSH    ES                          ; Disassemble Instruction
            PUSH    SI                          
            PUSH    DX                          
            PUSH    BX
            PUSH    AX

            MOV     AX,[UCS]                    ; Get Code Base segment
            MOV     ES,AX                       ;
            mov     BX,DISASM_CODE              ; Pointer to code storage
            mov     DX,DISASM_INST              ; Pointer to instr string
            POP     AX                          ; Address in AX
            CALL    disasm_                     ; Disassemble Opcode

            MOV     SI,DISASM_CODE
            CALL    PUTS
            CALL    STRLEN                      ; String in SI, Length in AL
            MOV     AH,15
            SUB     AH,AL
            CALL    WRNSPACE                    ; Write AH spaces
            MOV     SI,DISASM_INST
            CALL    PUTS

            POP     BX
            POP     DX
            POP     SI
            POP     ES
            RET

;----------------------------------------------------------------------
; Write Byte to Memory
;----------------------------------------------------------------------
WRMEMB:     CALL    GETHEX4                     ; Get Address
            MOV     BX,AX                       ; Store Address
            WRSPACE            
            
            MOV     AL,[ES:BX]                  ; Get current value and display it
            CALL    PUTHEX2
            WREQUAL
            CALL    GETHEX2                     ; Get new value
            MOV     [ES:BX],AL                  ; and write it
             
            JMP     CMD                         ; Next Command

;----------------------------------------------------------------------
; Write Word to Memory
;----------------------------------------------------------------------            
WRMEMW:     CALL    GETHEX4                     ; Get Address
            MOV     BX,AX
            WRSPACE 

            MOV     AX,[ES:BX]                  ; Get current value and display it
            CALL    PUTHEX4
            WREQUAL
            CALL    GETHEX4                     ; Get new value
            MOV     [ES:BX],AX                  ; and write it
            
            JMP     CMD                         ; Next Command  

;----------------------------------------------------------------------
; Change Register
; Valid register names: AX,BX,CX,DX,SP,BP,SI,DI,DS,ES,SS,CS,IP,FL (flag)
;----------------------------------------------------------------------
CHANGEREG:  CALL    RXCHAR                      ; Get Command First Register character
            CALL    TO_UPPER
            MOV     DH,AL
            CALL    RXCHAR                      ; Get Second Register character, DX=register
            CALL    TO_UPPER
            MOV     DL,AL

            MOV     BX,REGTAB
CMPREG:     MOV     AX,[BX]
            CMP     AX,DX                       ; Compare register string with user input
            JNE     NEXTREG                     ; No, continue search

            WREQUAL
            CALL    GETHEX4                     ; Get new value
            MOV     CX,AX                       ; CX=New reg value

            mov     DI,UAX                      ; Point to User Register Storage            
            MOV     BL,[BX+2]                   ; Get Offset
            XOR     BH,BH
            MOV     [DI+BX],CX
            JMP     DISPREG                     ; Display All registers

NEXTREG:    ADD     BX,4
            CMP     BX,ENDREG
            JNE     CMPREG                      ; Continue looking
            
            MOV     SI,ERRREG_MESS       ; Display Unknown Register Name
            CALL    PUTS                        

            JMP     CMD                         ; Try Again 

		align 2, db 0
REGTAB      DW      'XA',0                      ; register name, offset
            DW      'XB',2                  
            DW      'XC',4                  
            DW      'XD',6                  
            DW      'PS',8                  
            DW      'PB',10                 
            DW      'IS',12                 
            DW      'ID',14                 
            DW      'SD',16                 
            DW      'SE',18                 
            DW      'SS',20                 
            DW      'SC',22                 
            DW      'PI',24                 
            DW      'LF',26                 
ENDREG      DW      '??'


;----------------------------------------------------------------------
; Change Base Segment pointer
; Dump/Fill/Load operate on BASE_SEGMENT:[USER INPUT ADDRESS]
; Note: CB command will not update the User Registers!  
;----------------------------------------------------------------------
CHANGEBS:   MOV     AX,ES                       ; WORD BASE_SEGMENT
            CALL    PUTHEX4                     ; Display current value
            WRSPACE
            CALL    GETHEX4
            PUSH    AX
            POP     ES
            JMP     CMD                         ; Next Command  

 
;----------------------------------------------------------------------
; Trace Next  
;----------------------------------------------------------------------
TRACENEXT:  MOV     AX,[UFL]                    ; Get User flags
            OR      AX,0100h                    ; set TF
            MOV     [UFL],AX
            JMP     TRACNENTRY
                       
;----------------------------------------------------------------------
; Trace Program from Address
;----------------------------------------------------------------------
TRACEPROG:  MOV     AX,[UFL]                    ; Get User flags
            OR      AX,0100h                    ; set TF
            MOV     [UFL],AX
            JMP     TRACENTRY	; get execute address, save user registers etc
                        
;----------------------------------------------------------------------
; Execute program
; 1) Enable all Breakpoints (replace opcode with INT3 CC)
; 2) Restore User registers
; 3) Jump to BASE_SEGMENT:USER_OFFSET
;----------------------------------------------------------------------
EXECPROG:   MOV     BX,BPTAB             ; Enable All breakpoints
            MOV     CX,8

NEXTENBP:   MOV     AX,8
            SUB     AL,CL
            TEST    BYTE [BX+3],1               ; Check enable/disable flag
            JZ      NEXTEXBP
            MOV     DI,[BX]                     ; Get Breakpoint Address
            MOV     BYTE [ES:DI],0CCh           ; Write INT3 instruction to address

NEXTEXBP:   ADD     BX,4                        ; Next entry
            LOOP    NEXTENBP
            
TRACENTRY:  MOV     AX,ES                       ; Display Segment Address
            CALL    PUTHEX4
            MOV     AL,':'
            CALL    TXCHAR
            CALL    GETHEX4                     ; Get new IP
            MOV     [UIP],AX                    ; Update User IP
            MOV     AX,ES
            MOV     [UCS],AX
            
; Single Step Registers
; bit3 bit2 bit1 bit0
;  |    |    |     \--- '1' =Enable Single Step     
;  |    |     \-------- '1' =Select TXMON output for UARTx  
;  \-----\------------- '00'=No Step    
;                       '01'=Step   
;                       '10'=select step_sw input   
;                       '11'=select not(step_sw) input          
;           MOV     DX,HWM_CONFIG
;           MOV     AL,07h                      ; xxxx-0111 step=1
;           OUT     DX,AL                       ; Enable Trace
            
TRACNENTRY: MOV     AX,[UAX]                    ; Restore User Registers
            MOV     BX,[UBX]            
            MOV     CX,[UCX]            
            MOV     DX,[UDX]
            MOV     BP,[UBP]                        
            MOV     SI,[USI]             
            MOV     DI,[UDI]
                                                         
            MOV     ES,[UES]
            CLI                                 ; User User Stack!!
            MOV     SS,[USS]                         
            MOV     SP,[USP]
            
            PUSH    word [UFL]
            PUSH    word [UCS]                       ; Push CS (Base Segment) 
            PUSH    word [UIP]       
            MOV     DS,[UDS]
            IRET                                ; Execute!

;----------------------------------------------------------------------
; Write Byte to Output port 
;----------------------------------------------------------------------
OUTPORTB:   CALL    GETHEX4                     ; Get Port address
            MOV     DX,AX
            WREQUAL     
            CALL    GETHEX2                     ; Get Port value
            OUT     DX,AL
            JMP     CMD                         ; Next Command  

;----------------------------------------------------------------------
; Write Word to Output port 
;----------------------------------------------------------------------
OUTPORTW:   CALL    GETHEX4                     ; Get Port address
            MOV     DX,AX
            WREQUAL     
            CALL    GETHEX4                     ; Get Port value
            OUT     DX,AX
            JMP     CMD                         ; Next Command  

;----------------------------------------------------------------------
; Read Byte from Input port 
;----------------------------------------------------------------------
INPORTB:    CALL    GETHEX4                     ; Get Port address
            MOV     DX,AX
            WREQUAL
            IN      AL,DX
            CALL    PUTHEX2
            JMP     CMD                         ; Next Command  

;----------------------------------------------------------------------
; Read Word from Input port 
;----------------------------------------------------------------------
INPORTW:    CALL    GETHEX4                     ; Get Port address
            WREQUAL
            CALL    TXCHAR
            IN      AX,DX
            CALL    PUTHEX4
            JMP     CMD                         ; Next Command  

;----------------------------------------------------------------------
; Display Memory    
;----------------------------------------------------------------------
DUMPMEM:    CALL    GETRANGE                    ; Range from BX to DX
NEXTDMP:    MOV     SI,DUMPMEMS          ; Store ASCII values

            CALL    NEWLINE
            MOV     AX,ES
            CALL    PUTHEX4
            MOV     AL,':'
            CALL    TXCHAR
            MOV     AX,BX
            AND     AX,0FFF0h
            CALL    PUTHEX4
            WRSPACE                             ; Write Space
            WRSPACE                             ; Write Space
            
            MOV     AH,BL                       ; Save lsb
            AND     AH,0Fh                      ; 16 byte boundary

            CALL    WRNSPACE                    ; Write AH spaces
            CALL    WRNSPACE                    ; Write AH spaces
            CALL    WRNSPACE                    ; Write AH spaces
                        
DISPBYTE:   MOV     CX,16
            SUB     CL,AH
                
LOOPDMP1:   MOV     AL,[ES:BX]                  ; Get Byte and display it in HEX
            MOV     [SI],AL                  ; Save it
            CALL    PUTHEX2
            WRSPACE                             ; Write Space
            INC     BX
            INC     SI
            CMP     BX,DX
            JNC     SHOWREM                     ; show remaining 
            LOOP    LOOPDMP1
                                                
            CALL    PUTSDMP                     ; Display it

            CMP     DX,BX                       ; End of memory range?
            JNC     NEXTDMP                     ; No, continue with next 16 bytes

SHOWREM:    MOV     SI,DUMPMEMS          ; Stored ASCII values
            MOV     AX,BX
            AND     AX,0000Fh
            TEST    AL, al
            JZ      SKIPCLR
            ADD     SI,AX                       ; Offset
            MOV     AH,16
            SUB     AH,AL
            MOV     CL,AH
            XOR     CH,CH
            MOV     AL,' '                      ; Clear non displayed values
NEXTCLR:    MOV     [SI],AL                  ; Save it
            INC     SI
            LOOP    NEXTCLR
            CALL    WRNSPACE                    ; Write AH spaces
            CALL    WRNSPACE                    ; Write AH spaces
            CALL    WRNSPACE                    ; Write AH spaces
SKIPCLR:    XOR     AH,AH
            CALL    PUTSDMP

EXITDMP:    JMP     CMD                         ; Next Command

PUTSDMP:    MOV     SI,DUMPMEMS          ; Stored ASCII values
            WRSPACE                             ; Add 2 spaces
            WRSPACE
            CALL    WRNSPACE                    ; Write AH spaces
            MOV     CX,16
            SUB     CL,AH                       ; Adjust if not started at xxx0
NEXTCH:     LODSB                               ; Get character AL=DS:[SI++]
            CMP     AL,01Fh                     ; 20..7E printable
            JBE     PRINTDOT
            CMP     AL,07Fh
            JAE     PRINTDOT
            JMP     PRINTCH
PRINTDOT:   MOV     AL,'.'
PRINTCH:    CALL    TXCHAR                          
            LOOP    NEXTCH                      ; Next Character
            RET

WRNSPACE:   PUSH    AX                          ; Write AH space, skip if 0 
            PUSH    CX
            TEST    AH, ah
            JZ      EXITWRNP
            XOR     CH,CH                       ; Write AH spaces
            MOV     CL,AH
            MOV     AL,' '
NEXTDTX:    CALL    TXCHAR
            LOOP    NEXTDTX
EXITWRNP:   POP     CX
            POP     AX
            RET

;----------------------------------------------------------------------
; Fill Memory   
;----------------------------------------------------------------------
FILLMEM:    CALL    GETRANGE                    ; First get range BX to DX
            WRSPACE
            CALL    GETHEX2
            PUSH    AX                          ; Store fill character
            CALL    NEWLINE
                      
            CMP     DX,BX
            JB      EXITFILL
DOFILL:     SUB     DX,BX
            MOV     CX,DX            
            MOV     DI,BX                       ; [ES:DI]
            POP     AX                          ; Restore fill char
NEXTFILL:   STOSb
            LOOP    NEXTFILL
            STOSb                               ; Last byte
EXITFILL:   JMP     CMD                         ; Next Command

;----------------------------------------------------------------------
; Display Registers
;
; AX=0001 BX=0002 CX=0003 DX=0004 SP=0005 BP=0006 SI=0007 DI=0008
; DS=0009 ES=000A SS=000B CS=000C IP=0100   ODIT-SZAPC=0000-00000 
;----------------------------------------------------------------------
DISPREG:    CALL    NEWLINE
            MOV     SI,REG_MESS          ; -> SI
            mov     DI,UAX
            
            MOV     CX,8
NEXTDR1:    CALL    PUTS                        ; Point to first "AX=" string
            MOV     AX,[DI]                     ; DI points to AX value
            CALL    PUTHEX4                     ; Display AX value
            ADD     SI,5                        ; point to "BX=" string
            ADD     DI,2                        ; Point to BX value
            LOOP    NEXTDR1                     ; etc

            CALL    NEWLINE
            MOV     CX,5
NEXTDR2:    CALL    PUTS                        ; Point to first "DS=" string
            MOV     AX,[DI]                     ; DI points to DS value
            CALL    PUTHEX4                     ; Display DS value
            ADD     SI,5                        ; point to "ES=" string
            ADD     DI,2                        ; Point to ES value
            LOOP    NEXTDR2                     ; etc

            MOV     SI,FLAG_MESS
            CALL    PUTS
            MOV     SI,FLAG_VALID        ; String indicating which bits to display
            MOV     BX,[DI]                     ; get flag value in BX
            
            MOV     CX,8                        ; Display first 4 bits
NEXTBIT1:   LODSB                               ; Get display/notdisplay flag AL=DS:[SI++]
            CMP     AL,'X'                      ; Display?
            JNE     SHFTCAR                     ; Yes, shift bit into carry and display it
            SAL     BX,1                        ; no, ignore bit
            JMP     EXITDISP1
SHFTCAR:    SAL     BX,1
            JC      DISP1
            MOV     AL,'0'
            JMP     DISPBIT
DISP1:      MOV     AL,'1'
DISPBIT:    CALL    TXCHAR
EXITDISP1:  LOOP    NEXTBIT1

            MOV     AL,'-'                      ; Display seperator 0000-00000
            CALL    TXCHAR

            MOV     CX,8                        ; Display remaining 5 bits
NEXTBIT2:   LODSB                               ; Get display/notdisplay flag AL=DS:[SI++]
            CMP     AL,'X'                      ; Display?
            JNE     SHFTCAR2                    ; Yes, shift bit into carry and display it
            SAL     BX,1                        ; no, ignore bit
            JMP     EXITDISP2
SHFTCAR2:   SAL     BX,1
            JC      DISP2
            MOV     AL,'0'
            JMP     DISPBIT2
DISP2:      MOV     AL,'1'
DISPBIT2:   CALL    TXCHAR
EXITDISP2:  LOOP    NEXTBIT2

            CALL    NEWLINE                     ; Display CS:IP Instr
            MOV     AX,[UCS]                        
            CALL    PUTHEX4
            MOV     AL,':'
            CALL    TXCHAR
            MOV     AX,[UIP]
            CALL    PUTHEX4
            WRSPACE

            MOV     AX,[UIP]                    ; Address in AX
            CALL    DISASM_AX                   ; Disassemble Instruction & Display

            JMP     CMD                         ; Next Command

REG_MESS    DB  "AX=",0,0                       ; Display Register names table
            DB  " BX=",0
            DB  " CX=",0
            DB  " DX=",0
            DB  " SP=",0
            DB  " BP=",0
            DB  " SI=",0
            DB  " DI=",0

            DB  "DS=",0,0
            DB  " ES=",0
            DB  " SS=",0
            DB  " CS=",0
            DB  " IP=",0

;----------------------------------------------------------------------
; Load Hex, terminate when ":00000001FF" is received
; Mon88 may hang if this string is not received
; Print '.' for each valid received frame, exit upon error 
; Bytes are loaded at Segment=ES
;----------------------------------------------------------------------
LOADHEX:    MOV     SI,LOAD_MESS         ; Display Ready to receive upload
            CALL    PUTS                        
            
            MOV     AL,'>'
            JMP     DISPCH

RXBYTE:     XCHG    BH,AH                       ; save AH register
            CALL    RXNIB
            MOV     AH,AL
            SHL     AH,1                        ; Can't use CL
            SHL     AH,1
            SHL     AH,1
            SHL     AH,1
            CALL    RXNIB
            OR      AL,AH
            ADD     BL,AL                       ; Add to check sum
            XCHG    BH,AH                       ; Restore AH register
            RET            
            
RXNIB:      CALL    RXCHARNE                    ; Get Hex Character in AL
            CMP     AL,'0'                      ; Check to make sure 0-9,A-F
            JB      ERROR ;ERRHEX
            CMP     AL,'F'      
            JA      ERROR ;ERRHEX
            CMP     AL,'9'      
            JBE     SUB0        
            CMP     AL,'A'      
            JB      ERROR ; ERRHEX
            SUB     AL,07h                      ; Convert to hex
SUB0:       SUB     AL,'0'                      ; Convert to hex
            RET
            
                        
ERROR:      MOV     AL,'E'
DISPCH:     CALL    TXCHAR

WAITLDS:    CALL    RXCHARNE                    ; Wait for ':'
            CMP     AL,':'
            JNE     WAITLDS

            XOR     CX,CX                       ; CL=Byte count
            XOR     BX,BX                       ; BL=Checksum

            CALL    RXBYTE                      ; Get length in CX
            MOV     CL,AL

            CALL    RXBYTE                      ; Get Address HIGH
            MOV     AH,AL
            CALL    RXBYTE                      ; Get Address LOW
            MOV     DI,AX                       ; DI=Store Address

            CALL    RXBYTE                      ; Get Record Type
            CMP     AL,EOF_REC                  ; End Of File Record ("01")
            JE      GOENDLD
            CMP     AL,DATA_REC                 ; Data Record? ("00")
            JE      GOLOAD
            CMP     AL,EAD_REC                  ; Extended Address Record? ("02")
            JE      GOEAD
            CMP     AL,SSA_REC                  ; Start Segment Address Record? ("03")
            JE      GOSSA
            JMP     ERROR ;ERRREC

;GOSSAx: jmp            EXECPROG

GOSSA:      MOV     CX,2                        ; Get 2 word
NEXTW:      CALL    RXBYTE
            MOV     AH,AL
            CALL    RXBYTE
            PUSH    AX                          ; Push CS, IP
            LOOP    NEXTW
            CALL    RXBYTE                      ; Get Checksum
            SUB     BL,AL                       ; Remove checksum from checksum
            NOT     AL                          ; Two's complement
            ADD     AL,1
            CMP     AL,BL                       ; Checksum held in BL
            JNE     ERROR ;ERRCHKS           
    ; jne ERRHEX
     ;       MOV AX,0380h
      ;     PUSH AX
       ;        MOV AX,0100h
        ;   PUSH AX
;            POP        AX
;            CALL    PUTHEX4
;            POP        AX
;            CALL   PUTHEX4
;            JMP    ERRHEX                
            
            RETF                                ; Execute loaded file

GOENDLD:    CALL    RXBYTE
            SUB     BL,AL                       ; Remove checksum from checksum
            NOT     AL                          ; Two's complement
            ADD     AL,1
            CMP     AL,BL                       ; Checksum held in BL
            JNE     ERROR ;ERRCHKS
            JMP     LOADOK

GOCHECK:    CALL    RXBYTE
            SUB     BL,AL                       ; Remove checksum from checksum
            NOT     AL                          ; Two's complement
            ADD     AL,1
            CMP     AL,BL                       ; Checksum held in BL
            JNE     ERROR ;ERRCHKS
            MOV     AL,'.'                      ; After each successful record print a '.'
            JMP     DISPCH

GOLOAD:     CALL    RXBYTE                      ; Read Bytes
            STOSb                               ; ES:DI <= AL
            LOOP    GOLOAD
            JMP     GOCHECK

GOEAD:      CALL    RXBYTE
            MOV     AH,AL
            CALL    RXBYTE
            MOV     ES,AX                       ; Set Segment address (ES)
            JMP     GOCHECK

;ERRCHKS:    MOV     SI,LD_CHKS_MESS      ; Display Checksum error
;            JMP     EXITLD		; Exit Load Command
;ERRREC:     MOV     SI,LD_REC_MESS       ; Display unknown record type           
;            JMP     EXITLD		; Exit Load Command
LOADOK:     MOV     SI,LD_OK_MESS        ; Display Load OK
            JMP     EXITLD
ERRHEX:     MOV     SI,LD_HEX_MESS       ; Display Error hex value
EXITLD:     CALL    PUTS
            JMP     CMD                         ; Exit Load Command

;----------------------------------------------------------------------
; Disassembler
; Compiled, Disassembled from disasm.c
; wcl -c -0 -fpc -mt -s -d0 -os -l=COM disasm.c
; wdis -a -s=disasm.c -l=disasm.lst disasm.obj 
;----------------------------------------------------------------------
get_byte_:
            push        si
            push        di
            push        bp
            mov         bp,sp
            push        ax
            mov         si,ax
            mov         word [-2+bp],dx
            mov         ax,bx
            mov         bx,cx
            mov         di,word [si]
            mov         dl,byte [ES:di]
            mov         di,word [-2+bp]
            mov         byte [di],dl
            inc         word [si]
            test        ax,ax
            je          L$2
            test        cx,cx
            je          L$2
            mov         dl,byte [di]
            xor         dh,dh
            push        dx
            mov         dx,L$450
            push        dx
            add         ax,word [bx]
            push        ax
            call        esprintf_
            add         sp,6
            add         word [bx],ax
L$2:
            mov         sp,bp
            pop         bp
            pop         di
            pop         si
            ret         

get_bytes_:
    push        si
    push        di
    push        bp
    mov         bp,sp
    sub         sp,6
    mov         di,ax
    mov         word [-4+bp],dx
    mov         word [-6+bp],bx
    mov         word [-2+bp],cx
    xor         si,si
L$3:
    cmp         si,word[ 8+bp]
    jge         L$4
    mov         dx,word [-4+bp]
    add         dx,si
    mov         cx,word [-2+bp]
    mov         bx,word [-6+bp]
    mov         ax,di
    call        get_byte_
    inc         si
    jmp         L$3
L$4:
    mov         sp,bp
    pop         bp
    pop         di
    pop         si
    ret         2

		align 2, db 0
L$5:
    DW  L$16
    DW  L$18
    DW  L$7
    DW  L$7
    DW  L$7
    DW  L$7
    DW  L$7
    DW  L$7
    DW  L$8
    DW  L$18
    DW  L$11
    DW  L$15
    DW  L$18
    DW  L$18
    DW  L$18
    DW  L$18
    DW  L$18
    DW  L$18
    DW  L$18
    DW  L$18
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
    DW  L$19
L$6:
    DW  L$26
    DW  L$62
    DW  L$29
    DW  L$30
    DW  L$31
    DW  L$35
    DW  L$35
    DW  L$33
    DW  L$33
    DW  L$36
    DW  L$39
    DW  L$40
    DW  L$62
    DW  L$62
    DW  L$62
    DW  L$43
    DW  L$45
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$46
    DW  L$49
    DW  L$49
    DW  L$49
    DW  L$49
    DW  L$49
    DW  L$49
    DW  L$49
    DW  L$49
    DW  L$62
    DW  L$62
    DW  L$62
    DW  L$62
    DW  L$62
    DW  L$62
    DW  L$50
    DW  L$51
    DW  L$52
    DW  L$50
    DW  L$53
    DW  L$54
    DW  L$50
    DW  L$62
    DW  L$55
    DW  L$55
    DW  L$62
    DW  L$58
    DW  L$52
    DW  L$59
    DW  L$60
    DW  L$61
disasm_:
    push        cx
    push        si
    push        di
    push        bp
    mov         bp,sp
    sub         sp,3aH
    push        dx
    push        bx
    xor         di,di
    mov         word [-1aH+bp],di
    mov         word [-12H+bp],di
    mov         word [-0eH+bp],di
    mov         word [-18H+bp],ax
    mov         word [-10H+bp],_opcode1
    mov         word [-6+bp],di
    mov         word [-8+bp],di
    jmp         L$14
L$7:
    mov         al,byte [si]
    xor         ah,ah
    mov         bx,ax
    shl         bx,1
    push        word [_seg_regs-4+bx]
    mov         ax,L$451
    push        ax
    mov         ax,word [-3cH+bp]
    add         ax,di
    push        ax
    call        esprintf_
    add         sp,6
    jmp         L$13
L$8:
    cmp         word [-8+bp],0
    jne         L$9
    mov         ax,1
    jmp         L$10
L$9:
    xor         ax,ax
L$10:
    mov         word [-8+bp],ax
    jmp         L$14
L$11:
    mov         dx,L$452
L$12:
    push        dx
    push        ax
    call        esprintf_
    add         sp,4
L$13:
    add         di,ax
L$14:
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-4+bp]
    lea         ax,[-18H+bp]
    call        get_byte_
    mov         al,byte [-4+bp]
    xor         ah,ah
    mov         cl,3
    shl         ax,cl
    mov         si,word [-10H+bp]
    add         si,ax
    test        byte[ 7+si],80H
    je          L$20
    mov         al,byte [si]
    cmp         al,25H
    ja          L$18
    xor         ah,ah
    mov         bx,ax
    shl         bx,1
    mov         ax,word [-3cH+bp]
    add         ax,di
    jmp         word [cs:L$5+bx]
L$15:
    mov         dx,L$453
    jmp         L$12
L$16:
    mov         ax,L$454
L$17:
    push        ax
    push        word [-3cH+bp]
    call        esprintf_
    add         sp,4
    jmp         L$63
L$18:
    mov         ax,L$455
    jmp         L$17
L$19:
    mov         word [-12H+bp],1
L$20:
    test        byte[ 7+si],10H
    je          L$21
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-2+bp]
    lea         ax,[-18H+bp]
    call        get_byte_
    cmp         word [-12H+bp],0
    je          L$21
    mov         al,byte [si]
    xor         ah,ah
    mov         cl,6
    shl         ax,cl
    sub         ax,500H
    mov         si,_opcodeg
    add         si,ax
    mov         al,byte [-2+bp]
    xor         ah,ah
    mov         cl,3
    sar         ax,cl
    xor         ah,ah
    and         al,7
    shl         ax,cl
    add         si,ax
L$21:
    test        byte[ 7+si],40H
    je          L$22
    cmp         word [-8+bp],0
    je          L$22
    mov         word [-0eH+bp],1
L$22:
    mov         al,byte [si]
    xor         ah,ah
    mov         bx,ax
    add         bx,word [-0eH+bp]
    shl         bx,1
    push        word [_opnames+bx]
    mov         ax,L$456
    push        ax
    mov         ax,word [-3cH+bp]
    add         ax,di
    push        ax
    call        esprintf_
    add         sp,6
    add         di,ax
L$23:
    mov         bx,word [-3cH+bp]
    add         bx,di
    cmp         di,7
    jge         L$24
    mov         byte [bx],20H
    inc         di
    jmp         L$23
L$24:
    mov         byte [bx],0
    lea         bx,[2+si]
    mov         word [-0aH+bp],bx
    mov         word [-0cH+bp],0
L$25:
    mov         al,byte[ 1+si]
    xor         ah,ah
    cmp         ax,word [-0cH+bp]
    jle         L$32
    mov         word [-16H+bp],0
    mov         word [-14H+bp],0
    mov         bx,word [-0aH+bp]
    mov         al,byte [bx]
    dec         al
    cmp         al,3dH
    ja          L$34
    mov         bx,ax
    shl         bx,1
    jmp         word [cs:L$6+bx]
L$26:
    mov         ax,word [-6+bp]
    shl         ax,1
    inc         ax
    inc         ax
L$27:
    push        ax
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-16H+bp]
    lea         ax,[-18H+bp]
    call        get_bytes_
L$28:
    push        word [-16H+bp]
    mov         ax,L$457
    jmp         L$48
L$29:
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-16H+bp]
    lea         ax,[-18H+bp]
    call        get_byte_
    jmp         L$28
L$30:
    mov         ax,word [-8+bp]
    shl         ax,1
    inc         ax
    inc         ax
    push        ax
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-16H+bp]
    lea         ax,[-18H+bp]
    call        get_bytes_
    push        word [-16H+bp]
    jmp         L$38
L$31:
    mov         ax,2
    jmp         L$27
L$32:
    jmp         L$63
L$33:
    mov         bx,word [-6+bp]
    shl         bx,1
    push        word [_dssi_regs+bx]
    mov         ax,L$459
    jmp         L$48
L$34:
    jmp         L$62
L$35:
    mov         bx,word [-6+bp]
    shl         bx,1
    push        word [_esdi_regs+bx]
    mov         ax,L$460
    jmp         L$48
L$36:
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-16H+bp]
    lea         ax,[-18H+bp]
    call        get_byte_
    mov         al,byte [-16H+bp]
    xor         ah,ah
    add         ax,word [-18H+bp]
L$37:
    push        ax
L$38:
    mov         ax,L$458
    jmp         L$48
L$39:
    mov         ax,word [-8+bp]
    shl         ax,1
    inc         ax
    inc         ax
    push        ax
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-16H+bp]
    lea         ax,[-18H+bp]
    call        get_bytes_
    mov         ax,word [-18H+bp]
    add         ax,word [-16H+bp]
    jmp         L$37
L$40:
    mov         ax,word [-8+bp]
    shl         ax,1
    inc         ax
    inc         ax
    push        ax
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-16H+bp]
    lea         ax,[-18H+bp]
    call        get_bytes_
    mov         ax,2
    push        ax
    lea         cx,[-1aH+bp]
    mov         bx,word [-3eH+bp]
    lea         dx,[-14H+bp]
    lea         ax,[-18H+bp]
    call        get_bytes_
    push        word [-16H+bp]
    push        word [-14H+bp]
    mov         ax,L$461
    push        ax
    lea         ax,[-3aH+bp]
    push        ax
    call        esprintf_
    add         sp,8
L$41:
    lea         ax,[-3aH+bp]
    push        ax
    mov         ax,L$463
    push        ax
    mov         ax,word [-3cH+bp]
    add         ax,di
    push        ax
    call        esprintf_
    add         sp,6
    add         di,ax
    mov         al,byte[ 1+si]
    xor         ah,ah
    dec         ax
    cmp         ax,word [-0cH+bp]
    jle         L$42
    mov         ax,L$465
    push        ax
    mov         ax,word [-3cH+bp]
    add         ax,di
    push        ax
    call        esprintf_
    add         sp,4
    add         di,ax
L$42:
    inc         word [-0cH+bp]
    inc         word [-0aH+bp]
    jmp         L$25
L$43:
    mov         ax,1
L$44:
    push        ax
    mov         ax,L$462
    jmp         L$48
L$45:
    mov         ax,3
    jmp         L$44
L$46:
    mov         bx,word [-0aH+bp]
    mov         al,byte [bx]
    xor         ah,ah
    mov         bx,ax
    shl         bx,1
    push        word [_direct_regs-24H+bx]
L$47:
    mov         ax,L$463
L$48:
    push        ax
    lea         ax,[-3aH+bp]
    push        ax
    call        esprintf_
    add         sp,6
    jmp         L$41
L$49:
    mov         bx,word [-0aH+bp]
    mov         al,byte [bx]
    xor         ah,ah
    mov         bx,ax
    shl         bx,1
    push        word [_ea_regs-32H+bx]
    jmp         L$47
L$50:
    lea         ax,[-3aH+bp]
    push        ax
    lea         ax,[-1aH+bp]
    push        ax
    push        word [-3eH+bp]
    mov         al,byte [-2+bp]
    xor         ah,ah
    lea         cx,[-18H+bp]
    mov         bx,ax
    xor         dx,dx
    jmp         L$57
L$51:
    lea         ax,[-3aH+bp]
    push        ax
    lea         ax,[-1aH+bp]
    push        ax
    push        word [-3eH+bp]
    mov         al,byte [-2+bp]
    xor         ah,ah
    mov         dx,word [-8+bp]
    inc         dx
    lea         cx,[-18H+bp]
    mov         bx,ax
    jmp         L$57
L$52:
    lea         ax,[-3aH+bp]
    push        ax
    lea         ax,[-1aH+bp]
    push        ax
    push        word [-3eH+bp]
    mov         al,byte [-2+bp]
    xor         ah,ah
    lea         cx,[-18H+bp]
    mov         bx,ax
    mov         dx,1
    jmp         L$57
L$53:
    mov         al,byte [-2+bp]
    mov         cl,3
    mov         bx,ax
    sar         bx,cl
    xor         bh,bh
    and         bl,7
    shl         bx,1
    push        word [_ea_regs+bx]
    jmp         L$47
L$54:
    mov         al,byte [-2+bp]
    mov         cl,3
    mov         bx,ax
    sar         bx,cl
    xor         bh,bh
    and         bl,7
    shl         bx,1
    push        word [_ea_regs+10H+bx]
    jmp         L$47
L$55:
    lea         ax,[-3aH+bp]
    push        ax
    lea         ax,[-1aH+bp]
    push        ax
    push        word [-3eH+bp]
    mov         al,byte [-2+bp]
    xor         ah,ah
    lea         cx,[-18H+bp]
    mov         bx,ax
L$56:
    mov         dx,2
L$57:
    mov         ax,word [-6+bp]
    call        dec_modrm_
    jmp         L$41
L$58:
    lea         ax,[-3aH+bp]
    push        ax
    lea         ax,[-1aH+bp]
    push        ax
    push        word [-3eH+bp]
    mov         bl,byte [-2+bp]
    xor         bh,bh
    lea         cx,[-18H+bp]
    jmp         L$56
L$59:
    mov         al,byte [-2+bp]
    mov         cl,3
    mov         bx,ax
    sar         bx,cl
    xor         bh,bh
    and         bl,7
    shl         bx,1
    push        word [_seg_regs+bx]
    jmp         L$47
L$60:
    mov         al,byte [-2+bp]
    mov         cl,3
    mov         bx,ax
    sar         bx,cl
    xor         bh,bh
    and         bl,7
    shl         bx,1
    push        word [_cntrl_regs+bx]
    jmp         L$47
L$61:
    mov         al,byte [-2+bp]
    mov         cl,3
    mov         bx,ax
    sar         bx,cl
    xor         bh,bh
    and         bl,7
    shl         bx,1
    push        word [_debug_regs+bx]
    jmp         L$47
L$62:
    mov         bx,word [-0aH+bp]
    mov         al,byte [bx]
    xor         ah,ah
    push        ax
    mov         ax,L$464
    push        ax
    add         di,word [-3cH+bp]
    push        di
    call        esprintf_
    add         sp,6
L$63:
    mov         cx,word [-18H+bp]
    mov         ax,cx
L$64:
    mov         sp,bp
    pop         bp
    pop         di
    pop         si
    pop         cx
    ret      
       
dec_modrm_:
    push        si
    push        di
    push        bp
    mov         bp,sp
    sub         sp,22H
    PUSH        DX
    mov         si,cx
    mov         di,word[ 0aH+bp]
    mov         al,bl
    xor         ah,ah
    mov         cl,6
    sar         ax,cl
    xor         ah,ah
    mov         dl,al
    and         dl,3
    mov         dh,bl
    and         dh,7
    mov         word [-2+bp],0
    mov         al,dh
    mov         bx,ax
    shl         bx,1
    push        word [_ea_modes+bx]
    mov         ax,L$466
    push        ax
    lea         ax,[-22H+bp]
    push        ax
    call        esprintf_
    add         sp,6
    cmp         dl,3
    jne         L$67
    
    mov         cl,4
    mov         ax,word [-24H+bp]
    shl         ax,cl
    add         bx,ax
  
    push        word [_ea_regs+bx]
L$65:
    mov         ax,L$463
L$66:
    push        ax
    push        word[ 0cH+bp]
    call        esprintf_
    add         sp,6
    jmp         L$71
L$67:
    test        dl,dl
    jne         L$69
    cmp         dh,cl
    jne         L$68
    mov         cx,di
    mov         bx,word[ 8+bp]
    lea         dx,[-2+bp]
    mov         ax,si
    call        get_byte_
    mov         cx,di
    mov         bx,word[ 8+bp]
    lea         dx,[-1+bp]
    mov         ax,si
    call        get_byte_
    push        word [-2+bp]
    mov         ax,L$467
    jmp         L$66
L$68:
    lea         ax,[-22H+bp]
    push        ax
    jmp         L$65
L$69:
    cmp         dl,1
    jne         L$72
    mov         cx,di
    mov         bx,word[ 8+bp]
    lea         dx,[-2+bp]
L$70:
    mov         ax,si
    call        get_byte_
    push        word [-2+bp]
    lea         ax,[-22H+bp]
    push        ax
    mov         ax,L$468
    push        ax
    push        word[ 0cH+bp]
    call        esprintf_
    add         sp,8
L$71:
    xor         ax,ax
    jmp         L$74
L$72:
    cmp         dl,2
    jne         L$73
    mov         cx,di
    mov         bx,word[ 8+bp]
    lea         dx,[-2+bp]
    mov         ax,si
    call        get_byte_
    mov         cx,di
    mov         bx,word[ 8+bp]
    lea         dx,[-1+bp]
    jmp         L$70
L$73:
    mov         ax,0ffffH
L$74:
    mov         sp,bp
    pop         bp
    pop         di
    pop         si
    ret         6
printchar_:
    push        bx
    push        si
    mov         bx,ax
    mov         ax,dx
    test        bx,bx
    je          L$75
    mov         si,word [bx]
    mov         byte [si],dl
    inc         word [bx]
    pop         si
    pop         bx
    ret         
L$75:
    call        TXCHAR
    pop         si
    pop         bx
    ret         
prints_:
    push        si
    push        di
    push        bp
    mov         bp,sp
    push        ax
    push        ax
    mov         si,dx
    mov         dx,cx
    xor         cx,cx
    mov         word [-2+bp],20H
    test        bx,bx
    jle         L$80
    xor         ax,ax
    mov         di,si
L$76:
    cmp         byte [di],0
    je          L$77
    inc         ax
    inc         di
    jmp         L$76
L$77:
    cmp         ax,bx
    jl          L$78
    xor         bx,bx
    jmp         L$79
L$78:
    sub         bx,ax
L$79:
    test        dl,2
    je          L$80
    mov         word [-2+bp],30H
L$80:
    test        dl,1
    jne         L$82
L$81:
    test        bx,bx
    jle         L$82
    mov         dx,word [-2+bp]
    mov         ax,word [-4+bp]
    call        printchar_
    inc         cx
    dec         bx
    jmp         L$81
L$82:
    cmp         byte [si],0
    je          L$83
    mov         al,byte [si]
    xor         ah,ah
    mov         dx,ax
    mov         ax,word [-4+bp]
    call        printchar_
    inc         cx
    inc         si
    jmp         L$82
L$83:
    test        bx,bx
    jle         L$84
    mov         dx,word [-2+bp]
    mov         ax,word [-4+bp]
    call        printchar_
    inc         cx
    dec         bx
    jmp         L$83
L$84:
    mov         ax,cx
    jmp         L$2
printi_:
    push        si
    push        di
    push        bp
    mov         bp,sp
    sub         sp,12H
    mov         di,ax
    mov         word [-6+bp],bx
    mov         word [-4+bp],0
    mov         word [-2+bp],0
    mov         bx,dx
    test        dx,dx
    jne         L$85
    mov         word [-12H+bp],30H
    mov         cx,word[ 0aH+bp]
    mov         bx,word[ 8+bp]
    lea         dx,[-12H+bp]
    call        prints_
    jmp         L$74
L$85:
    test        cx,cx
    je          L$86
    cmp         word [-6+bp],0aH
    jne         L$86
    test        dx,dx
    jge         L$86
    mov         word [-4+bp],1
    neg         bx
L$86:
    lea         si,[-7+bp]
    mov         byte [-7+bp],0
L$87:
    test        bx,bx
    je          L$89
    mov         ax,bx
    xor         dx,dx
    div         word [-6+bp]
    cmp         dx,0aH
    jl          L$88
    mov         ax,word[ 0cH+bp]
    sub         ax,3aH
    add         dx,ax
L$88:
    mov         al,dl
    add         al,30H
    dec         si
    mov         byte [si],al
    mov         ax,bx
    xor         dx,dx
    div         word [-6+bp]
    mov         bx,ax
    jmp         L$87
L$89:
    cmp         word [-4+bp],0
    je          L$91
    cmp         word[ 8+bp],0
    je          L$90
    test        byte[ 0aH+bp],2
    je          L$90
    mov         dx,2dH
    mov         ax,di
    call        printchar_
    inc         word [-2+bp]
    dec         word[ 8+bp]
    jmp         L$91
L$90:
    dec         si
    mov         byte [si],2dH
L$91:
    mov         cx,word[ 0aH+bp]
    mov         bx,word[ 8+bp]
    mov         dx,si
    mov         ax,di
    call        prints_
    add         ax,word [-2+bp]
    jmp         L$74
print_:
    push        cx
    push        si
    push        di
    push        bp
    mov         bp,sp
    push        ax
    push        ax
    push        ax
    mov         si,dx
    mov         di,bx
    mov         word [-2+bp],0
L$92:
    cmp         byte [si],0
    je          L$96
    cmp         byte [si],25H
    jne         L$97
    xor         cx,cx
    xor         dx,dx
    inc         si
    cmp         byte [si],0
    je          L$96
    cmp         byte [si],25H
    je          L$97
    cmp         byte [si],2dH
    jne         L$93
    mov         cx,1
    add         si,cx
L$93:
    cmp         byte [si],30H
    jne         L$94
    or          cl,2
    inc         si
    jmp         L$93
L$94:
    cmp         byte [si],30H
    jb          L$95
    cmp         byte [si],39H
    ja          L$95
    mov         ax,dx
    mov         dx,0aH
    imul        dx
    mov         dx,ax
    mov         bl,byte [si]
    xor         bh,bh
    sub         bx,30H
    add         dx,bx
    inc         si
    jmp         L$94
L$95:
    cmp         byte [si],73H
    jne         L$101
    add         word [di],2
    mov         bx,word [di]
    mov         ax,word [-2+bx]
    mov         bx,dx
    test        ax,ax
    je          L$98
    mov         dx,ax
    jmp         L$99
L$96:
    jmp         L$111
L$97:
    jmp         L$109
L$98:
    mov         dx,L$469
L$99:
    mov         ax,word [-6+bp]
    call        prints_
L$100:
    add         word [-2+bp],ax
    jmp         L$110
L$101:
    cmp         byte [si],64H
    jne         L$104
    mov         ax,61H
    push        ax
    push        cx
    push        dx
    add         word [di],2
    mov         bx,word [di]
    mov         dx,word [-2+bx]
    mov         cx,1
L$102:
    mov         bx,0aH
L$103:
    mov         ax,word [-6+bp]
    call        printi_
    jmp         L$100
L$104:
    cmp         byte [si],78H
    jne         L$106
    mov         ax,61H
L$105:
    push        ax
    push        cx
    push        dx
    add         word [di],2
    mov         bx,word [di]
    mov         dx,word [-2+bx]
    xor         cx,cx
    mov         bx,10H
    jmp         L$103
L$106:
    cmp         byte [si],58H
    jne         L$107
    mov         ax,41H
    jmp         L$105
L$107:
    cmp         byte [si],75H
    jne         L$108
    mov         ax,61H
    push        ax
    push        cx
    push        dx
    add         word [di],2
    mov         bx,word [di]
    mov         dx,word [-2+bx]
    xor         cx,cx
    jmp         L$102
L$108:
    cmp         byte [si],63H
    jne         L$110
    add         word [di],2
    mov         bx,word [di]
    mov         al,byte [-2+bx]
    mov         byte [-4+bp],al
    mov         byte [-3+bp],0
    mov         bx,dx
    lea         dx,[-4+bp]
    jmp         L$99
L$109:
    mov         dl,byte [si]
    xor         dh,dh
    mov         ax,word [-6+bp]
    call        printchar_
    inc         word [-2+bp]
L$110:
    inc         si
    jmp         L$92
L$111:
    cmp         word [-6+bp],0
    je          L$112
    mov         bx,word [-6+bp]
    mov         bx,word [bx]
    mov         byte [bx],0
L$112:
    mov         word [di],0
    mov         ax,word [-2+bp]
    jmp         L$64
esprintf_:
    push        bx
    push        dx
    push        bp
    mov         bp,sp
    push        ax
    lea         ax,[0cH+bp]
    mov         word [-2+bp],ax
    lea         bx,[-2+bp]
    mov         dx,word[ 0aH+bp]
    lea         ax,[8+bp]
    call        print_
    mov         sp,bp
    pop         bp
    pop         dx
    pop         bx
    ret 

;----------------------------------------------------------------------
; Display Help Menu
;----------------------------------------------------------------------
DISPHELP:   MOV     SI,HELP_MESS         ; -> SI
            CALL    PUTS                        ; String pointed to by DS:[SI]
EXITDH:     JMP     CMD                         ; Next Command

;----------------------------------------------------------------------
; Quite Monitor
;----------------------------------------------------------------------
EXITMON:    MOV     AH,4Ch                      ; Exit MON88
            INT     21h

;======================================================================
; Monitor routines
;======================================================================
;----------------------------------------------------------------------
; Return String Length in AL
; String pointed to by DS:[SI]
;----------------------------------------------------------------------
STRLEN:     PUSH    SI
            MOV     AH,-1
            CLD 
NEXTSL:     INC     AH
            LODSB                               ; AL=DS:[SI++]
            OR      AL,AL                       ; Zero?
            JNZ     NEXTSL                      ; No, continue
            MOV     AL,AH                       ; Return Result in AX
            XOR     AH,AH                       
            POP     SI
            RET

;----------------------------------------------------------------------
; Write zero terminated string to CONOUT
; String pointed to by DS:[SI]
;----------------------------------------------------------------------
PUTS:       PUSH    SI
            PUSH    AX
            CLD 
PRINT:      LODSB                               ; AL=DS:[SI++]
            OR      AL,AL                       ; Zero?
            JZ      PRINT_X                     ; then exit
            CALL    TXCHAR                          
            JMP     PRINT                       ; Next Character
PRINT_X:    POP     AX
            POP     SI
            RET

;----------------------------------------------------------------------
; Write string to CONOUT, length in CL
; String pointed to by DS:[SI]
;----------------------------------------------------------------------
PUTSF:      PUSH    SI
            PUSH    CX          
            PUSH    AX
            CLD 
            XOR     CH,CH
PRTF:       LODSB                               ; AL=DS:[SI++]
            CALL    TXCHAR                          
            LOOP    PRTF
            POP     AX
            POP     CX
            POP     SI
            RET

;----------------------------------------------------------------------
; Write newline
;----------------------------------------------------------------------
NEWLINE:    PUSH    AX
            MOV     AL,CR
            CALL    TXCHAR
            MOV     AL,LF
            CALL    TXCHAR
            POP     AX
            RET
;----------------------------------------------------------------------
; Get Address range into BX, DX 
;----------------------------------------------------------------------
GETRANGE:   PUSH    AX
            CALL    GETHEX4
            MOV     BX,AX
            MOV     AL,'-'
            CALL    TXCHAR
            CALL    GETHEX4
            MOV     DX,AX
            POP     AX
            RET

;----------------------------------------------------------------------
; Get Hex4,2,1 Into AX, AL, AL  
;----------------------------------------------------------------------
GETHEX4:    PUSH    BX
            CALL    GETHEX2                     ; Get Hex Character in AX
            MOV     BL,AL
            CALL    GETHEX2
            MOV     AH,BL
            POP     BX
            RET

GETHEX2:    PUSH    BX
            CALL    GETHEX1                      ; Get Hex character in AL
            MOV     BL,AL
            SHL     BL,1
            SHL     BL,1
            SHL     BL,1
            SHL     BL,1
            CALL    GETHEX1
            OR      AL,BL
            POP     BX
            RET

GETHEX1:    CALL    RXCHAR                      ; Get Hex character in AL
            CMP     AL,ESC
            JNE     OKCHAR
            JMP     CMD                         ; Abort if ESC is pressed
OKCHAR:     CALL    TO_UPPER
            CMP     AL,39h                      ; 0-9?
            JLE     CONVDEC                     ; yes, subtract 30
            SUB     AL,07h                      ; A-F subtract 39
CONVDEC:    SUB     AL,30h
            RET

;----------------------------------------------------------------------
; Display AX/AL in HEX
;----------------------------------------------------------------------
PUTHEX4:    XCHG    AL,AH                       ; Write AX in hex
            CALL    PUTHEX2
            XCHG    AL,AH
            CALL    PUTHEX2
            RET

PUTHEX2:    PUSH    AX                          ; Save the working register
            SHR     AL,1
            SHR     AL,1
            SHR     AL,1
            SHR     AL,1
            CALL    PUTHEX1                     ; Output it
            POP     AX                          ; Get the LSD
            CALL    PUTHEX1                     ; Output
            RET

PUTHEX1:    PUSH    AX                          ; Save the working register
            AND     AL, 0FH                     ; Mask off any unused bits
            CMP     AL, 0AH                     ; Test for alpha or numeric
            JL      NUMERIC                     ; Take the branch if numeric
            ADD     AL, 7                       ; Add the adjustment for hex alpha
NUMERIC:    ADD     AL, '0'                     ; Add the numeric bias
            CALL    TXCHAR                      ; Send to the console
            POP     AX
            RET

;----------------------------------------------------------------------
; Convert HEX to BCD
; 3Bh->59
;----------------------------------------------------------------------
HEX2BCD:    PUSH    CX
            XOR     AH,AH
            MOV     CL,0Ah
            DIV     CL
            SHL     AL,1
            SHL     AL,1
            SHL     AL,1
            SHL     AL,1
            OR      AL,AH
            POP     CX      
            RET
                
;----------------------------------------------------------------------
; Convert to Upper Case
; if (c >= 'a' && c <= 'z') c -= 32;
;----------------------------------------------------------------------
TO_UPPER:   CMP     AL,'a'
            JGE     CHECKZ
            RET
CHECKZ:     CMP     AL,'z'
            JLE     SUB32
            RET
SUB32:      SUB     AL,32
            RET

;----------------------------------------------------------------------
; Transmit character in AL
;----------------------------------------------------------------------
;TXCHAR:     PUSH    DX
;            PUSH    AX                          ; Character in AL
;            MOV     DX,COMPORT+STATUS           
;WAITTX:     IN      AL,DX                       ; read status
;            AND     AL,TX_EMPTY                 ; Transmit Register Empty?
;            JZ      WAITTX                      ; no, wait
;            MOV     DX,COMPORT+DATAREG          ; point to data port
;            POP     AX
;            OUT     DX,AL
;            POP     DX
;            RET
TXCHAR:     PUSH    DX
            PUSH    AX                          ; Character in AL
            MOV     DX,LSR                      ; Read Line Status Register          
WAITTX:     IN      AL,DX                        
            AND     AL,THRE                     ; Transmit Holding Register Empty?
            JZ      WAITTX                      ; no, wait
            MOV     DX,THR                      ; point to data port
            POP     AX
            OUT     DX,AL
            POP     DX
            RET


;----------------------------------------------------------------------
; Receive character in AL, blocking
; AL Changed
;----------------------------------------------------------------------
;RXCHAR:     PUSH    DX
;            MOV     DX,COMPORT+STATUS
;WAITRX:     IN      AL,DX
;            AND     AL,RX_AVAIL
;            JZ      WAITRX                      ; blocking
;            MOV     DX,COMPORT+DATAREG    
;            IN      AL,DX                       ; return result in al
;            CALL    TXCHAR                      ; Echo back
;            POP     DX
;            RET
RXCHAR:     PUSH    DX
            MOV     DX,LSR
WAITRX:     IN      AL,DX
            AND     AL,DR                       ; Character pending?
            JZ      WAITRX                      ; No, then wait
            MOV     DX,RBR    
            IN      AL,DX                       ; return result in al
            CALL    TXCHAR                      ; Echo back
            POP     DX
            RET

;----------------------------------------------------------------------
; Receive character in AL, blocking
; AL Changed
; No Echo
;----------------------------------------------------------------------
;RXCHARNE:   PUSH    DX
;            MOV     DX,COMPORT+STATUS
;WAITRXNE:   IN      AL,DX
;            AND     AL,RX_AVAIL
;            JZ      WAITRXNE                    ; blocking
;            MOV     DX,COMPORT+DATAREG    
;            IN      AL,DX                       ; return result in al
;            POP     DX
;            RET
RXCHARNE:   PUSH    DX
            MOV     DX,LSR
WAITRXNE:   IN      AL,DX
            AND     AL,DR
            JZ      WAITRXNE                    ; blocking
            MOV     DX,RBR    
            IN      AL,DX                       ; return result in al
            POP     DX
            RET
            
;======================================================================
; Monitor Interrupt Handlers
;======================================================================  
;----------------------------------------------------------------------
; Breakpoint/Trace Interrupt Handler
; Restore All instructions
; Display Breakpoint Number
; Update & Display Registers
; Return to monitor                
;----------------------------------------------------------------------
INT1_3:     PUSH    BP
            MOV     BP,SP                       ; BP+2=IP, BP+4=CS, BP+6=Flags
            PUSH    SS                          
            PUSH    ES
            PUSH    DS
            PUSH    DI
            PUSH    SI
            PUSH    BP                          ; Note this is the wrong value
            PUSH    SP
            PUSH    DX
            PUSH    CX
            PUSH    BX
            PUSH    AX                           

            MOV     AX,CS                       ; Restore Monitor's Data segment
            MOV     DS,AX                       
                        
            MOV     AX,[BP+4]                ; Get user CS
            MOV     ES,AX                       ; Used for restoring bp replaced opcode
            MOV     [UCS],AX                    ; Save User CS            
           
            MOV     AX,[BP+2]                ; Save User IP
            MOV     [UIP],AX
                                   
            MOV     DI,SP                       ; SS:SP=AX
            MOV     BX,UAX               ; Update User registers, DI=pointing to AX
            MOV     CX,11
NEXTUREG:   MOV     AX,[SS:DI]                  ; Get register
            MOV     [BX],AX                     ; Write it to user reg
            ADD     BX,2
            ADD     DI,2
            LOOP    NEXTUREG
            
            MOV     AX,BP                       ; Save User SP
            ADD     AX,8                        
            MOV     [USP],AX

            MOV     AX,[BP]
            MOV     [UBP],AX                    ; Restore real BP value
            
            MOV     AX,[BP+6]                ; Save Flags            
            MOV     [UFL],AX
            AND     word [UFL],0FEFFh                ; Clear TF
            TEST    AX,0100h                    ; Check If Trace flag set then
            JZ      CONTBPC                     ; No, check which bp triggered it
                        
            JMP     EXITINT3	; Exit, Display regs, Cmd prompt
            
CONTBPC:    DEC     word [UIP]                       ; No, IP-1 and save
                                 
            MOV     SI,BREAKP_MESS       ; Display "***** BreakPoint # *****

            MOV     BX,BPTAB             ; Check which breakpoint triggered
            MOV     CX,8                        ; and restore opcode
INTNEXTBP:  MOV     AX,8
            SUB     AL,CL

            TEST    BYTE [BX+3],1               ; Check enable/disable flag
            JZ      INT3RESBP
                            
            MOV     DI,[BX]                     ; Get Breakpoint Address
            CMP     [UIP],DI
            JNE     INT3RES
            
            ADD     AL, '0'                     ; Add the numeric bias
            MOV     [SI+18],AL                  ; Save number
           
INT3RES:    MOV     AL,BYTE [BX+2]              ; Get original Opcode
            MOV     [ES:DI],AL                  ; Write it back

INT3RESBP:  ADD     BX,4                        ; Next entry
            LOOP    INTNEXTBP

            CALL    PUTS                        ; Write BP Number message                 
                       
EXITINT3:   MOV     AX,CS                       ; Restore Monitor settings
;            MOV     DS,AX
            MOV     SS,AX
            MOV     SP, TOS			; Restore Monitor Stack pointer
            MOV     AX,BASE_SEGMENT             ; Restore Base Pointer
            MOV     ES,AX
            
            JMP     DISPREG                     ; Jump to Display Registers
                
;======================================================================
; BIOS Services
;======================================================================

;----------------------------------------------------------------------
; Interrupt 10H, video function                                           
; Service   0E   Teletype Output                  
; Input     AL   Character, BL and BH are ignored                                
; Output                                                  
; Changed                                               
;----------------------------------------------------------------------
INT10:      CMP     AH,0Eh
            JNE     ISR10_X

            CALL    TXCHAR                      ; Transmit character
            JMP     ISR10_RET
            
;----------------------------------------------------------------------                                         
; Service Unkown service, display message int and ah value, return to monitor 
;----------------------------------------------------------------------
ISR10_X:    MOV     AL,10h
            CALL    DISPSERI                    ; Display Int and service number
            JMP     INITMON                     ; Jump back to monitor

ISR10_RET:  IRET


;----------------------------------------------------------------------
; Interrupt 16H, I/O function                                           
; Service   00   Wait for keystroke                  
; Input                                     
; Output    AL   Character, AH=ScanCode=0                                              
; Changed   AX                                            
;----------------------------------------------------------------------
INT16:      PUSH    DX                          
            PUSH    BP
            MOV     BP,SP
                                                
ISR16_00:   CMP     AH,00h
            JNE     ISR16_01

            CALL    RXCHAR
            XOR     AH,AH
            
            JMP     ISR16_RET

;----------------------------------------------------------------------
; Interrupt 16H, I/O function                                           
; Service   01   Check for keystroke (kbhit)                  
; Input                                     
; Output    AL   Character, AH=ScanCode=0 ZF=0 when keystoke available                                              
; Changed   AX                                            
;----------------------------------------------------------------------
ISR16_01:   CMP     AH,01h
            JNE     ISR16_X 
                   
            XOR     AH,AH                       ; Clear ScanCode            
            OR      WORD [BP+8],0040h        ; SET ZF in stack stored flag
            
;            MOV     DX,COMPORT+STATUS
;            IN      AL,DX                       ; Get Status
;            AND     AL,RX_AVAIL                 
;            JZ      ISR16_RET                   ; No keystoke
;            
;            MOV     DX,COMPORT+DATAREG    
;            IN      AL,DX                       ; return result in al

            MOV     DX,LSR
            IN      AL,DX                       ; Get Status
            AND     AL,DR                 
            JZ      ISR16_RET                   ; No keystoke
            
            MOV     DX,RBR    
            IN      AL,DX                       ; return result in al

            AND     WORD [BP+8],0FFBFh       ; Clear ZF in stack stored flag
            JMP     ISR16_RET
                    
;----------------------------------------------------------------------                                          
; Service Unkown service, display message int and ah value, return to monitor 
;----------------------------------------------------------------------
ISR16_X:    MOV     AL,16h
            CALL    DISPSERI                    ; Display Int and service number
            JMP     INITMON                     ; Jump back to monitor

ISR16_RET:  POP     BP
            POP     DX
            IRET
        

;----------------------------------------------------------------------
;  INT 1AH, timer function 
;  AX is not saved!
;        Addr    Function
;====    =========================================;
; 00     current second for real-time clock
; 02     current minute
; 04     current hour
; 07     current date of month
; 08     current month
; 09     current year  (final two digits; eg, 93)
; 0A     Status Register A - Read/Write except UIP
;----------------------------------------------------------------------
INT1A:      PUSH    DS
            PUSH    BP
            MOV     BP,SP
            
;----------------------------------------------------------------------
; Interrupt 1AH, Time function                                           
; Service   00   Get System Time in ticks                  
; Input                                     
; Output    CX:DX ticks since midnight                                                                                         
;----------------------------------------------------------------------
ISR1A_00:   CMP     AH,00h
            JNE     ISR1A_01
                       
            MOV     AX,04h                      ; Hours
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
            
            MOV     CX,65520                    ; 60*60*18.2
            MUL     CX                          ; DX:AX=result hours
            MOV     word [TEMP1],DX
            MOV     word [TEMP2],AX
                        
            MOV     AX,02h                      ; Minutes
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
            
            MOV     CX,1092
            MUL     CX                          ; DX:AX=result minutes
            ADD     word [TEMP2],AX                    ; TEMP2=AX+TEMP2
            ADC     word [TEMP1],DX                    ; TEMP1=DX+TEMP1+carry
                                                ; TEMP1:TEMP2 (hour+minutes)*18.2
            
            MOV     AL,00h                      ; Seconds
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
                                    
            MOV     CL,182
            MUL     CL                          ; AX seconds*182
            
            XOR     DX,DX
            MOV     CX,10
            DIV     CX                          ; AX=seconds*18.2 DX=remainder(ignored)
            
            XOR     DX,DX
            ADD     word [TEMP2],AX
            ADC     word [TEMP1],DX                    ; Add Carry
            MOV     CX,word [TEMP1]
            MOV     DX,word [TEMP2]
            
            JMP     ISR1A_RET	; exit

		align 2, db 0
TEMP1       DW      0
TEMP2       DW      0                           

;----------------------------------------------------------------------
; Interrupt 1AH, Time function                                           
; Service   01   Set System Time from ticks                  
; Input     CX:DX ticks since midnight                                
; Output                                                                                             
;----------------------------------------------------------------------
ISR1A_01:   CMP     AH,01h
            JNE     ISR1A_02

            PUSH    BX
            PUSH    CX
            PUSH    DX
            
            MOV     AL,0Ah      
            OUT     RTC_BASE,AL
ISR1A_01W:  IN      AL,RTC_DATA                 ; Check Update In Progress Flag
            AND     AL,80h
            JNZ     ISR1A_01W                   ; if so then wait
            
            MOV     AL,04h                      ; Hours
            OUT     RTC_BASE,AL
            
            MOV     BX,65520                    ; 60*60*18.2            
            PUSH    DX
            POP     AX
            PUSH    CX
            POP     DX                          ; DX:AX <-CX:DX
            
            DIV     BX                          ; DX:AX/65520-> AL=Hours,AH=0 DX=remainder
            OUT     RTC_DATA,AL
            
            MOV     AL,02h                      ; Minutes
            OUT     RTC_BASE,AL

            MOV     BX,1092
            PUSH    DX
            POP     AX
            XOR     DX,DX
            DIV     BX                          ; 00:DX/1092->AL=Minutes AH=0, DX=remainder
            OUT     RTC_DATA,AL
            
            MOV     AL,00h                      ; Seconds
            OUT     RTC_BASE,AL
            MOV     CX,10
            MOV     AX,DX
            MUL     CX
            MOV     BX,182                      ; 
            DIV     BX                          ; AL/BL-> AL=seconds
            OUT     RTC_DATA,AL

            POP     DX
            POP     CX
            POP     BX
            JMP     ISR1A_RET	; exit
            
            
;----------------------------------------------------------------------
; Interrupt 1AH, Time function                                           
; Service   02   Get RTC time                  
;   exit :  CF clear if successful, set on error ***NOT YET ADDED***
;           CH = hour (BCD)
;           CL = minutes (BCD)
;           DH = seconds (BCD)
;           DL = daylight savings flag  (!! NOT IMPLEMENTED !!)
;                (00h standard time, 01h daylight time)
;----------------------------------------------------------------------
ISR1A_02:   CMP     AH,02h
            JNE     ISR1A_03
            
            CALL    READRTC
            JMP     ISR1A_RET	; exit

READRTC:    MOV     AL,00h                      ; Seconds
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
            CALL    HEX2BCD
            MOV     DH,AL
            
            MOV     AL,02h                      ; Minutes
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
            CALL    HEX2BCD
            MOV     CL,AL
            
            MOV     AL,04h                      ; Hours
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
            CALL    HEX2BCD
            MOV     CH,AL
            
            XOR     DL,DL                       ; Set to standard time
            RET
            
;----------------------------------------------------------------------
; Int 1Ah function 03h - Set RTC time
;   entry:  AH = 03h
;           CH = hour (BCD)
;           CL = minutes (BCD)
;           DH = seconds (BCD)
;           DL = daylight savings flag (as above)
;   exit:   none
;----------------------------------------------------------------------
ISR1A_03:   CMP     AH,03h
            JNE     ISR1A_04
            
            MOV     AL,0Ah      
            OUT     RTC_BASE,AL
ISR1A_03W:  IN      AL,RTC_DATA                 ; Check Update In Progress Flag
            AND     AL,80h
            JNZ     ISR1A_03W                   ; if so then wait

            MOV     AL,00h                      ; Seconds
            OUT     RTC_BASE,AL
            MOV     AL,DH
            OUT     RTC_DATA,AL
            
            MOV     AL,02h                      ; Minutes
            OUT     RTC_BASE,AL
            MOV     AL,CL
            OUT     RTC_DATA,AL
            
            MOV     AL,04h                      ; Hours
            OUT     RTC_BASE,AL
            MOV     AL,CH
            OUT     RTC_DATA,AL
            
            JMP     ISR1A_RET
            
;----------------------------------------------------------------------
; Int 1Ah function 04h - Get RTC date
;   entry:  AH = 04h
;   exit:   CF clear if successful, set on error
;           CH = century (BCD)
;           CL = year (BCD)
;           DH = month (BCD)
;           DL = day (BCD)
;----------------------------------------------------------------------
ISR1A_04:   CMP     AH,04h
            JNE     ISR1A_05
            
            MOV     AL,07h                      ; Day
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
            CALL    HEX2BCD
            MOV     DL,AL
            
            MOV     AL,08h                      ; Month
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
            CALL    HEX2BCD
            MOV     DH,AL
            
            MOV     AL,09h                      ; Year
            OUT     RTC_BASE,AL
            IN      AL,RTC_DATA
            CALL    HEX2BCD
            MOV     CL,AL
            MOV     CH,20h          
            
            JMP     ISR1A_RET

;----------------------------------------------------------------------
; Int 1Ah function 05h - Set RTC date
;   entry:  AH = 05h
;           CH = century (BCD)
;           CL = year (BCD)
;           DH = month (BCD)
;           DL = day (BCD)
;   exit:   none        
;----------------------------------------------------------------------
ISR1A_05:   CMP     AH,05h
            JNE     ISR1A_X
            
            MOV     AL,0Ah      
            OUT     RTC_BASE,AL
ISR1A_05W:  IN      AL,RTC_DATA                 ; Check Update In Progress Flag
            AND     AL,80h
            JNZ     ISR1A_05W                   ; if so then wait

            MOV     AL,07h                      ; Day
            OUT     RTC_BASE,AL
            MOV     AL,DL
            OUT     RTC_DATA,AL
            
            MOV     AL,08h                      ; Month
            OUT     RTC_BASE,AL
            MOV     AL,DH
            OUT     RTC_DATA,AL
            
            MOV     AL,09h                      ; Year
            OUT     RTC_BASE,AL
            MOV     AL,CL
            OUT     RTC_DATA,AL
            
            JMP     ISR1A_RET
            
;----------------------------------------------------------------------
; Interrupt 1Ah                                           
; Service   xx   Unknown service, print message, jump to monitor 
;----------------------------------------------------------------------
ISR1A_X:    MOV     AL,1Ah
            CALL    DISPSERI                    ; Display Int and service number
            JMP     INITMON                     ; Jump back to monitor

ISR1A_RET:  AND     WORD [BP+8],0FFFEh       ; Clear Carry to indicate no error
            POP     BP
            POP     DS      
            IRET        

;----------------------------------------------------------------------
; INT 21H, basic I/O functions 
; AX REGISTER NOT SAVED                                   
;----------------------------------------------------------------------
INT21:      PUSH    DS                          ; DS used for service 25h
            PUSH    ES
            PUSH    SI

            STI                                 ; INT21 is reentrant!

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   01   get character from UART                  
; Input                                                   
; Output    AL   character read                           
; Changed   AX                                            
;----------------------------------------------------------------------
ISR21_1:    CMP     AH,01                           
            JNE     ISR21_2                         

            CALL    RXCHAR                      ; Return result in AL
            JMP     ISR21_RET	; return to caller

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   02   write character to UART                  
; Input     DL   character                                
; Output                                                  
; Changed   AX                                            
;----------------------------------------------------------------------
ISR21_2:    CMP     AH,02                           
            JNE     ISR21_8                         

            MOV     AL,DL
            CALL    TXCHAR
        
            JMP     ISR21_RET	; return to caller

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   08   Console input without an echo                  
; Input                                     
; Output                                                  
; Changed   AX                                            
;----------------------------------------------------------------------
ISR21_8:    CMP     AH,08                           
            JNE     ISR21_9                         

            CALL    RXCHAR                      ; Return result in AL
            JMP     ISR21_RET	; return to caller

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   09   write 0 terminated string to UART  (change to $ terminated ??)                
; Input     DX   to string                                
; Output                                                  
; Changed   AX                                            
;----------------------------------------------------------------------
ISR21_9:    CMP     AH,09                           
            JNE     ISR21_25                        

            MOV     SI,DX
            CALL    PUTS                        ; Display string DS[SI]
                
            JMP     ISR21_RET	; return to caller

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   25   Set Interrupt Vector                  
; Input     AL   Interrupt Number, DS:DX -> new interrupt handler                                
; Output                                                  
; Changed   AX                                            
;----------------------------------------------------------------------
ISR21_25:   CMP     AH,25h                              
            JNE     ISR21_0B
             
            CLI                                 ; Disable Interrupts            
            XOR     AH,AH
            MOV     SI,AX
            SHR     SI,1
            SHR     SI,1                        ; Int number * 4

            XOR     AX,AX
            MOV     ES,AX                       ; Int table segment=0000

            MOV     [ES:SI],DX                  ; Set offset
            INC     SI
            INC     SI                          ; SI POINT TO INT CS
            MOV     [ES:SI],DS                  ; Set segment


            JMP     ISR21_RET	; return to caller

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   48   Allocate memory                  
; Input                                     
; Output                                                  
; Changed   AX                                            
;----------------------------------------------------------------------
;ISR21_48:CMP       AH,48h                              
;        JNE    ISR21_4C                        
;        JMP    ISR21_RET                       ; return to caller


;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   0Bh  Check for character waiting (kbhit)      
; Input                                                   
; Output    AL   kbhit status !=0 if key pressed          
; Changed   AL                                            
;----------------------------------------------------------------------
ISR21_0B:   CMP     AH,0Bh
            JNE     ISR21_2C 

            XOR     AH,AH
            ;MOV     DX,COMPORT+STATUS           ; get UART RX status
            MOV     DX,LSR              ; get UART RX status

            IN      AL,DX
            ;AND     AL,RX_AVAIL
            AND     AL,DR

            JMP     ISR21_RET	; return to caller

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   2Ch  Get System Time 
;           CH = hour (BCD)
;           CL = minutes (BCD)
;           DH = seconds (BCD)
;           DL = 0                                                                                
;----------------------------------------------------------------------
ISR21_2C:   CMP     AH,02Ch
            JNE     ISR21_30 
          
;            MOV        AH,02h
;            INT        1Ah                         
;            XOR        DL,DL                       ; Ignore 1/100 seconds value
            CALL    READRTC                     ; Get System Time
            JMP     ISR21_RET	; return to caller

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   30h  Get DOS version, return 2                                                                 
;----------------------------------------------------------------------
ISR21_30:   CMP     AH,030h
            JNE     ISR21_3D 
            
            MOV     AL,02                       ; DOS=2.0
            JMP     ISR21_RET	; return to caller

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   3Dh  DOS 2+ Open Existing file (used for write to CON)
; Action    Do nothing                                                                
;----------------------------------------------------------------------
ISR21_3D:   CMP     AH,03DH
            JNE     ISR21_40

            JMP     ISR21_RET	; Just return

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   40h  Write to File or Device
;           BX = file handler, ignored, all strings redirected to UART
;           CX = number of bytes to write
;           DS:DX = Data to write                                                                                                                                                            
;----------------------------------------------------------------------
ISR21_40:   CMP     AH,040h
            JNE     ISR21_4A 
            
            MOV     SI,DX
NEXT40W:    LODSB                               ; AL=DS:[SI++]
            CALL    TXCHAR                      ; Write to UART
            LOOP    NEXT40W                     
                      
            JMP     ISR21_RET

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   4Ah  DOS 2+ Resize Memory
; Action    Do nothing                                                                 
;----------------------------------------------------------------------
ISR21_4A:   CMP     AH,04AH
            JNE     ISR21_4C

            JMP     ISR21_RET	; Just return

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   4Ch  exit to bootloader                                                                 
;----------------------------------------------------------------------
ISR21_4C:   CMP     AH,04CH
            JNE     ISR21_X
            MOV     BL,AL                       ; Save exit code

            MOV     AX,CS
            MOV     DS,AX
            MOV     SI,TERM_MESS                 
            CALL    PUTS
            MOV     AL,BL
            CALL    PUTHEX2
            
            JMP     INITMON                     ; Re-start MON88

;----------------------------------------------------------------------
; Interrupt 21h                                           
; Service   xx   Unkown service, display message int and ah value, return to monitor 
;----------------------------------------------------------------------
ISR21_X:    MOV     AL,21h
            CALL    DISPSERI                        ; Display Int and service number
            JMP     INITMON                         ; Jump back to monitor

ISR21_RET:  POP     SI
            POP     ES
            POP     DS
            IRET


int19:
	push cs
	pop ds
	mov si, msgint19
	call PUTS
	jmp INITMON


;----------------------------------------------------------------------
; Unknown Service Handler
; Display Message, interrupt and service number before jumping back to the monitor
;----------------------------------------------------------------------
DISPSERI:   MOV     BX,AX                           ; Store int number (AL) and service (AH)
            MOV     AX,CS
            MOV     DS,AX
            MOV     SI,UNKNOWNSER_MESS       ; Print Error: Unknown Service
            CALL    PUTS
            MOV     AL,BL
            CALL    PUTHEX2                         ; Print Interrupt Number
            MOV     AL,','
            CALL    TXCHAR
            MOV     AL,BH
            CALL    PUTHEX2                         ; Write Service number
            RET

;----------------------------------------------------------------------
; Spurious Interrupt Handler
;----------------------------------------------------------------------
INTX:       PUSH    DS
            PUSH    SI
            PUSH    AX
            
            MOV     AX,CS                           ; If AH/=0 print message and exit
            MOV     DS,AX
            MOV     SI,UNKNOWN_MESS          ; Print Error: Unknown Service
            CALL    PUTS
            
            POP     AX
            POP     SI
            POP     DS
            IRET


;----------------------------------------------------------------------
; Disassembler Tables
; Watcom C compiler generated
;----------------------------------------------------------------------
L$113:
    DB  0
L$114:
    DB  41H, 41H, 41H, 0
L$115:
    DB  41H, 41H, 44H, 0
L$116:
    DB  41H, 41H, 4dH, 0
L$117:
    DB  41H, 41H, 53H, 0
L$118:
    DB  41H, 44H, 43H, 0
L$119:
    DB  41H, 44H, 44H, 0
L$120:
    DB  41H, 4eH, 44H, 0
L$121:
    DB  41H, 52H, 50H, 4cH, 0
L$122:
    DB  42H, 4fH, 55H, 4eH, 44H, 0
L$123:
    DB  42H, 53H, 46H, 0
L$124:
    DB  42H, 53H, 52H, 0
L$125:
    DB  42H, 54H, 0
L$126:
    DB  42H, 54H, 43H, 0
L$127:
    DB  42H, 54H, 52H, 0
L$128:
    DB  42H, 54H, 53H, 0
L$129:
    DB  43H, 41H, 4cH, 4cH, 0
L$130:
    DB  43H, 42H, 57H, 0
L$131:
    DB  43H, 57H, 44H, 45H, 0
L$132:
    DB  43H, 4cH, 43H, 0
L$133:
    DB  43H, 4cH, 44H, 0
L$134:
    DB  43H, 4cH, 49H, 0
L$135:
    DB  43H, 4cH, 54H, 53H, 0
L$136:
    DB  43H, 4dH, 43H, 0
L$137:
    DB  43H, 4dH, 50H, 0
L$138:
    DB  43H, 4dH, 50H, 53H, 0
L$139:
    DB  43H, 4dH, 50H, 53H, 42H, 0
L$140:
    DB  43H, 4dH, 50H, 53H, 57H, 0
L$141:
    DB  43H, 4dH, 50H, 53H, 44H, 0
L$142:
    DB  43H, 57H, 44H, 0
L$143:
    DB  43H, 44H, 51H, 0
L$144:
    DB  44H, 41H, 41H, 0
L$145:
    DB  44H, 41H, 53H, 0
L$146:
    DB  44H, 45H, 43H, 0
L$147:
    DB  44H, 49H, 56H, 0
L$148:
    DB  45H, 4eH, 54H, 45H, 52H, 0
L$149:
    DB  48H, 4cH, 54H, 0
L$150:
    DB  49H, 44H, 49H, 56H, 0
L$151:
    DB  49H, 4dH, 55H, 4cH, 0
L$152:
    DB  49H, 4eH, 0
L$153:
    DB  49H, 4eH, 43H, 0
L$154:
    DB  49H, 4eH, 53H, 0
L$155:
    DB  49H, 4eH, 53H, 42H, 0
L$156:
    DB  49H, 4eH, 53H, 57H, 0
L$157:
    DB  49H, 4eH, 53H, 44H, 0
L$158:
    DB  49H, 4eH, 54H, 0
L$159:
    DB  49H, 4eH, 54H, 4fH, 0
L$160:
    DB  49H, 52H, 45H, 54H, 0
L$161:
    DB  49H, 52H, 45H, 54H, 44H, 0
L$162:
    DB  4aH, 4fH, 0
L$163:
    DB  4aH, 4eH, 4fH, 0
L$164:
    DB  4aH, 42H, 0
L$165:
    DB  4aH, 4eH, 42H, 0
L$166:
    DB  4aH, 5aH, 0
L$167:
    DB  4aH, 4eH, 5aH, 0
L$168:
    DB  4aH, 42H, 45H, 0
L$169:
    DB  4aH, 4eH, 42H, 45H, 0
L$170:
    DB  4aH, 53H, 0
L$171:
    DB  4aH, 4eH, 53H, 0
L$172:
    DB  4aH, 50H, 0
L$173:
    DB  4aH, 4eH, 50H, 0
L$174:
    DB  4aH, 4cH, 0
L$175:
    DB  4aH, 4eH, 4cH, 0
L$176:
    DB  4aH, 4cH, 45H, 0
L$177:
    DB  4aH, 4eH, 4cH, 45H, 0
L$178:
    DB  4aH, 4dH, 50H, 0
L$179:
    DB  4cH, 41H, 48H, 46H, 0
L$180:
    DB  4cH, 41H, 52H, 0
L$181:
    DB  4cH, 45H, 41H, 0
L$182:
    DB  4cH, 45H, 41H, 56H, 45H, 0
L$183:
    DB  4cH, 47H, 44H, 54H, 0
L$184:
    DB  4cH, 49H, 44H, 54H, 0
L$185:
    DB  4cH, 47H, 53H, 0
L$186:
    DB  4cH, 53H, 53H, 0
L$187:
    DB  4cH, 44H, 53H, 0
L$188:
    DB  4cH, 45H, 53H, 0
L$189:
    DB  4cH, 46H, 53H, 0
L$190:
    DB  4cH, 4cH, 44H, 54H, 0
L$191:
    DB  4cH, 4dH, 53H, 57H, 0
L$192:
    DB  4cH, 4fH, 43H, 4bH, 0
L$193:
    DB  4cH, 4fH, 44H, 53H, 0
L$194:
    DB  4cH, 4fH, 44H, 53H, 42H, 0
L$195:
    DB  4cH, 4fH, 44H, 53H, 57H, 0
L$196:
    DB  4cH, 4fH, 44H, 53H, 44H, 0
L$197:
    DB  4cH, 4fH, 4fH, 50H, 0
L$198:
    DB  4cH, 4fH, 4fH, 50H, 45H, 0
L$199:
    DB  4cH, 4fH, 4fH, 50H, 5aH, 0
L$200:
    DB  4cH, 4fH, 4fH, 50H, 4eH, 45H, 0
L$201:
    DB  4cH, 4fH, 4fH, 50H, 4eH, 5aH, 0
L$202:
    DB  4cH, 53H, 4cH, 0
L$203:
    DB  4cH, 54H, 52H, 0
L$204:
    DB  4dH, 4fH, 56H, 0
L$205:
    DB  4dH, 4fH, 56H, 53H, 0
L$206:
    DB  4dH, 4fH, 56H, 53H, 42H, 0
L$207:
    DB  4dH, 4fH, 56H, 53H, 57H, 0
L$208:
    DB  4dH, 4fH, 56H, 53H, 44H, 0
L$209:
    DB  4dH, 4fH, 56H, 53H, 58H, 0
L$210:
    DB  4dH, 4fH, 56H, 5aH, 58H, 0
L$211:
    DB  4dH, 55H, 4cH, 0
L$212:
    DB  4eH, 45H, 47H, 0
L$213:
    DB  4eH, 4fH, 50H, 0
L$214:
    DB  4eH, 4fH, 54H, 0
L$215:
    DB  4fH, 52H, 0
L$216:
    DB  4fH, 55H, 54H, 0
L$217:
    DB  4fH, 55H, 54H, 53H, 0
L$218:
    DB  4fH, 55H, 54H, 53H, 42H, 0
L$219:
    DB  4fH, 55H, 54H, 53H, 57H, 0
L$220:
    DB  4fH, 55H, 54H, 53H, 44H, 0
L$221:
    DB  50H, 4fH, 50H, 0
L$222:
    DB  50H, 4fH, 50H, 41H, 0
L$223:
    DB  50H, 4fH, 50H, 41H, 44H, 0
L$224:
    DB  50H, 4fH, 50H, 46H, 0
L$225:
    DB  50H, 4fH, 50H, 46H, 44H, 0
L$226:
    DB  50H, 55H, 53H, 48H, 0
L$227:
    DB  50H, 55H, 53H, 48H, 41H, 0
L$228:
    DB  50H, 55H, 53H, 48H, 41H, 44H, 0
L$229:
    DB  50H, 55H, 53H, 48H, 46H, 0
L$230:
    DB  50H, 55H, 53H, 48H, 46H, 44H, 0
L$231:
    DB  52H, 43H, 4cH, 0
L$232:
    DB  52H, 43H, 52H, 0
L$233:
    DB  52H, 4fH, 4cH, 0
L$234:
    DB  52H, 4fH, 52H, 0
L$235:
    DB  52H, 45H, 50H, 0
L$236:
    DB  52H, 45H, 50H, 45H, 0
L$237:
    DB  52H, 45H, 50H, 5aH, 0
L$238:
    DB  52H, 45H, 50H, 4eH, 45H, 0
L$239:
    DB  52H, 45H, 50H, 4eH, 5aH, 0
L$240:
    DB  52H, 45H, 54H, 0
L$241:
    DB  53H, 41H, 48H, 46H, 0
L$242:
    DB  53H, 41H, 4cH, 0
L$243:
    DB  53H, 41H, 52H, 0
L$244:
    DB  53H, 48H, 4cH, 0
L$245:
    DB  53H, 48H, 52H, 0
L$246:
    DB  53H, 42H, 42H, 0
L$247:
    DB  53H, 43H, 41H, 53H, 0
L$248:
    DB  53H, 43H, 41H, 53H, 42H, 0
L$249:
    DB  53H, 43H, 41H, 53H, 57H, 0
L$250:
    DB  53H, 43H, 41H, 53H, 44H, 0
L$251:
    DB  53H, 45H, 54H, 0
L$252:
    DB  53H, 47H, 44H, 54H, 0
L$253:
    DB  53H, 49H, 44H, 54H, 0
L$254:
    DB  53H, 48H, 4cH, 44H, 0
L$255:
    DB  53H, 48H, 52H, 44H, 0
L$256:
    DB  53H, 4cH, 44H, 54H, 0
L$257:
    DB  53H, 4dH, 53H, 57H, 0
L$258:
    DB  53H, 54H, 43H, 0
L$259:
    DB  53H, 54H, 44H, 0
L$260:
    DB  53H, 54H, 49H, 0
L$261:
    DB  53H, 54H, 4fH, 53H, 0
L$262:
    DB  53H, 54H, 4fH, 53H, 42H, 0
L$263:
    DB  53H, 54H, 4fH, 53H, 57H, 0
L$264:
    DB  53H, 54H, 4fH, 53H, 44H, 0
L$265:
    DB  53H, 54H, 52H, 0
L$266:
    DB  53H, 55H, 42H, 0
L$267:
    DB  54H, 45H, 53H, 54H, 0
L$268:
    DB  56H, 45H, 52H, 52H, 0
L$269:
    DB  56H, 45H, 52H, 57H, 0
L$270:
    DB  57H, 41H, 49H, 54H, 0
L$271:
    DB  58H, 43H, 48H, 47H, 0
L$272:
    DB  58H, 4cH, 41H, 54H, 0
L$273:
    DB  58H, 4cH, 41H, 54H, 42H, 0
L$274:
    DB  58H, 4fH, 52H, 0
L$275:
    DB  4aH, 43H, 58H, 5aH, 0
L$276:
    DB  4cH, 4fH, 41H, 44H, 41H, 4cH, 4cH, 0
L$277:
    DB  49H, 4eH, 56H, 44H, 0
L$278:
    DB  57H, 42H, 49H, 4eH, 56H, 44H, 0
L$279:
    DB  53H, 45H, 54H, 4fH, 0
L$280:
    DB  53H, 45H, 54H, 4eH, 4fH, 0
L$281:
    DB  53H, 45H, 54H, 42H, 0
L$282:
    DB  53H, 45H, 54H, 4eH, 42H, 0
L$283:
    DB  53H, 45H, 54H, 5aH, 0
L$284:
    DB  53H, 45H, 54H, 4eH, 5aH, 0
L$285:
    DB  53H, 45H, 54H, 42H, 45H, 0
L$286:
    DB  53H, 45H, 54H, 4eH, 42H, 45H, 0
L$287:
    DB  53H, 45H, 54H, 53H, 0
L$288:
    DB  53H, 45H, 54H, 4eH, 53H, 0
L$289:
    DB  53H, 45H, 54H, 50H, 0
L$290:
    DB  53H, 45H, 54H, 4eH, 50H, 0
L$291:
    DB  53H, 45H, 54H, 4cH, 0
L$292:
    DB  53H, 45H, 54H, 4eH, 4cH, 0
L$293:
    DB  53H, 45H, 54H, 4cH, 45H, 0
L$294:
    DB  53H, 45H, 54H, 4eH, 4cH, 45H, 0
L$295:
    DB  57H, 52H, 4dH, 53H, 52H, 0
L$296:
    DB  52H, 44H, 54H, 53H, 43H, 0
L$297:
    DB  52H, 44H, 4dH, 53H, 52H, 0
L$298:
    DB  43H, 50H, 55H, 49H, 44H, 0
L$299:
    DB  52H, 53H, 4dH, 0
L$300:
    DB  43H, 4dH, 50H, 58H, 43H, 48H, 47H, 0
L$301:
    DB  58H, 41H, 44H, 44H, 0
L$302:
    DB  42H, 53H, 57H, 41H, 50H, 0
L$303:
    DB  49H, 4eH, 56H, 4cH, 50H, 47H, 0
L$304:
    DB  43H, 4dH, 50H, 58H, 43H, 48H, 47H, 38H
    DB  42H, 0
L$305:
    DB  4aH, 4dH, 50H, 20H, 46H, 41H, 52H, 0
L$306:
    DB  52H, 45H, 54H, 46H, 0
L$307:
    DB  52H, 44H, 50H, 4dH, 43H, 0
L$308:
    DB  55H, 44H, 32H, 0
L$309:
    DB  43H, 4dH, 4fH, 56H, 4fH, 0
L$310:
    DB  43H, 4dH, 4fH, 56H, 4eH, 4fH, 0
L$311:
    DB  43H, 4dH, 4fH, 56H, 42H, 0
L$312:
    DB  43H, 4dH, 4fH, 56H, 41H, 45H, 0
L$313:
    DB  43H, 4dH, 4fH, 56H, 45H, 0
L$314:
    DB  43H, 4dH, 4fH, 56H, 4eH, 45H, 0
L$315:
    DB  43H, 4dH, 4fH, 56H, 42H, 45H, 0
L$316:
    DB  43H, 4dH, 4fH, 56H, 41H, 0
L$317:
    DB  43H, 4dH, 4fH, 56H, 53H, 0
L$318:
    DB  43H, 4dH, 4fH, 56H, 4eH, 53H, 0
L$319:
    DB  43H, 4dH, 4fH, 56H, 50H, 0
L$320:
    DB  43H, 4dH, 4fH, 56H, 4eH, 50H, 0
L$321:
    DB  43H, 4dH, 4fH, 56H, 4cH, 0
L$322:
    DB  43H, 4dH, 4fH, 56H, 4eH, 4cH, 0
L$323:
    DB  43H, 4dH, 4fH, 56H, 4cH, 45H, 0
L$324:
    DB  43H, 4dH, 4fH, 56H, 4eH, 4cH, 45H, 0
L$325:
    DB  50H, 52H, 45H, 46H, 45H, 54H, 43H, 48H
    DB  4eH, 54H, 41H, 0
L$326:
    DB  50H, 52H, 45H, 46H, 45H, 54H, 43H, 48H
    DB  54H, 30H, 0
L$327:
    DB  50H, 52H, 45H, 46H, 45H, 54H, 43H, 48H
    DB  54H, 31H, 0
L$328:
    DB  50H, 52H, 45H, 46H, 45H, 54H, 43H, 48H
    DB  54H, 32H, 0
L$329:
    DB  46H, 32H, 58H, 4dH, 31H, 0
L$330:
    DB  46H, 41H, 42H, 53H, 0
L$331:
    DB  46H, 41H, 44H, 44H, 0
L$332:
    DB  46H, 41H, 44H, 44H, 50H, 0
L$333:
    DB  46H, 42H, 4cH, 44H, 0
L$334:
    DB  46H, 42H, 53H, 54H, 50H, 0
L$335:
    DB  46H, 43H, 48H, 53H, 0
L$336:
    DB  46H, 43H, 4cH, 45H, 58H, 0
L$337:
    DB  46H, 43H, 4fH, 4dH, 0
L$338:
    DB  46H, 43H, 4fH, 4dH, 50H, 0
L$339:
    DB  46H, 43H, 4fH, 4dH, 50H, 50H, 0
L$340:
    DB  46H, 43H, 4fH, 53H, 0
L$341:
    DB  46H, 44H, 45H, 43H, 53H, 54H, 50H, 0
L$342:
    DB  46H, 44H, 49H, 56H, 0
L$343:
    DB  46H, 44H, 49H, 56H, 50H, 0
L$344:
    DB  46H, 44H, 49H, 56H, 52H, 0
L$345:
    DB  46H, 44H, 49H, 56H, 52H, 50H, 0
L$346:
    DB  46H, 46H, 52H, 45H, 45H, 0
L$347:
    DB  46H, 49H, 41H, 44H, 44H, 0
L$348:
    DB  46H, 49H, 43H, 4fH, 4dH, 0
L$349:
    DB  46H, 49H, 43H, 4fH, 4dH, 50H, 0
L$350:
    DB  46H, 49H, 44H, 49H, 56H, 0
L$351:
    DB  46H, 49H, 44H, 49H, 56H, 52H, 0
L$352:
    DB  46H, 49H, 4cH, 44H, 0
L$353:
    DB  46H, 49H, 4dH, 55H, 4cH, 0
L$354:
    DB  46H, 49H, 4eH, 43H, 53H, 54H, 50H, 0
L$355:
    DB  46H, 49H, 4eH, 49H, 54H, 0
L$356:
    DB  46H, 49H, 53H, 54H, 0
L$357:
    DB  46H, 49H, 53H, 54H, 50H, 0
L$358:
    DB  46H, 49H, 53H, 55H, 42H, 0
L$359:
    DB  46H, 49H, 53H, 55H, 42H, 52H, 0
L$360:
    DB  46H, 4cH, 44H, 0
L$361:
    DB  46H, 4cH, 44H, 31H, 0
L$362:
    DB  46H, 4cH, 44H, 43H, 57H, 0
L$363:
    DB  46H, 4cH, 44H, 45H, 4eH, 56H, 0
L$364:
    DB  46H, 4cH, 44H, 4cH, 32H, 45H, 0
L$365:
    DB  46H, 4cH, 44H, 4cH, 32H, 54H, 0
L$366:
    DB  46H, 4cH, 44H, 4cH, 47H, 32H, 0
L$367:
    DB  46H, 4cH, 44H, 4cH, 4eH, 32H, 0
L$368:
    DB  46H, 4cH, 44H, 50H, 49H, 0
L$369:
    DB  46H, 4cH, 44H, 5aH, 0
L$370:
    DB  46H, 4dH, 55H, 4cH, 0
L$371:
    DB  46H, 4dH, 55H, 4cH, 50H, 0
L$372:
    DB  46H, 4eH, 4fH, 50H, 0
L$373:
    DB  46H, 50H, 41H, 54H, 41H, 4eH, 0
L$374:
    DB  46H, 50H, 52H, 45H, 4dH, 0
L$375:
    DB  46H, 50H, 52H, 45H, 4dH, 31H, 0
L$376:
    DB  46H, 50H, 54H, 41H, 4eH, 0
L$377:
    DB  46H, 52H, 4eH, 44H, 49H, 4eH, 54H, 0
L$378:
    DB  46H, 52H, 53H, 54H, 4fH, 52H, 0
L$379:
    DB  46H, 53H, 41H, 56H, 45H, 0
L$380:
    DB  46H, 53H, 43H, 41H, 4cH, 45H, 0
L$381:
    DB  46H, 53H, 49H, 4eH, 0
L$382:
    DB  46H, 53H, 49H, 4eH, 43H, 4fH, 53H, 0
L$383:
    DB  46H, 53H, 51H, 52H, 54H, 0
L$384:
    DB  46H, 53H, 54H, 0
L$385:
    DB  46H, 53H, 54H, 43H, 57H, 0
L$386:
    DB  46H, 53H, 54H, 45H, 4eH, 56H, 0
L$387:
    DB  46H, 53H, 54H, 50H, 0
L$388:
    DB  46H, 53H, 54H, 53H, 57H, 0
L$389:
    DB  46H, 53H, 55H, 42H, 0
L$390:
    DB  46H, 53H, 55H, 42H, 50H, 0
L$391:
    DB  46H, 53H, 55H, 42H, 52H, 0
L$392:
    DB  46H, 53H, 55H, 42H, 52H, 50H, 0
L$393:
    DB  46H, 54H, 53H, 54H, 0
L$394:
    DB  46H, 55H, 43H, 4fH, 4dH, 0
L$395:
    DB  46H, 55H, 43H, 4fH, 4dH, 50H, 0
L$396:
    DB  46H, 55H, 43H, 4fH, 4dH, 50H, 50H, 0
L$397:
    DB  46H, 58H, 41H, 4dH, 0
L$398:
    DB  46H, 58H, 43H, 48H, 0
L$399:
    DB  46H, 58H, 54H, 52H, 41H, 43H, 54H, 0
L$400:
    DB  46H, 59H, 4cH, 32H, 58H, 0
L$401:
    DB  46H, 59H, 4cH, 32H, 58H, 50H, 31H, 0
L$402:
    DB  45H, 53H, 0
L$403:
    DB  43H, 53H, 0
L$404:
    DB  53H, 53H, 0
L$405:
    DB  44H, 53H, 0
L$406:
    DB  46H, 53H, 0
L$407:
    DB  47H, 53H, 0
L$408:
    DB  3fH, 0
L$409:
    DB  2aH, 32H, 0
L$410:
    DB  2aH, 34H, 0
L$411:
    DB  2aH, 38H, 0
L$412:
    DB  42H, 58H, 2bH, 53H, 49H, 0
L$413:
    DB  42H, 58H, 2bH, 44H, 49H, 0
L$414:
    DB  42H, 50H, 2bH, 53H, 49H, 0
L$415:
    DB  42H, 50H, 2bH, 44H, 49H, 0
L$416:
    DB  53H, 49H, 0
L$417:
    DB  44H, 49H, 0
L$418:
    DB  42H, 50H, 0
L$419:
    DB  42H, 58H, 0
L$420:
    DB  41H, 4cH, 0
L$421:
    DB  43H, 4cH, 0
L$422:
    DB  44H, 4cH, 0
L$423:
    DB  42H, 4cH, 0
L$424:
    DB  41H, 48H, 0
L$425:
    DB  43H, 48H, 0
L$426:
    DB  44H, 48H, 0
L$427:
    DB  42H, 48H, 0
L$428:
    DB  41H, 58H, 0
L$429:
    DB  43H, 58H, 0
L$430:
    DB  44H, 58H, 0
L$431:
    DB  53H, 50H, 0
L$432:
    DB  43H, 52H, 30H, 0
L$433:
    DB  43H, 52H, 31H, 0
L$434:
    DB  43H, 52H, 32H, 0
L$435:
    DB  43H, 52H, 33H, 0
L$436:
    DB  43H, 52H, 34H, 0
L$437:
    DB  44H, 52H, 30H, 0
L$438:
    DB  44H, 52H, 31H, 0
L$439:
    DB  44H, 52H, 32H, 0
L$440:
    DB  44H, 52H, 33H, 0
L$441:
    DB  44H, 52H, 34H, 0
L$442:
    DB  44H, 52H, 35H, 0
L$443:
    DB  44H, 52H, 36H, 0
L$444:
    DB  44H, 52H, 37H, 0
L$445:
    DB  5bH, 44H, 49H, 5dH, 0
L$446:
    DB  5bH, 45H, 44H, 49H, 5dH, 0
L$447:
    DB  5bH, 53H, 49H, 5dH, 0
L$448:
    DB  5bH, 45H, 53H, 49H, 5dH, 0
L$449:
    DB  25H, 2dH, 31H, 32H, 73H, 20H, 25H, 73H
    DB  0aH, 0
L$450:
    DB  25H, 30H, 32H, 58H, 0
L$451:
    DB  25H, 73H, 3aH, 0
L$452:
    DB  52H, 45H, 50H, 4eH, 5aH, 20H, 0
L$453:
    DB  52H, 45H, 50H, 20H, 0
L$454:
    DB  49H, 6cH, 6cH, 65H, 67H, 61H, 6cH, 20H
    DB  69H, 6eH, 73H, 74H, 72H, 75H, 63H, 74H
    DB  69H, 6fH, 6eH, 0
L$455:
    DB  50H, 72H, 65H, 66H, 69H, 78H, 20H, 6eH
    DB  6fH, 74H, 20H, 69H, 6dH, 70H, 6cH, 65H
    DB  6dH, 65H, 6eH, 74H, 65H, 64H, 0
L$456:
    DB  25H, 73H, 20H, 0
L$457:
    DB  25H, 58H, 0
L$458:
    DB  25H, 30H, 34H, 58H, 0
L$459:
    DB  44H, 53H, 3aH, 25H, 73H, 0
L$460:
    DB  45H, 53H, 3aH, 25H, 73H, 0
L$461:
    DB  25H, 30H, 34H, 58H, 3aH, 25H, 30H, 38H
    DB  58H, 0
L$462:
    DB  25H, 64H, 0
L$463:
    DB  25H, 73H, 0
L$464:
    DB  55H, 6eH, 69H, 6dH, 70H, 6cH, 65H, 6dH
    DB  65H, 6eH, 74H, 65H, 64H, 20H, 6fH, 70H
    DB  65H, 72H, 61H, 6eH, 64H, 20H, 25H, 58H
    DB  0
L$465:
    DB  2cH, 20H, 0
L$466:
    DB  5bH, 25H, 73H, 5dH, 0
L$467:
    DB  5bH, 25H, 58H, 5dH, 0
L$468:
    DB  25H, 73H, 2bH, 25H, 58H, 0
L$469:
    DB  28H, 6eH, 75H, 6cH, 6cH, 29H, 0

		align 2, db 0
_opnames:
    DW  L$113
    DW  L$114
    DW  L$115
    DW  L$116
    DW  L$117
    DW  L$118
    DW  L$119
    DW  L$120
    DW  L$121
    DW  L$122
    DW  L$123
    DW  L$124
    DW  L$125
    DW  L$126
    DW  L$127
    DW  L$128
    DW  L$129
    DW  L$130
    DW  L$131
    DW  L$132
    DW  L$133
    DW  L$134
    DW  L$135
    DW  L$136
    DW  L$137
    DW  L$138
    DW  L$139
    DW  L$140
    DW  L$141
    DW  L$142
    DW  L$143
    DW  L$144
    DW  L$145
    DW  L$146
    DW  L$147
    DW  L$148
    DW  L$149
    DW  L$150
    DW  L$151
    DW  L$152
    DW  L$153
    DW  L$154
    DW  L$155
    DW  L$156
    DW  L$157
    DW  L$158
    DW  L$159
    DW  L$160
    DW  L$161
    DW  L$162
    DW  L$163
    DW  L$164
    DW  L$165
    DW  L$166
    DW  L$167
    DW  L$168
    DW  L$169
    DW  L$170
    DW  L$171
    DW  L$172
    DW  L$173
    DW  L$174
    DW  L$175
    DW  L$176
    DW  L$177
    DW  L$178
    DW  L$179
    DW  L$180
    DW  L$181
    DW  L$182
    DW  L$183
    DW  L$184
    DW  L$185
    DW  L$186
    DW  L$187
    DW  L$188
    DW  L$189
    DW  L$190
    DW  L$191
    DW  L$192
    DW  L$193
    DW  L$194
    DW  L$195
    DW  L$196
    DW  L$197
    DW  L$198
    DW  L$199
    DW  L$200
    DW  L$201
    DW  L$202
    DW  L$203
    DW  L$204
    DW  L$205
    DW  L$206
    DW  L$207
    DW  L$208
    DW  L$209
    DW  L$210
    DW  L$211
    DW  L$212
    DW  L$213
    DW  L$214
    DW  L$215
    DW  L$216
    DW  L$217
    DW  L$218
    DW  L$219
    DW  L$220
    DW  L$221
    DW  L$222
    DW  L$223
    DW  L$224
    DW  L$225
    DW  L$226
    DW  L$227
    DW  L$228
    DW  L$229
    DW  L$230
    DW  L$231
    DW  L$232
    DW  L$233
    DW  L$234
    DW  L$235
    DW  L$236
    DW  L$237
    DW  L$238
    DW  L$239
    DW  L$240
    DW  L$241
    DW  L$242
    DW  L$243
    DW  L$244
    DW  L$245
    DW  L$246
    DW  L$247
    DW  L$248
    DW  L$249
    DW  L$250
    DW  L$251
    DW  L$252
    DW  L$253
    DW  L$254
    DW  L$255
    DW  L$256
    DW  L$257
    DW  L$258
    DW  L$259
    DW  L$260
    DW  L$261
    DW  L$262
    DW  L$263
    DW  L$264
    DW  L$265
    DW  L$266
    DW  L$267
    DW  L$268
    DW  L$269
    DW  L$270
    DW  L$271
    DW  L$272
    DW  L$273
    DW  L$274
    DW  L$275
    DW  L$276
    DW  L$277
    DW  L$278
    DW  L$279
    DW  L$280
    DW  L$281
    DW  L$282
    DW  L$283
    DW  L$284
    DW  L$285
    DW  L$286
    DW  L$287
    DW  L$288
    DW  L$289
    DW  L$290
    DW  L$291
    DW  L$292
    DW  L$293
    DW  L$294
    DW  L$295
    DW  L$296
    DW  L$297
    DW  L$298
    DW  L$299
    DW  L$300
    DW  L$301
    DW  L$302
    DW  L$303
    DW  L$304
    DW  L$305
    DW  L$306
    DW  L$307
    DW  L$308
    DW  L$309
    DW  L$310
    DW  L$311
    DW  L$312
    DW  L$313
    DW  L$314
    DW  L$315
    DW  L$316
    DW  L$317
    DW  L$318
    DW  L$319
    DW  L$320
    DW  L$321
    DW  L$322
    DW  L$323
    DW  L$324
    DW  L$325
    DW  L$326
    DW  L$327
    DW  L$328
_coproc_names:
    DW  L$113
    DW  L$329
    DW  L$330
    DW  L$331
    DW  L$332
    DW  L$333
    DW  L$334
    DW  L$335
    DW  L$336
    DW  L$337
    DW  L$338
    DW  L$339
    DW  L$340
    DW  L$341
    DW  L$342
    DW  L$343
    DW  L$344
    DW  L$345
    DW  L$346
    DW  L$347
    DW  L$348
    DW  L$349
    DW  L$350
    DW  L$351
    DW  L$352
    DW  L$353
    DW  L$354
    DW  L$355
    DW  L$356
    DW  L$357
    DW  L$358
    DW  L$359
    DW  L$360
    DW  L$361
    DW  L$362
    DW  L$363
    DW  L$364
    DW  L$365
    DW  L$366
    DW  L$367
    DW  L$368
    DW  L$369
    DW  L$370
    DW  L$371
    DW  L$372
    DW  L$373
    DW  L$374
    DW  L$375
    DW  L$376
    DW  L$377
    DW  L$378
    DW  L$379
    DW  L$380
    DW  L$381
    DW  L$382
    DW  L$383
    DW  L$384
    DW  L$385
    DW  L$386
    DW  L$387
    DW  L$388
    DW  L$389
    DW  L$390
    DW  L$391
    DW  L$392
    DW  L$393
    DW  L$394
    DW  L$395
    DW  L$396
    DW  L$397
    DW  L$398
    DW  L$399
    DW  L$400
    DW  L$401
_opcode1:
    DB  6, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  6, 2, 30H, 34H, 0, 0, 0, 10H
    DB  6, 2, 33H, 2fH, 0, 0, 0, 10H
    DB  6, 2, 34H, 30H, 0, 0, 0, 10H
    DB  6, 2, 13H, 3, 0, 0, 0, 0
    DB  6, 2, 21H, 4, 0, 0, 0, 0
    DB  71H, 1, 1dH, 0, 0, 0, 0, 0
    DB  6cH, 1, 1dH, 0, 0, 0, 0, 0
    DB  66H, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  66H, 2, 30H, 34H, 0, 0, 0, 10H
    DB  66H, 2, 33H, 2fH, 0, 0, 0, 10H
    DB  66H, 2, 34H, 30H, 0, 0, 0, 10H
    DB  66H, 2, 13H, 3, 0, 0, 0, 0
    DB  66H, 2, 21H, 4, 0, 0, 0, 0
    DB  71H, 1, 1bH, 0, 0, 0, 0, 0
    DB  1, 0, 0, 0, 0, 0, 0, 80H
    DB  5, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  5, 2, 30H, 34H, 0, 0, 0, 10H
    DB  5, 2, 33H, 2fH, 0, 0, 0, 10H
    DB  5, 2, 34H, 30H, 0, 0, 0, 10H
    DB  5, 2, 13H, 3, 0, 0, 0, 0
    DB  5, 2, 21H, 4, 0, 0, 0, 0
    DB  71H, 1, 1eH, 0, 0, 0, 0, 0
    DB  6cH, 1, 1eH, 0, 0, 0, 0, 0
    DB  85H, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  85H, 2, 30H, 34H, 0, 0, 0, 10H
    DB  85H, 2, 33H, 2fH, 0, 0, 0, 10H
    DB  85H, 2, 34H, 30H, 0, 0, 0, 10H
    DB  85H, 2, 13H, 3, 0, 0, 0, 0
    DB  85H, 2, 21H, 4, 0, 0, 0, 0
    DB  71H, 1, 1cH, 0, 0, 0, 0, 0
    DB  6cH, 1, 1cH, 0, 0, 0, 0, 0
    DB  7, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  7, 2, 30H, 34H, 0, 0, 0, 10H
    DB  7, 2, 33H, 2fH, 0, 0, 0, 10H
    DB  7, 2, 34H, 30H, 0, 0, 0, 10H
    DB  7, 2, 13H, 3, 0, 0, 0, 0
    DB  7, 2, 21H, 4, 0, 0, 0, 0
    DB  2, 0, 0, 0, 0, 0, 0, 80H
    DB  1fH, 0, 0, 0, 0, 0, 0, 0
    DB  99H, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  99H, 2, 30H, 34H, 0, 0, 0, 10H
    DB  99H, 2, 33H, 2fH, 0, 0, 0, 10H
    DB  99H, 2, 34H, 30H, 0, 0, 0, 10H
    DB  99H, 2, 13H, 3, 0, 0, 0, 0
    DB  99H, 2, 21H, 4, 0, 0, 0, 0
    DB  3, 0, 0, 0, 0, 0, 0, 80H
    DB  20H, 0, 0, 0, 0, 0, 0, 0
    DB  0a1H, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  0a1H, 2, 30H, 34H, 0, 0, 0, 10H
    DB  0a1H, 2, 33H, 2fH, 0, 0, 0, 10H
    DB  0a1H, 2, 34H, 30H, 0, 0, 0, 10H
    DB  0a1H, 2, 13H, 3, 0, 0, 0, 0
    DB  0a1H, 2, 21H, 4, 0, 0, 0, 0
    DB  4, 0, 0, 0, 0, 0, 0, 80H
    DB  1, 0, 0, 0, 0, 0, 0, 0
    DB  18H, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  18H, 2, 30H, 34H, 0, 0, 0, 10H
    DB  18H, 2, 33H, 2fH, 0, 0, 0, 10H
    DB  18H, 2, 34H, 30H, 0, 0, 0, 10H
    DB  18H, 2, 13H, 3, 0, 0, 0, 0
    DB  18H, 2, 21H, 4, 0, 0, 0, 0
    DB  5, 0, 0, 0, 0, 0, 0, 80H
    DB  4, 0, 0, 0, 0, 0, 0, 0
    DB  28H, 1, 21H, 0, 0, 0, 0, 0
    DB  28H, 1, 22H, 0, 0, 0, 0, 0
    DB  28H, 1, 23H, 0, 0, 0, 0, 0
    DB  28H, 1, 24H, 0, 0, 0, 0, 0
    DB  28H, 1, 25H, 0, 0, 0, 0, 0
    DB  28H, 1, 26H, 0, 0, 0, 0, 0
    DB  28H, 1, 27H, 0, 0, 0, 0, 0
    DB  28H, 1, 28H, 0, 0, 0, 0, 0
    DB  21H, 1, 21H, 0, 0, 0, 0, 0
    DB  21H, 1, 22H, 0, 0, 0, 0, 0
    DB  21H, 1, 23H, 0, 0, 0, 0, 0
    DB  21H, 1, 24H, 0, 0, 0, 0, 0
    DB  21H, 1, 25H, 0, 0, 0, 0, 0
    DB  21H, 1, 26H, 0, 0, 0, 0, 0
    DB  21H, 1, 27H, 0, 0, 0, 0, 0
    DB  21H, 1, 28H, 0, 0, 0, 0, 0
    DB  71H, 1, 21H, 0, 0, 0, 0, 0
    DB  71H, 1, 22H, 0, 0, 0, 0, 0
    DB  71H, 1, 23H, 0, 0, 0, 0, 0
    DB  71H, 1, 24H, 0, 0, 0, 0, 0
    DB  71H, 1, 25H, 0, 0, 0, 0, 0
    DB  71H, 1, 26H, 0, 0, 0, 0, 0
    DB  71H, 1, 27H, 0, 0, 0, 0, 0
    DB  71H, 1, 28H, 0, 0, 0, 0, 0
    DB  6cH, 1, 21H, 0, 0, 0, 0, 0
    DB  6cH, 1, 22H, 0, 0, 0, 0, 0
    DB  6cH, 1, 23H, 0, 0, 0, 0, 0
    DB  6cH, 1, 24H, 0, 0, 0, 0, 0
    DB  6cH, 1, 25H, 0, 0, 0, 0, 0
    DB  6cH, 1, 26H, 0, 0, 0, 0, 0
    DB  6cH, 1, 27H, 0, 0, 0, 0, 0
    DB  6cH, 1, 28H, 0, 0, 0, 0, 0
    DB  72H, 0, 0, 0, 0, 0, 0, 40H
    DB  6dH, 0, 0, 0, 0, 0, 0, 40H
    DB  9, 2, 34H, 36H, 0, 0, 0, 10H
    DB  8, 2, 31H, 3bH, 0, 0, 0, 10H
    DB  6, 0, 0, 0, 0, 0, 0, 80H
    DB  7, 0, 0, 0, 0, 0, 0, 80H
    DB  8, 0, 0, 0, 0, 0, 0, 80H
    DB  9, 0, 0, 0, 0, 0, 0, 80H
    DB  71H, 1, 4, 0, 0, 0, 0, 0
    DB  26H, 2, 34H, 30H, 4, 0, 0, 10H
    DB  71H, 1, 3, 0, 0, 0, 0, 0
    DB  26H, 3, 34H, 30H, 3, 0, 0, 10H
    DB  2aH, 2, 6, 12H, 0, 0, 0, 3
    DB  2bH, 2, 7, 12H, 0, 0, 0, 43H
    DB  69H, 2, 12H, 8, 0, 0, 0, 3
    DB  6aH, 2, 12H, 9, 0, 0, 0, 43H
    DB  31H, 1, 0aH, 0, 0, 0, 0, 2
    DB  32H, 1, 0aH, 0, 0, 0, 0, 2
    DB  33H, 1, 0aH, 0, 0, 0, 0, 2
    DB  34H, 1, 0aH, 0, 0, 0, 0, 2
    DB  35H, 1, 0aH, 0, 0, 0, 0, 2
    DB  36H, 1, 0aH, 0, 0, 0, 0, 2
    DB  37H, 1, 0aH, 0, 0, 0, 0, 2
    DB  38H, 1, 0aH, 0, 0, 0, 0, 2
    DB  39H, 1, 0aH, 0, 0, 0, 0, 2
    DB  3aH, 1, 0aH, 0, 0, 0, 0, 2
    DB  3bH, 1, 0aH, 0, 0, 0, 0, 2
    DB  3cH, 1, 0aH, 0, 0, 0, 0, 2
    DB  3dH, 1, 0aH, 0, 0, 0, 0, 2
    DB  3eH, 1, 0aH, 0, 0, 0, 0, 2
    DB  3fH, 1, 0aH, 0, 0, 0, 0, 2
    DB  40H, 1, 0aH, 0, 0, 0, 0, 2
    DB  14H, 2, 2fH, 3, 0, 0, 0, 90H
    DB  15H, 2, 30H, 4, 0, 0, 0, 90H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  16H, 2, 30H, 3, 0, 0, 0, 90H
    DB  9aH, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  9aH, 2, 30H, 34H, 0, 0, 0, 10H
    DB  9eH, 2, 2fH, 33H, 0, 0, 0, 10H
    DB  9eH, 2, 30H, 34H, 0, 0, 23H, 10H
    DB  5bH, 2, 2fH, 33H, 0, 0, 41H, 10H
    DB  5bH, 2, 30H, 34H, 0, 0, 42H, 10H
    DB  5bH, 2, 33H, 2fH, 0, 0, 81H, 10H
    DB  5bH, 2, 34H, 30H, 0, 0, 0, 10H
    DB  5bH, 2, 31H, 3cH, 0, 0, 0, 10H
    DB  44H, 2, 34H, 35H, 0, 0, 0, 10H
    DB  5bH, 2, 3cH, 31H, 0, 0, 0, 14H
    DB  6cH, 1, 30H, 0, 0, 0, 0, 10H
    DB  64H, 0, 0, 0, 0, 0, 0, 0
    DB  9eH, 2, 22H, 21H, 0, 0, 0, 0
    DB  9eH, 2, 23H, 21H, 0, 0, 0, 0
    DB  9eH, 2, 24H, 21H, 0, 0, 0, 0
    DB  9eH, 2, 25H, 21H, 0, 0, 0, 0
    DB  9eH, 2, 26H, 21H, 0, 0, 0, 0
    DB  9eH, 2, 27H, 21H, 0, 0, 0, 0
    DB  9eH, 2, 28H, 21H, 0, 0, 0, 0
    DB  11H, 0, 0, 0, 0, 0, 0, 40H
    DB  1dH, 0, 0, 0, 0, 0, 0, 40H
    DB  10H, 1, 0cH, 0, 0, 0, 0, 5
    DB  9dH, 0, 0, 0, 0, 0, 0, 0
    DB  74H, 0, 0, 0, 0, 0, 0, 43H
    DB  6fH, 0, 0, 0, 0, 0, 0, 43H
    DB  80H, 0, 0, 0, 0, 0, 0, 0
    DB  42H, 0, 0, 0, 0, 0, 0, 0
    DB  5bH, 2, 13H, 1, 0, 0, 0, 0
    DB  5bH, 2, 21H, 1, 0, 0, 83H, 0
    DB  5bH, 2, 1, 13H, 0, 0, 0, 0
    DB  5bH, 2, 1, 21H, 0, 0, 43H, 0
    DB  5dH, 2, 6, 8, 0, 0, 0, 0
    DB  5eH, 2, 7, 9, 0, 0, 0, 40H
    DB  1aH, 2, 8, 6, 0, 0, 0, 0
    DB  1bH, 2, 9, 7, 0, 0, 0, 40H
    DB  9aH, 2, 13H, 3, 0, 0, 0, 0
    DB  9aH, 2, 21H, 4, 0, 0, 0, 0
    DB  95H, 2, 6, 13H, 0, 0, 0, 0
    DB  96H, 2, 6, 21H, 0, 0, 0, 40H
    DB  51H, 2, 13H, 8, 0, 0, 81H, 0
    DB  52H, 2, 21H, 9, 0, 0, 83H, 40H
    DB  87H, 2, 13H, 8, 0, 0, 0, 0
    DB  88H, 2, 21H, 9, 0, 0, 0, 40H
    DB  5bH, 2, 13H, 3, 0, 0, 0, 0
    DB  5bH, 2, 17H, 3, 0, 0, 0, 0
    DB  5bH, 2, 19H, 3, 0, 0, 0, 0
    DB  5bH, 2, 15H, 3, 0, 0, 0, 0
    DB  5bH, 2, 14H, 3, 0, 0, 0, 0
    DB  5bH, 2, 18H, 3, 0, 0, 0, 0
    DB  5bH, 2, 1aH, 3, 0, 0, 0, 0
    DB  5bH, 2, 16H, 3, 0, 0, 0, 0
    DB  5bH, 2, 21H, 4, 0, 0, 0, 0
    DB  5bH, 2, 22H, 4, 0, 0, 0, 0
    DB  5bH, 2, 23H, 4, 0, 0, 0, 0
    DB  5bH, 2, 24H, 4, 0, 0, 0, 0
    DB  5bH, 2, 25H, 4, 0, 0, 0, 0
    DB  5bH, 2, 26H, 4, 0, 0, 0, 0
    DB  5bH, 2, 27H, 4, 0, 0, 0, 0
    DB  5bH, 2, 28H, 4, 0, 0, 0, 0
    DB  17H, 2, 2fH, 3, 0, 0, 0, 90H
    DB  18H, 2, 30H, 3, 0, 0, 0, 90H
    DB  7fH, 1, 5, 0, 0, 0, 0, 5
    DB  7fH, 0, 0, 0, 0, 0, 0, 5
    DB  4bH, 2, 34H, 37H, 0, 0, 0, 14H
    DB  4aH, 2, 34H, 37H, 0, 0, 0, 14H
    DB  5bH, 2, 2fH, 3, 0, 0, 0, 10H
    DB  5bH, 2, 30H, 4, 0, 0, 0, 10H
    DB  23H, 2, 5, 3, 0, 0, 0, 0
    DB  45H, 0, 0, 0, 0, 0, 0, 0
    DB  0c1H, 1, 5, 0, 0, 0, 0, 5
    DB  0c1H, 0, 0, 0, 0, 0, 0, 5
    DB  2dH, 1, 11H, 0, 0, 0, 0, 0
    DB  2dH, 1, 3, 0, 0, 0, 0, 3
    DB  2eH, 0, 0, 0, 0, 0, 0, 3
    DB  2fH, 0, 0, 0, 0, 0, 0, 3
    DB  19H, 2, 2fH, 10H, 0, 0, 0, 90H
    DB  1aH, 2, 30H, 10H, 0, 0, 0, 90H
    DB  1bH, 2, 2fH, 17H, 0, 0, 0, 90H
    DB  1cH, 2, 30H, 17H, 0, 0, 0, 90H
    DB  3, 1, 3, 0, 0, 0, 0, 0
    DB  2, 1, 3, 0, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  9fH, 0, 0, 0, 0, 0, 0, 0
    DB  0cH, 0, 0, 0, 0, 0, 0, 80H
    DB  0dH, 0, 0, 0, 0, 0, 0, 80H
    DB  0eH, 0, 0, 0, 0, 0, 0, 80H
    DB  0fH, 0, 0, 0, 0, 0, 0, 80H
    DB  10H, 0, 0, 0, 0, 0, 0, 80H
    DB  11H, 0, 0, 0, 0, 0, 0, 80H
    DB  12H, 0, 0, 0, 0, 0, 0, 80H
    DB  13H, 0, 0, 0, 0, 0, 0, 80H
    DB  57H, 1, 0aH, 0, 0, 0, 0, 2
    DB  55H, 1, 0aH, 0, 0, 0, 0, 2
    DB  54H, 1, 0aH, 0, 0, 0, 0, 2
    DB  0a2H, 1, 0aH, 0, 0, 0, 0, 2
    DB  27H, 2, 13H, 3, 0, 0, 0, 3
    DB  27H, 2, 21H, 3, 0, 0, 0, 3
    DB  67H, 2, 3, 13H, 0, 0, 0, 3
    DB  67H, 2, 3, 21H, 0, 0, 0, 3
    DB  10H, 1, 0bH, 0, 0, 0, 0, 2
    DB  41H, 1, 0bH, 0, 0, 0, 0, 1
    DB  0c0H, 1, 0cH, 0, 0, 0, 0, 3
    DB  41H, 1, 0aH, 0, 0, 0, 0, 1
    DB  27H, 2, 13H, 12H, 0, 0, 0, 3
    DB  27H, 2, 21H, 12H, 0, 0, 0, 3
    DB  67H, 2, 12H, 13H, 0, 0, 0, 3
    DB  67H, 2, 12H, 21H, 0, 0, 0, 3
    DB  4fH, 0, 0, 0, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0aH, 0, 0, 0, 0, 0, 0, 80H
    DB  0bH, 0, 0, 0, 0, 0, 0, 80H
    DB  24H, 0, 0, 0, 0, 0, 0, 3
    DB  17H, 0, 0, 0, 0, 0, 0, 0
    DB  1dH, 1, 2fH, 0, 0, 0, 0, 90H
    DB  1eH, 1, 30H, 0, 0, 0, 0, 90H
    DB  13H, 0, 0, 0, 0, 0, 0, 0
    DB  91H, 0, 0, 0, 0, 0, 0, 0
    DB  15H, 0, 0, 0, 0, 0, 0, 3
    DB  93H, 0, 0, 0, 0, 0, 0, 3
    DB  14H, 0, 0, 0, 0, 0, 0, 0
    DB  92H, 0, 0, 0, 0, 0, 0, 0
    DB  1fH, 0, 0, 0, 0, 0, 0, 90H
    DB  20H, 0, 0, 0, 0, 0, 0, 90H
_opcodeg:
    DB  6, 2, 2fH, 3, 0, 0, 0, 0
    DB  66H, 2, 2fH, 3, 0, 0, 0, 0
    DB  5, 2, 2fH, 3, 0, 0, 0, 0
    DB  85H, 2, 2fH, 3, 0, 0, 0, 0
    DB  7, 2, 2fH, 3, 0, 0, 0, 0
    DB  99H, 2, 2fH, 3, 0, 0, 0, 0
    DB  0a1H, 2, 2fH, 3, 0, 0, 0, 0
    DB  18H, 2, 2fH, 3, 0, 0, 0, 0
    DB  6, 2, 30H, 4, 0, 0, 0, 0
    DB  66H, 2, 30H, 4, 0, 0, 0, 0
    DB  5, 2, 30H, 4, 0, 0, 0, 0
    DB  85H, 2, 30H, 4, 0, 0, 0, 0
    DB  7, 2, 30H, 4, 0, 0, 0, 0
    DB  99H, 2, 30H, 4, 0, 0, 0, 0
    DB  0a1H, 2, 30H, 4, 0, 0, 0, 0
    DB  18H, 2, 30H, 4, 0, 0, 0, 0
    DB  6, 2, 30H, 3, 0, 0, 0, 0
    DB  66H, 2, 30H, 3, 0, 0, 0, 0
    DB  5, 2, 30H, 3, 0, 0, 0, 0
    DB  85H, 2, 30H, 3, 0, 0, 0, 0
    DB  7, 2, 30H, 3, 0, 0, 0, 0
    DB  99H, 2, 30H, 3, 0, 0, 0, 0
    DB  0a1H, 2, 30H, 3, 0, 0, 0, 0
    DB  18H, 2, 30H, 3, 0, 0, 0, 0
    DB  78H, 2, 2fH, 3, 0, 0, 0, 0
    DB  79H, 2, 2fH, 3, 0, 0, 0, 0
    DB  76H, 2, 2fH, 3, 0, 0, 0, 0
    DB  77H, 2, 2fH, 3, 0, 0, 0, 0
    DB  81H, 2, 2fH, 3, 0, 0, 0, 0
    DB  84H, 2, 2fH, 3, 0, 0, 0, 0
    DB  83H, 2, 2fH, 3, 0, 0, 0, 0
    DB  82H, 2, 2fH, 3, 0, 0, 0, 0
    DB  78H, 2, 30H, 3, 0, 0, 0, 0
    DB  79H, 2, 30H, 3, 0, 0, 0, 0
    DB  76H, 2, 30H, 3, 0, 0, 0, 0
    DB  77H, 2, 30H, 3, 0, 0, 0, 0
    DB  81H, 2, 30H, 3, 0, 0, 0, 0
    DB  84H, 2, 30H, 3, 0, 0, 0, 0
    DB  83H, 2, 30H, 3, 0, 0, 0, 0
    DB  82H, 2, 30H, 3, 0, 0, 0, 0
    DB  78H, 2, 2fH, 10H, 0, 0, 0, 0
    DB  79H, 2, 2fH, 10H, 0, 0, 0, 0
    DB  76H, 2, 2fH, 10H, 0, 0, 0, 0
    DB  77H, 2, 2fH, 10H, 0, 0, 0, 0
    DB  81H, 2, 2fH, 10H, 0, 0, 0, 0
    DB  84H, 2, 2fH, 10H, 0, 0, 0, 0
    DB  83H, 2, 2fH, 10H, 0, 0, 0, 0
    DB  82H, 2, 2fH, 10H, 0, 0, 0, 0
    DB  78H, 2, 30H, 10H, 0, 0, 0, 0
    DB  79H, 2, 30H, 10H, 0, 0, 0, 0
    DB  76H, 2, 30H, 10H, 0, 0, 0, 0
    DB  77H, 2, 30H, 10H, 0, 0, 0, 0
    DB  81H, 2, 30H, 10H, 0, 0, 0, 0
    DB  84H, 2, 30H, 10H, 0, 0, 0, 0
    DB  83H, 2, 30H, 10H, 0, 0, 0, 0
    DB  82H, 2, 30H, 10H, 0, 0, 0, 0
    DB  78H, 2, 2fH, 17H, 0, 0, 0, 0
    DB  79H, 2, 2fH, 17H, 0, 0, 0, 0
    DB  76H, 2, 2fH, 17H, 0, 0, 0, 0
    DB  77H, 2, 2fH, 17H, 0, 0, 0, 0
    DB  81H, 2, 2fH, 17H, 0, 0, 0, 0
    DB  84H, 2, 2fH, 17H, 0, 0, 0, 0
    DB  83H, 2, 2fH, 17H, 0, 0, 0, 0
    DB  82H, 2, 2fH, 17H, 0, 0, 0, 0
    DB  78H, 2, 30H, 17H, 0, 0, 0, 0
    DB  79H, 2, 30H, 17H, 0, 0, 0, 0
    DB  76H, 2, 30H, 17H, 0, 0, 0, 0
    DB  77H, 2, 30H, 17H, 0, 0, 0, 0
    DB  81H, 2, 30H, 17H, 0, 0, 0, 0
    DB  84H, 2, 30H, 17H, 0, 0, 0, 0
    DB  83H, 2, 30H, 17H, 0, 0, 0, 0
    DB  82H, 2, 30H, 17H, 0, 0, 0, 0
    DB  9aH, 2, 2fH, 3, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  65H, 1, 2fH, 0, 0, 0, 0, 0
    DB  63H, 1, 2fH, 0, 0, 0, 0, 0
    DB  62H, 1, 2fH, 0, 0, 0, 0, 0
    DB  26H, 1, 2fH, 0, 0, 0, 0, 0
    DB  22H, 1, 2fH, 0, 0, 0, 0, 0
    DB  25H, 1, 2fH, 0, 0, 0, 0, 0
    DB  9aH, 2, 30H, 4, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  65H, 1, 30H, 0, 0, 0, 0, 0
    DB  63H, 1, 30H, 0, 0, 0, 0, 0
    DB  62H, 1, 30H, 0, 0, 0, 0, 0
    DB  26H, 1, 30H, 0, 0, 0, 0, 0
    DB  22H, 1, 30H, 0, 0, 0, 0, 0
    DB  25H, 1, 30H, 0, 0, 0, 0, 0
    DB  28H, 1, 2fH, 0, 0, 0, 0, 0
    DB  21H, 1, 2fH, 0, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  28H, 1, 30H, 0, 0, 0, 0, 0
    DB  21H, 1, 30H, 0, 0, 0, 0, 0
    DB  10H, 1, 30H, 0, 0, 0, 0, 5
    DB  10H, 1, 32H, 0, 0, 0, 0, 5
    DB  41H, 1, 30H, 0, 0, 0, 0, 5
    DB  41H, 1, 32H, 0, 0, 0, 0, 5
    DB  71H, 1, 30H, 0, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  8fH, 1, 31H, 0, 0, 0, 0, 3
    DB  98H, 1, 31H, 0, 0, 0, 0, 3
    DB  4dH, 1, 31H, 0, 0, 0, 0, 3
    DB  5aH, 1, 31H, 0, 0, 0, 0, 3
    DB  9bH, 1, 31H, 0, 0, 0, 0, 0
    DB  9cH, 1, 31H, 0, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  8bH, 1, 38H, 0, 0, 0, 0, 3
    DB  8cH, 1, 38H, 0, 0, 0, 0, 3
    DB  46H, 1, 38H, 0, 0, 0, 0, 3
    DB  47H, 1, 38H, 0, 0, 0, 0, 3
    DB  90H, 1, 31H, 0, 0, 0, 0, 3
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  4eH, 1, 31H, 0, 0, 0, 0, 3
    DB  0beH, 1, 35H, 0, 0, 0, 0, 3
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0cH, 2, 30H, 3, 0, 0, 0, 0
    DB  0fH, 2, 30H, 3, 0, 0, 0, 0
    DB  0eH, 2, 30H, 3, 0, 0, 0, 0
    DB  0dH, 2, 30H, 3, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0bfH, 1, 39H, 0, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0d4H, 1, 35H, 0, 0, 0, 0, 0
    DB  0d5H, 1, 35H, 0, 0, 0, 0, 0
    DB  0d6H, 1, 35H, 0, 0, 0, 0, 0
    DB  0d7H, 1, 35H, 0, 0, 0, 0, 0
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H
    DB  0, 0, 0, 0, 0, 0, 0, 80H

		align 2, db 0
_seg_regs:
    DW  L$402
    DW  L$403
    DW  L$404
    DW  L$405
    DW  L$406
    DW  L$407
    DW  L$408
    DW  L$408
_ea_scale:
    DW  L$113
    DW  L$409
    DW  L$410
    DW  L$411
_ea_modes:
    DW  L$412
    DW  L$413
    DW  L$414
    DW  L$415
    DW  L$416
    DW  L$417
    DW  L$418
    DW  L$419
_ea_regs:
    DW  L$420
    DW  L$421
    DW  L$422
    DW  L$423
    DW  L$424
    DW  L$425
    DW  L$426
    DW  L$427
    DW  L$428
    DW  L$429
    DW  L$430
    DW  L$419
    DW  L$431
    DW  L$418
    DW  L$416
    DW  L$417
_direct_regs:
    DW  L$430
    DW  L$420
    DW  L$424
    DW  L$423
    DW  L$427
    DW  L$421
    DW  L$425
    DW  L$422
    DW  L$426
    DW  L$403
    DW  L$405
    DW  L$402
    DW  L$404
    DW  L$406
    DW  L$407
_cntrl_regs:
    DW  L$432
    DW  L$433
    DW  L$434
    DW  L$435
    DW  L$436
    DW  L$408
    DW  L$408
    DW  L$408
_debug_regs:
    DW  L$437
    DW  L$438
    DW  L$439
    DW  L$440
    DW  L$441
    DW  L$442
    DW  L$443
    DW  L$444
_esdi_regs:
    DW  L$445
    DW  L$446
_dssi_regs:
    DW  L$447
    DW  L$448
_inpfp:
    DB  0, 0

;----------------------------------------------------------------------
; Text Strings
;----------------------------------------------------------------------
WELCOME_MESS    DB  CR,LF,CR,LF,"MON88 8088/8086 Monitor ver 0.12"
                DB  CR,LF,"Copyright WWW.HT-LAB.COM 2005-2008"
		db 13,10,"Modified by C. Masloch, 2021"
                DB  CR,LF,"All rights reserved.",CR,LF,0
PROMPT_MESS     DB  CR,LF,"Cmd>",0
ERRCMD_MESS     DB  " <- Unknown Command, type H to Display Help",0
ERRREG_MESS     DB  " <- Unknown Register, valid names: AX,BX,CX,DX,SP,BP,SI,DI,DS,ES,SS,CS,IP,FL",0

LOAD_MESS       DB  CR,LF,"Start upload now, load is terminated by :00000001FF",CR,LF,0
LD_CHKS_MESS    DB  CR,LF,"Error: CheckSum failure",CR,LF,0
LD_REC_MESS     DB  CR,LF,"Error: Unknown Record Type",CR,LF,0          
LD_HEX_MESS     DB  CR,LF,"Error: Non Hex value received",CR,LF,0
LD_OK_MESS      DB  CR,LF,"Load done",CR,LF,0
TERM_MESS       DB  CR,LF,"Program Terminated with exit code ",0
msgint19:	db 13,10,"Program terminated with int19.",0

; Mess+18=? character, change by bp number
BREAKP_MESS     DB  CR,LF,"**** BREAKPOINT ? ****",CR,LF,0

FLAG_MESS       DB  "   ODIT-SZAPC=",0
FLAG_VALID      DB  "XXXX......X.X.X.",0        ; X=Don't display flag bit, .=Display

HELP_MESS       DB  CR,LF,"Commands"
                DB  CR,LF,"DM {from} {to}        : Dump Memory, example D 0000 0100"
                DB  CR,LF,"FM {from} {to} {Byte} : Fill Memory, example FM 0200 020F 5A"
                DB  CR,LF,"R                     : Display Registers"
                DB  CR,LF,"CR {reg}              : Change Registers, example CR SP=1234"
                DB  CR,LF,"L                     : Load Intel hexfile"
                DB  CR,LF,"U  {from} {to}        : Un(dis)assemble range, example U 0120 0128"
                DB  CR,LF,"G  {Address}          : Execute, example G 0100"
                DB  CR,LF,"T  {Address}          : Trace from address, example T 0100"
                DB  CR,LF,"N                     : Trace Next"
                DB  CR,LF,"BP {bp} {Address}     : Set BreakPoint, bp=0..7, example BP 0 2344"
                DB  CR,LF,"CB {bp}               : Clear Breakpoint, example BS 7 8732"
                DB  CR,LF,"DB                    : Display Breakpoints"
                DB  CR,LF,"BS {Word}             : Change Base Segment Address, example BS 0340"
                DB  CR,LF,"WB {Address} {Byte}   : Write Byte to address, example WB 1234 5A"
                DB  CR,LF,"WW {Address} {Word}   : Write Word to address"
                DB  CR,LF,"IB {Port}             : Read Byte from Input port, example IB 03F8"
                DB  CR,LF,"IW {Port}             : Read Word from Input port"
                DB  CR,LF,"OB {Port} {Byte}      : Write Byte to Output port, example OB 03F8 3A"
                DB  CR,LF,"OW {Port} {Word}      : Write Word to Output port, example OB 03F8 3A5A"
                DB  CR,LF,"Q                     : Restart Monitor",0


UNKNOWN_MESS    DB  CR,LF,"*** ERROR: Spurious Interrupt ",0
UNKNOWNSER_MESS DB  CR,LF,"*** ERROR: Unknown Service INT,AH=",0


		align 2, db 0
;----------------------------------------------------------------------
; Disassembler string storage
;----------------------------------------------------------------------
DISASM_INST times 48 db 0			; Stored Disassemble string
DISASM_CODE times 32 db 0			; Stored Disassemble Opcode 

		align 2, db 0
;----------------------------------------------------------------------
; Save Register values
;----------------------------------------------------------------------
UAX         DW      00h                         ; AX
UBX         DW      01h                         ; BX
UCX         DW      02h                         ; CX
UDX         DW      03h                         ; DX
USP         DW      0100h                       ; SP
UBP         DW      05h                         ; BP
USI         DW      06h                         ; SI
UDI         DW      07h                         ; DI
UDS         DW      BASE_SEGMENT                ; DS
UES         DW      BASE_SEGMENT                ; ES
USS         DW      BASE_SEGMENT                ; SS
UCS         DW      BASE_SEGMENT                ; CS
UIP         DW      0100h                       ; IP
UFL         DW      0F03Ah                      ; flags

DUMPMEMS    times 16 db 0			; Stored memdump read values

            times 256 db 0			; Reserve 256 bytes for the stack
		align 2, db 0
TOS         dw 0				; Top of stack
