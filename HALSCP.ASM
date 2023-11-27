; 20HAL File Downloader version 1.0
; Runs on the 8086 under MS-DOS
; 21-APR-81
;
; Compile with ASM and convert to a COM file using HEX2BIN.

; Comments:
; 05-Oct-2020
;	This remote access program would likely have been run by
;	the development team at IBM in Boca to access Microsoft's
;	DEC mainframe in Bellevue running TOPS-10/20, possibly 
;	through an acoustic-coupler type modem (Hayes SmartModems 
;	didn't exist yet). The file date is late in the development
;	cycle, so likely this was running on an IBM PC prototype or
;	pre-production machine. I've read that initial file
; 	transfers would done by courrier from WA to FL.
;
;	Two host-based programs, noted below, were remotely run
;	to facilitate the file transfers. The code for these
;	programs are not known to exist.
;
;	Regarding the development environment, I would guess that
;	SCP's assembler would have been used. It has some unique
;	syntax regarding the use of ORG statements and operand 
;	sizes. Converting from modern MASM source to ASM source
;	would be a bit tedious but not very challenging.
;
; 12-Oct-2020
;	If 20HAL in invoked with a filename, the filename acts
;	like a command script. Each line would have a file
;	transfer command, accomplishing a less-than-disk
;	bulk file transfer. For a single file, you need to hit ^E
;	to enter command mode. It looks like the command line is 
;	something like this:
;		[d:]filename.ext={some command}-{type}
;	Even with this, I still get errors. 
;	Depending on the file type, it sets up a remote TOPS-10
;	command to do the transfer using the two external programs
;	CPMTXT and CPMLOD. ^U is used to cancel a command line
;	that's being typed. It's possible that the "some command"
;	is for the whole-disk command "DISK" in which case a 
;	command like "A:=DISK" may make sense. Could be the remote
;	file name?
;
; 13-Oct-2020
;	The command line is definitely like the above. As a test,
;	hit ^E and type "TESTFIL.MAC=-A" and you will get to a
; 	type of receive mode. 20HAL will send " COP DISK=" to the
;	far-end before dropping into a loop waiting for a response.
;	Not sure what that is yet.
;
;	If it's a MAC file, a "/N<cr><0>" is added to the TOPS-10
;	command. Otherwise, the proper file extension is copied to
;	the FCB. 
;
;	After additional work, the second parameter is the name of
;	the remote file to retrieve. So, the command is:
;		[d:]destination.ext=source.ext-file_type
;	All parameters are required except the destination drive
;	letter. File_type is A (MAC assembler file), B (binary COM),
;	or R (REL relocatable file). I have not yet been able to
;	figure out what "DISK" is for.				
;
; 08-Jan-2022
;	Had a nice discussion with historian Ryan Ottignon about this
;	and he pointed out a few passages in the book "Gates" which
;	provides some clues. Developer Bob O'Rear was primarily
;	responsible for the conversion of SCP code for use with 
;	the IBM prototype and he described the frequent trips to 
;	SeaTac to express courier diskettes to IBM in Florida. So,
;	in my mind, it wouldn't be a stretch to think that he
;	might have hacked this together to make getting files to
;	IBM a lot easier.
;
; 21-Nov-2023
;	Significant work done to get this to compile properly under
;	MASM 6.11 and get the data structure stuff right, but certain
;	instructions assemble differently under MASM than ASM. While
;	I'd prefer to stick with MASM, ASM would certainly be
;	period-correct. ASM also doesn't support STRUC.
;
;	This version is patched to run at 9600 baud to be compatible
;	with SIMH (which assumes a raw port speed of 9600). Look for
;	"PATCH" in the code.

; references to locations in the PDB. ORGs with labels could work too.
TMP1:	equ	1	; PDB exit
BDOS:	equ	5	; far cal to DOS
FPDOS:	equ	6	; *fpDOSEntry
FCB1:	equ	5Ch	; FCB1
FNAME:	equ	5dh	; filename in FCB1
FEXT:	equ	65h	; file extension
FDTA:	equ	80h	; DTA

	org     100h
	put	100h
Start:  jmp     realstart
progsz:		dw      0                       ;  xref 9663:02B3, 0325, 0751
data7:		db      0                       ;  xref 9663:0627, 0649, 0790
cmdcnt: 	dw      0                       ;  xref 9663:0643, 064C, 065A
		db      0, 0
; Pointer to the end of the "resident" portion as realstart is overwritten
; during code execution to create a disk buffer.
sysinit:	dw	realstart       ; 74Bh xref 9663:0343 set in sub5
; private FCB
fcbDrive:	db 	0	;drive 
fcbName: 	db 	0,0,0,0,0,0,0,0	;FNAME
fcbExtension:	db 	0,0,0	;EXT
fcbCurrBlockNo:	dw 	0	;EXTENT
fcbRecordSize:	dw 	0	;RECSIZ
fcbFileSize:	dw 	0	;FILESIZ
fcbDRVBP:	dw 	0	;DRVBP first/next
fcbDate:	dw 	0	;FDATE
fcbTime:	dw 	0	;FTIME
fcbSFN:		db 	0	;DEVID
fcbBegClusterNo:dw 	0 	;FIRCLUS  start of file cluster number
fcbLSTCLUS:	dw 	0	;LSTCLUS  last cluster
fcbCLUSPOS:	dw 	0 	;position of last cluster
		db 	0	; align 32
fcbRandomRecNo:	dw 	0	;RR
		dw 	0

;should be @ 130h
		db      0
CurParseChar:	db      0                       ;  xref 9663:046C, 0486, 049D
		db      0
extmac:		db      "MAC"                   ; CP/M MAC marcoassembler file
extcom:		db      "COM"                   ; executable
extrel:		db      "REL"                   ; relocatable
		db      0,0
secbuf:		ds	128
filecmdtp:	db      0                       ;  xref 9663:0522
filecmdstr:	dw      0                       ;  xref 9663:02FD, 052F, 053E *to which remote prg
halpgfs: 	db      0                       ;  # of paragraphs in 20HAL xref 9663:0347, 075E
recptr:		db      0                       ;  xref 9663:0363, 06F5 *record buffer
BlockCnt:	dw      0                       ;  xref 9663:02C1, 036F, 0374, 059B
; Breaks into TOPS-20 monitor; PJ is "PJOB" which prints the current user info.
t10cmd1:	db      3,3,"PJ",0dh,0		; ETX,ETX,P,J,CR,0
;
; TTY FILL command is a TOPS-20 command to control character pacing after 
; certain control codes as specified on page 2-275 of the TOPS-10/20 Operating 
; System Commands Manual.
t10fillcmd:	db      "TTY FILL 3",0Dh,0		;  xref 9663:02B8
msgblkcnt:	db      8," Blocks.",0Dh,0Ah,0		;  xref 9663:0317
msgdisk:	db      "DISK",0Dh 			; unsure how used
; COPy dev:file.ext [directory]<nnn>=dev:file.ext [directory]. File on the
; left is the DEST; right is the SRC.
msgcopdsk:	db      " COP DISK="            	;  xref 9663:02E8           	
cmdbuff:	ds	24				;  xref 9663:0502, 0556

; These are remote command strings. 'R' is the TOPS-20 'run' command so the two
; programs are programs on the PDP-10. There is a discussion on the PDP-10
; mailing list relating to ITS that mentions remote file transfer programs
; that seem similar. If you look at the /cpm/cis archive on the WCCDROM,
; there are two programs 'dow12' and 'upload12' which download and
; upload from CompuServe using the CIS A protocol. CIS ran on PDP-10s
; and pre-dated DOS, so using it as a model for this effort wouldn't be a 
; stretch. 
msgrcpmt:	db      "R CPMTXT",0Dh,0
msgrcpml:	db      "R CPMLOD",0Dh,0

; Pad each part of the filename with [ch] spaces
; @21eh
padfnm:
		mov	B,[bx],' '		;20h
		inc     bx
		dec     ch
		jnz     padfnm 
		ret

; copies a string from dx to [bx]
strcpydxbx:					;  xref 9663:0230, 057A
		mov     si,dx
		lodb 				; String [si] to al
		mov     [bx],al
		inc     dx
		inc     bx
		dec     ch
		jnz     strcpydxbx 
		ret

; sends a message string to COM and then echos it to the screen
; @ 233h
StringToComm: 					;  xref 9663:0240
		mov     al,[bx]
		and     al,7Fh
		jnz     loc4 			; end of string?
		ret 				; yes, return
loc4:  
		mov     cl,al
		call    comms			; (0698)
		inc     bx
		jmp     StringToComm 		; (0233)

; @243h
prtstring:
		mov     al,[bx]
		and     al,7Fh
		jnz     loc6 
		ret
loc6: 						;  xref 9663:0247
		call    printchar 		; (0584)
		inc     bx
		jmp     prtstring 		; (0243)

;error messages
; @251h
errcmd:		db      "Command Error" 	;  xref 9663:0289
		db      7, 7, 7, 0 		; BEL
errfnf:		db      "File Not Found", 0
errdf:		db      "Disk Full"
		db      7, 7, 7, 0		; BEL

; Error processing code. Disk Full is a fatal exit.
; @27eh
dferror: 					;  xref 9663:06E8
		mov     ax,0			; ah=functn 00h al=mode
		int     10h 			; Video display 
		call    prtstring 		; (0243)
		jmp     exithal 		; (029D)

; Bad command and file not found are non-fatal errors, so print an error and 
; return to the command loop. BX for FNF error message is set in the caller.
cmderror:                                       ;  xref 9663:04D7, 04E8, 051F, 054F
		mov     bx,errcmd 		; (9663:0251='Command Error')
fnferror: 					;  xref 9663:06C5
		call    prtstring 		; (0243)
		call    printcrlf		; (057D)
		jmp     CmdLoop 		; (02B3)

; We get here from the ^C test in the keyboard loop. It already printed '^' 
; and al has 'C', so print it and exit
exitctlc: 					;  xref 9663:0434
		call    printchar		; (0584)
; Exit by way other than ^C
loc11: 						;  xref 9663:063D, 0656
		mov     ax,0 			; ah=functn 00h al=mode
		int     10h 			; Video display 
exithal: 					;  xref 9663:0286
		call    printcrlf 		; (057D)
		int     20h 			; DOS program terminate

;=============================================================================
; startup initialization continues here
; @2a2h
startup2:					;  xref 9663:0774, 0793
;PATCH
;		mov     ax,43h 			; reset to 300,N81
		mov	ax,0E3h			; 9600,N81
		mov     dx,0 			; port= COM1
		int     14h 			; RS-232

; WaitForIdle polls the COM port and waits for it to be ready. Once ready, 
; print CMD1 followed by CMD2. The string ETX,ETX,"PJ",CR is a TOPS-10/20
; command: ^C interrupts the current program and returns to the 
; TOPS-10/20 command prompt. "PJ" is PJOB, which prints the current job ID, 
; user name, user ID and terminal ID. 
		call    WaitForIdle		; (03CF)
		mov     bx,t10cmd1 		; (9663:01C5=3) 3,3,"PJ",0D,0
		call    StringToComm 		; (0233)

; This is the top of the command loop. Always reissue the TTY command.
CmdLoop:					;  xref 9663:0292, 032B
		SEG	CS
		mov     sp,[progsz]		; (9663:0103=0) WORD
		mov     bx,t10fillcmd 		; TOPS-10/20 TTY FILL
		call    StringToComm		; (0233)

; Strings printed to remote system, so continue with the setup. Check for
; a filename on the command line. Maybe this is how it processes a command
; script file to transfer more than one file?
		mov     bx,0
		mov     [BlockCnt],bx		; (9663:01C3=0)
		mov	al,[FNAME]		; 5d
		cmp     al," " 			; is FCB blank?
		jne     CmdInner 		; no, continue

; look for ENQ (^E) to start direct command input
		mov     ch,5 			; ENQ??
		call    WaitForENQ 		; (032E)

;@2d1h
CmdInner: 					;  xref 9663:02CA
		call    WaitForIdle		; (03CF) wait for serial line
		call    GetCommand 		; (0402) print "*" prompt and process
		call    ParseCmdLine 		; (0449) bx=cmd input buffer
		call    LookForEq 		; (04D0) dx=second cmd
		call    WhatFileType 		; (0519) sets xfer string 
						;    filecmdstr set dx=*ext al=type
		call    CreateFileOW 		; (06C8) create file
		call    IsDiskCmd		; (0502)
		jz      DiskCmd			; DISK is param2, so continue

; This sends a remote copy command to the remote system. A download request
; command line is "dest.mac=source.mac-A", so 20HAL sends 'COP DISK='
; with the source file name "source.mac". 
		mov     bx,msgcopdsk 		; (9663:01E8=' COP DISK=')
		jz      loc16			; print only if not disk cmd
		call    StringToComm 		 ; (0233)

; Sits here in a loop waiting for the TOPS-10/20 monitor prompt to return 
; after issuing the system copy command. While idling it prints a block on the 
; screen for each pass.
loc16: 
		call    comread 		; (0666)
loc17:
		call    comread 		; (0666)
		call    printchar		; (0584)
		cmp     al,"."	
		jne     loc17 

; Command request was acknowledged, so send the file transfer command
; based on the file type.
; @2fdh                 
DiskCmd: 					;  xref 9663:02E6
		mov     bx,[filecmdstr]		; (9663:01BF=0)
		call    StringToComm		; (0233)
		call    printcrlf		; (057D)
		call    WaitForIdle 		; (03CF)
		mov     cl,0Dh			; Is this the sync char?
		call    comwrite		; (06A1)
		mov     al," "
		call    printchar		; (0584)
		call    BlockXfer		; (0340)
		mov     bx,msgblkcnt		; (9663:01D7='  Blocks.')
		call    prtstring		; (0243)
		call    WaitForIdle		; (03CF)
		mov     cl,0Dh 			; xfer over?
		call    comwrite		; (06A1)
		mov     bx,[progsz]		; (9663:0103=0)
		mov     sp,bx
		jmp     CmdLoop			; (02B3) go to the beginning

; 	Called from:   9663:02CE
; Enters with ch=5 so this loop tests for ENQ (^E)
; @32eh
WaitForENQ:
		call    rxloop			; (05DB)
		cmp     al,ch			; ENQ?
		jne     loc20
		jmp     printcrlf		; (057D) returns to 02D1 CmdInner
loc20: 
		mov     cl,al
		call    comwrite		; (06A1)
		jmp     WaitForENQ		; (032E) loop

;	Called from:   9663:0314
; This is the actual file transfer code. It sends "B" as a "ready" char and 
; beeps, and sits in this B/beep loop until characters are received. It uses
; the end of the file as the receive buffer.
; @340h
BlockXfer:
		mov     bx,realstart		;74Bh
		mov     [sysinit],bx		; (9663:010A=74Bh)
		mov     ch,[halpgfs]		; (9663:01C1=0)
		mov     cl,0

XferLoop:					;  xref 9663:039F, 03CC
		push    cx 
		push    bx 			; DTA
		mov     dx,81h			; record size 129b?

XferLoop1: 					; inner loop
		call    comread 		; (0666)
		jnz     GetBlock 		; char, so collect bytes
		jmp     CheckBuf		; (06F5) sends NAK (^U) and 
						; returns to SendSynch

; Block size DX is set above -- 128 bytes plus terminator or maybe a block 
; number (max 255) followed by 128 bytes. BX is the disk transfer buffer 
; which is recycled space at the end. It's not clear if there is any block 
; separation or if it just relies on character counting.
; @35ah
GetBlock: 					;  xref 9663:0355
		mov     [bx],al			; save char in buffer
		inc     bx
		xor     al,dh 			; dh should be 0
		mov     dh,al
		dec     dl 			 ; dl= remaining chars in buf?
		mov     [recptr],dl		; save # chars left in record
		jnz     XferLoop1		; more space? continue
; record full
		or      al,dh 			; zero?
		jnz     SendSynch 		; send synch to resend block?
		xchg    bx,dx			; count the block
		mov     bx,[BlockCnt]
		inc     bx
		mov     [BlockCnt],bx		; (9663:01C3=0)
		xchg    bx,dx
		dec     bx
		pop     cx
		pop     cx
		inc     cl
		push    cx
		mov     al,cl
		cmp     al,ch
		pushf 
		push    ax
		jnz     loc25 			; done with file, get more?
		call    DiskWriteRec 		; (071C) write record and get next

loc25: 						;  xref 9663:0386
		push    bx
		call    PrintBlkCnt		; (0596)
		pop     bx
		mov     al," " 	
		call    printchar		; (0584)
		mov     cl,"A"
		call    comwrite		; (06A1)
		pop     ax
		popf
		pop     cx
		jz      BlockXfer		; restart next block
		jmp     XferLoop		; (034D) loop in current block

; this sounds the bell, prints backspace and ^C. "ready for block" process?
; @3a2h
SendSynch: 					;  xref 9663:036B, 06FC
		mov     al,7 			; BEL
		call    printchar 		; (0584)
		inc     al 			; BS
		call    printchar 		; (0584)
		mov     al,3 			; this is a loop of 256*256*3
		mov     cx,0
loc27: 
		dec     ch
		jnz     loc27  
		dec     cl
		jnz     loc27
		dec     al
		jnz     loc27
		call    WaitForIdle 		; (03CF)
		mov     cl,"B" 
		mov     al,cl
		call    printchar		; (0584)
		call    comwrite 		; (06A1)
		pop     bx
		pop     cx
		jmp     XferLoop		; (034D)

;         Called from:   9663:02AA, 02D1, 0307, 031D, 03BD
; @3cfh
WaitForIdle:
		push    bx
		push    dx
		push    cx
		mov     cx,0
loc28: 						;  xref 9663:03F6
		mov     al,1
		
; looks like this is some sort of wait loop for 256*2
loc29:   					;  xref 9663:03D9, 03DD, 03E1
		dec     ch
		jnz     loc29 
		dec     cl
		jnz     loc29 
		dec     al
		jnz     loc29 

; get line status
		mov     ah,3
		mov     dx,0
		int     14h 			; RS-232   dx=com1, ah=func 03h
						;  get status al=modem, ah=line
		and     ah,1 			; RDR?
		jz      loc30 			; Rx data available

		mov     ah,2
		mov     dx,0
		int     14h 			; RS-232   dx=com1, ah=func 02h
						;  get char al, ah=return status
; line still not ready, so wait again
		jp	loc28			; (03D5)

; line is idle and ready, so return
loc30: 						;  xref 9663:03ED
		pop     cx
		pop     dx
		pop     bx
		ret


; Command line processor
; @3fch
GetCommandTop:					;  xref 9663:0439
		call    printchar		; (0584)
		call    printcrlf		; (057D)
		
;         Called from:   9663:02D4
; The only way to get the * prompt is by hitting ^E
GetCommand:
		mov     al,"*" 
		call    printchar		; (0584)
		mov     bx,secbuf		; 128-byte command line buffer
CmdFetchChar:  					;  xref 9663:0424, 043E
		call    rxloop 			; (05DB)
		call    toupper 		; (061A)
		cmp     al,0Dh 			; CR?
		je      GotCmdLine 		; yes, process command line
		cmp     al,0Ah 			; LF?
		je      loc33 			; yes, print LF and loop back
		cmp     al," " 			; space
		je      loc33			; yes, print it and loop
		jc      prtctrl 		; print other control chars
		mov     [bx],al			; save it to buffer
		inc     bx 			; next buffer slot

; print current character and loop
loc33: 
		call    printchar		; (0584)
		jmp     CmdFetchChar		; (040A)


; print/expand control character
; @427h
prtctrl: 					;  xref 9663:041C
		push    ax
		mov     al,"^" 			;5Eh 
		call    printchar 		; (0584)
		pop     ax
		add     al,"@"			; ASCII adjust ctrlchar
		cmp     al,"C" 			; 43h 'C' control-C?
		jne     NotCtlC 
		jmp     exitctlc		; (0295) ^C, so exit

; check other control characters (only one is ^U to cancel command)
NotCtlC:
		cmp     al,"U" 			; 55h
		je      GetCommandTop 		; cancel command and restart
		call    printchar 		; (0584)
		jmp     CmdFetchChar 		; (040A) top of loop


; CR received, so return command line to parent
GotCmdLine:					;  xref 9663:0412
		mov     [bx],al			; save final CR
		mov     bx,secbuf		; reset BX to top of buffer
		jmp     printcrlf 		; (057D) exit via here


;         Called from:   9663:02D7
; Parse command line. Enters with BX= buffer used in GetCommand.
; Look for a drive letter and if one is specified, get the letter, 
; determine the drive number for the FCB (0=default; 1=A) and then store it
; in the FCB. The next 11 characters are a file name or possibly 
; just "DISK", resulting in a command like "A:=DISK-"
; @449h
ParseCmdLine:
		push    bx
		push    dx
		push    cx
		xchg    bx,dx 			; save *cmd to DX
		mov     bx,fcbDrive		; (9663:010C=0)
		inc     dx
		mov     si,dx
		lodb 				; String [si] to al
		dec     dx
		cmp     al,":" 
		mov     al,0
		jnz     loc37
		mov     si,dx
		lodb 				; String [si] to al
		inc     dx
		inc     dx
		sub     al,"@" 			;ASCII adjust
loc37: 						;  xref 9663:045A
		mov     [bx],al			; save it
		inc     bx

; Get the next 8 characters which I assume is a file name.
; @466h
		mov     ch,8 			; 8 character loop?
loc38: 						;  xref 9663:0480
		mov     si,dx
		lodb				; String [si] to al
		inc     dx
		mov     [CurParseChar],al	; (9663:0131=0)
		cmp     al,"." 			; file extension so short FNM
		je      loc40			; pad to 8-chars if needed
		cmp     al,"=" 			; check for second command
		je      loc40
		cmp     al,"!" 
		jb      loc40 			; <1Dh is space and control chars
		mov     [bx],al 		; save the char
		inc     bx
		dec     ch
		jnz     loc38 			; not done yet, so loop

; Done with first 8 characters, so check for a file extension or a secondary 
; command.
; @482h
loc39: 						;  xref 9663:0493
		mov     si,dx
		lodb 				; String [si] to al
		inc     dx
		mov     [CurParseChar],al 	; (9663:0131=0)
		cmp     al,"." 
		je      loc41
		cmp     al,"="
		je      loc41
		cmp     al,"!" 
		jae     loc39			; keep parsing
		jmp     loc41			; (049B)

; Pad filename to 8 chars and continue
loc40: 						;  xref 9663:0471, 0475, 0479
		call    padfnm 			; (021E)

; If there's a '.' we assume an extension exists and then copy it to the buffer. 
loc41: 						;  xref 9663:048B, 048F, 0495
		mov     ch,3
		mov     al,[CurParseChar]	; (9663:0131=0)
		cmp     al,"." 
		je      loc42 
;		mov     dx,132h 		; this points to file extensions - 1
		mov	dx,extmac - 1
loc42: 						;  xref 9663:04A2, 04B4
		mov     si,dx
		lodb 				; String [si] to al
		cmp     al,"=" 			; then skip rest of extension
		je      loc43 			; extension is specified and we have '='
						;   so skip copying rest of extension.
		inc     dx
		mov     [bx],al
		inc     bx
		dec     ch
		jnz     loc42
		jmp     loc44 			; (04BC)
loc43:						;  xref 9663:04AC
		call    padfnm 			; (021E) pad the extension too

; In the caller, CH is used as a loop variable that is used to check file 
; extensions against MAC, COM, REL (note the move absolute of 132h which is
; ds:132h). BX is a pointer in the temporary FCB. CH should also be 0 on entry.
; There is a bug in ASM that requires a short forward reference in order to get
; the assembler to emit the right op codes for the 16-bit operand. DS:1 is the
; exit interrupt number in the PSP (CD 20) so this should not be modified. I 
; think it's an artifact of Sourcer not knowing about the ASM bug. 
; @4bch
loc44:						;  xref 9663:04B6
		mov     cl,0
		mov     [bx],ch
		mov     [bx+ONE],ch		; (9663:0001=0) DS:1??
		mov     [fcbRandomRecNo],cx	; (9663:012C=0)
		mov     [fcbRandomRecNo+2],cx	; (9663:012E=0)
		pop     cx
		pop     dx
		pop     bx
		ret

;         Called from:   9663:02DA
; On entry, BX points to the command buffer. Returns with dx pointing to a
; "second command" buffer. {BX popped at end of ParseCmdLine.}
; @4d0h
LookForEq:
		mov     al,[bx]
		inc     bx
		cmp     al,0Dh			; EOL? {empty command line}
		jne     loc46			; no, keep processing
		jmp     cmderror		; (0289) process CR
loc46: 
		cmp     al,"=" 
		jne     LookForEq 		; no, loop back

; So far, the command line is "[d:]file.ext=" or "d:=" so get up to 
; 24-bytes for whatever is after. '=' with nothing being an ERR                               
		mov     dx,cmdbuff		; 1F2h 24-char buffer?
loc47: 						;xref 9663:04F3
		mov     al,[bx]
		inc     bx
		cmp     al,0Dh
		jne     loc48 
		jmp     cmderror 		; (0289)

; Parse the second part of the command; "-" is a flag for the file
; type A, B or R. Command is copied from the input buffer in BX to DX.
loc48:  					;  xref 9663:04E6
		cmp     al,"-" 
		je      loc49
		mov     di,dx
		stob 				; Store al to es:[di]
		inc     dx
		jmp     loc47 			; (04E1)

; Dash without a command, so add a <CR><0>
loc49:						;  xref 9663:04ED
		mov     al,0Dh
		mov     di,dx
		stob 				; Store al to es:[di]
		inc     dx
		xor     al,al
		mov     di,dx
		stob 				; Store al to es:[di]
		ret

;         Called from:   9663:02E3
; test to see if "DISK" command received? 
; @502h
IsDiskCmd: 					;  xref 9663:02E3
		mov     bx,cmdbuff		; (9663:01F2=0)
		mov     dx,msgdisk 		;1E3h msgdisk??
		mov     ch,5
loc50: 						;  xref 9663:0516
		mov     si,dx
		lodb 				; String [si] to al
		cmp     al,[bx]
		je      loc51 
		ret
loc51: 						;  xref 9663:050F
		inc     bx
		inc     dx
		dec     ch
		jnz     loc50
		ret

;         Called from:   9663:02DD
; Looks like this figures out what kind of file is being transferred. Called
; with BX= command input buffer pointing at next char after parsing second part
; of command. DI points to second command.
; @519h
WhatFileType:
		mov     al,[bx]
		cmp     al,0Dh			; EOL? {empty command line}
		jne     loc52			; no, process command
		jmp     cmderror 		; (0289) yes, exit

; Setup registers for the specific request type. BX contains
; return location which is pushed on the stack and then popped
; into IP on the RET after file type parameters are set.
loc52:						;  xref 9663:051D
		mov     [filecmdtp],al		; (9663:01BE=0)
		mov     bx,loc55a       	;552h "error" address
		push    bx			; create imbalanced stack

; "A" = MAC file
		mov     bx,msgrcpmt		;20Ah CPMTTY
		mov     dx,extmac		;133h
		mov     [filecmdstr],bx		; (9663:01BF=0)
		cmp     al,"A" 			; 41h 'A' CPMTXT
		jne     loc53
		ret

; "B" = COM file
loc53:						;  xref 9663:0535
		mov     bx,msgrcpml		;214h CPMLOD
		mov     dx,extcom 		;136h
		mov     [filecmdstr],bx 	; (9663:01BF=0)
		cmp     al,"B"			; 42h B
		jne     loc54 
		ret

; "R" = REL file
loc54: 						;  xref 9663:0544
		mov     dx,extrel		;139h
		cmp     al,"R"			; 52h 'R'
		jne     loc55			; not A, B, or R
		ret 				; do a return to loc55a

; Stack is still imbalanced here I think...
loc55: 						;  xref 9663:054C
		jmp     cmderror		; (0289) 

; We get here by the imbalanced stack (the "push bx" in loc52) and the ret in
; loc53 and loc54 which pops it into IP. 
; with:
;       al= transfer command A, B, or R
;       bx= TOPS-10 transfer command based on file type
;       dx= offset to related extension
; @552h
loc55a:
		cmp     al,"A"
		jne     loc57 			; COM or REL

; Get here if it's a type "A" (MAC) file (so, non-executable). Reset BX to 
; beginning of the second-command buffer used in loc47.
		mov     bx,cmdbuff 	; (9663:01F2=0)
; find the end of the buffer and terminate it with /N<0>
loc56: 
		inc     bx
		mov     al,[bx]
		cmp     al,0Dh 			; EOL?
		jne     loc56 			; no, loop
; terminate line with "/N<CR>0"
		mov	B,[bx],"/"		; 2Fh
		inc     bx
		mov 	B,[bx],"N"		; 4Eh
		inc     bx
		mov     [bx],al 		; put <CR>
		inc     bx
		mov 	B,[bx],0
; process COM/REL. This should return to 02DD if there's already an extension, 
; otherwise copy the extension into the FCB.
loc57:						;  xref 9663:0554
		mov     bx,fcbExtension		; (9663:0115=0)
		mov     al,[bx]
		or      al,al 
		jz      padext
		ret

; this will space-pad the file extension if needed.
padext: 					;  xref 9663:0575
		mov     ch,3
		jmp     strcpydxbx		; (0227)

;         Called from:   9663:028F, 029D, 0304, 03FF
; @57dh
printcrlf:
		mov     al,0Dh
		call    printchar 		 ; (0584)
		mov     al,0Ah

; Although Sourcer decompiles it with a negative offset to the current PC, 
; it's really a "CALL 0005" to the PSP which is the CP/M equivalent to calling 
; the BDOS. Function 6 is the call to Direct Console I/O. CL= BDOS function; 
; DL= character.
printchar:
		push    bx
		push    dx
		push    cx
		push    ax
		pushf
		mov     cl,6
		mov     dl,al
		call    BDOS		;$-588h
		popf 
		pop     ax
		pop     cx
		pop     dx
		pop     bx
		ret

;
;         Called from:   9663:038C
; @596h
PrintBlkCnt:
		mov     al,0Dh
		call    printchar 		; (0584)
		mov     W,bx,[BlockCnt]		; (9663:01C3=0)
		mov     cl,0
		mov     dx,3E8h 		; 1000d
		call    BX2DEC			; (05BC)
		mov     dx,64h 			; 'd'??
		call    BX2DEC			; (05BC)
		mov     dx,0Ah			; CR
		call    BX2DEC			; (05BC)
		mov     al,"0"
		add     al,bl
		mov     ch,al
		jmp     loc62			; (05D4)

; routine BX2DEC - print BX in decimal
BX2DEC: 
		mov     ch,"/"
loc61: 					;  xref 9663:05C2
		inc     ch 		; '0' 30h
		sub     bx,dx 		; bx=BlockCnt from PrintBlkCnt
		jnc     loc61 		; Jump if carry=0
		add     bx,dx
		mov     al,ch
		sub     al,"0" 
		jnz     loc62 
		cmp     al,cl
		jne     loc62 
		mov     ch," "
		jp	loc63		; (05D6)
loc62:					;  xref 9663:05B9, 05CA, 05CE
		inc     cl
loc63: 					;  xref 9663:05D2
		mov     al,ch
		jmp     printchar	; (0584) exits through printchar

;
;         Called from:   9663:032E, 040A
; looks like this gets a character from the first serial channel if available. 
; If not, polls the keyboard for a character.
; @5dbh
rxloop:
		push    cx
		push    dx
		push    bx
loc64: 
		mov     ah,3		; ah=post status
		mov     dx,0		; dx=portnum 0...3
		int     14h 		; RS-232 get status al=modem, ah=line
		and     ah,1 		; ah=LSR  b.1=RDR
		jz      loc65 		; no char, move on
		mov     ah,2 		; ah=2 get char
		mov     dx,0 		; port 0
		int     14h 		; RS-232 get char al, ah=return status
		and     ah,1Eh 		; any line errors? (brk,frm,pty,OR)
		jnz     loc64 		; line error, try again.
		and     al,7Fh 		; no line error...make 7-bit
		cmp     al,7Fh		; DEL?
		je      loc64		; yes, DEL key so get another
		call    printchar	; (0584) print it...
		jmp     loc64 		; (05DE) ...and loop

loc65: 					;  xref 9663:05E8
		mov     al,[FNAME]	; filename 5d 
		cmp     al," "
		jne     loc68		; FCB has something in it so go

		mov     cl,6 		; BDOS call Direct Console I/O
		mov     dl,0FFh 	; SubFx=getcharnonblock
		call    BDOS		;$-608h
		or      al,al 		; Zero ?
		jz      loc64 		; no keyboard char waiting, loop
		and     al,7Fh 		; force 7-bit ASCII and return
		pop     bx
		pop     dx
		pop     cx
		ret

;convert LC to UC
; @61ah
toupper:
		cmp     al,"a"
		jae     loc66 
		ret
loc66: 					;  xref 9663:061C
		cmp     al,"{" 
		jb      loc67 
		ret
loc67: 					;  xref 9663:0621
		xor     al,20h
		ret

; get here from comm loop if the FCB has a filename in it so I assume that if
; the FCB is valid, it assumes that a file transfer is in progress and what's 
; being received should be written to disk.
loc68:						;  xref 9663:0607, 0660
		mov     al,[data7] 		; (9663:0105=0)
		dec     al
		jns     loc70

		mov     cl,14h			; BDOS 14h ReadNextRecord
		mov     dx,FCB1			; FCB 5C
		mov     bx,FDTA			; DTA 80
		call    BDOSDiskFnCx		; (0736)
		add     al,0FFh
		jnc     loc69			; Jump if carry=0
		jmp     loc11			; (0298)
loc69:						;  xref 9663:063B
		mov     bx,80h 			; count of chars
		mov     [cmdcnt],bx 		; (9663:0106=0)
		mov     al,7Fh
loc70: 						;  xref 9663:062C
		mov     [data7],al 		; (9663:0105=0)
		mov     bx,[cmdcnt] 		; (9663:0106=0)
		mov     al,[bx]
		cmp     al,1Ah 			; ^Z
		jne     loc71
		jmp     loc11 			; (0298) exit program

loc71: 						;  xref 9663:0654
		inc     bx
		mov     [cmdcnt],bx 		; (9663:0106=0)
		or      al,al 			; Zero ?
		js      loc68			; Jump if sign=1
		pop     bx
		pop     dx
		pop     cx
		ret

; @666h
comread:
		push    dx
		push    cx
		mov     cl,0
		mov     ch,80h
		call    comstat		; (0680)
		pop     cx
		pop     dx
		jnz     loc72 
		ret
loc72:					;  xref 9663:0671
		push    dx
		mov     ah,2 		; RS-232 get char
		mov     dx,0 		; port 0
		int     14h		; RS-232  get char al, ah=retn stat
		inc     ah
		pop     dx
		ret

; @680h
comstat:				;  xref 9663:0691, 0695
		mov     ah,3
		push    cx
		mov     dx,0
		int     14h		; RS-232   dx=com1, ah=func 03h
					;  get status al=modem, ah=line
		pop     cx
		and     ah,1
		jz      loc74
		ret

loc74:					;  xref 9663:068C
		dec     cl
		jnz     comstat
		dec     ch
		jnz     comstat
		ret

; @698h
comms:
		call    comwrite 	; (06A1)
		call    comread		; (0666)
		jmp     printchar	; (0584)

; @6a1h
comwrite:
		push    dx
		mov     ah,1
		mov     dx,0
		mov     al,cl
		int     14h 		; RS-232   dx=com1, ah=func 01h
		pop     dx 		;  write char al, ah=retn status
		ret

; @6adh
BDOSOpenFile:
		mov     cl,0Fh		; BDOS Open File
					; Open returns al=0-3 or ffh=error
		mov     dx,FCB1 	; FCB 5C
		mov     bx,FDTA		; DTA 80
		call    BDOSDiskFnCx	; (0736)
		inc     al		; 0ffh+1=0 for error
		jz      loc75		; file not found, so print error
		ret
loc75: 
		mov	B,[FNAME],20h	; mark FCB as invalid 5D
		mov     bx, errfnf	; file not found 262h
		jmp     fnferror 	; (028C)

;
;         Called from:   9663:02E0
; This routine opens a file in OW (overwrite) mode.
; @6c8h
CreateFileOW:
		mov     dx,realstart	;74Bh realstart (end of code)
		mov     cl,1Ah 		; BDOS SetDMAAddress DX
		call    BDOS		;$-6C8h
		mov     dx,fcbDrive	;10Ch
		push    dx
		mov     cl,13h		; BDOS DeleteFile
		call    BDOS 		;$-6D1h
		pop     dx
		push    dx
		mov     cl,16h 		; BDOS CreateFile
		call    BDOS		;$-6D8h
		pop     dx
		inc     al
		jnz     openok
erdff: 					;  xref 9663:06F2, 0733
		mov     bx,errdf	; disk full 271h
		jmp     dferror		; (027E) exit with DF
openok:
		mov     cl,0Fh		; BDOS OpenFile
		call    BDOS 		;$-6E8h
		inc     al
		jz      erdff 		; disk full
		ret

; looks like this checks how full the buffer is and either sends a sync 
; character if empty or flushes it if full.
; @6f5h
CheckBuf:				;  xref 9663:0357
		mov     al,[recptr]	; (9663:01C2=0) get pos in buffer
		sub     al,80h
		jz      FlushBuf	; buffer full? write it
		jmp     SendSynch	; (03A2) sends synch and loop

; record buffer full, so write it.
; @6ffh
FlushBuf:
		mov     cl,15h		; send NAK to the channel
		call    comwrite	; (06A1)
		call    comread		; (0666)
		pop     bx
		pop     cx
;@709h
		cmp     cl,ZERO		; this codes as 82/f9/00 so
		je      loc80
		call    DiskWriteRec	; (071C)

; done writing records, so close and flush the file.
loc80: 					;  xref 9663:070C
		mov     dx,fcbDrive 	; 10Ch
		mov     bx,realstart    ; 74Bh
		mov     cl,10h 		; BDOS CloseFile
		jmp     BDOSDiskFnCx	; (0736)

;
;         Called from:   9663:0388, 070E
; writes a block of data
; @71ch
DiskWriteRec:
		mov     ch,0
		or      cx,cx		; Zero ?
		jnz     WrtBuf		; buffer full, so write it
		ret
WrtBuf: 
		mov     ah,1Ah
		mov     dx,realstart	; 74Bh (9663:074B=8Bh)
		int     21h 		; DOS Services  ah=function 1Ah
					;  set DTA(disk xfer area) ds:dx
		mov     ah,28h  
		mov     dx,fcbDrive	; (9663:010C=0)
		int     21h 		; DOS Services  ah=function 28h
					;  random block write FCB @ds:dx
					;   cx=#records to write,Returns
					;   al=0 ok,cx=actual write recs
		or      al,al 		; Zero ?
		jnz     erdff		; error: disk full
		ret


; General DiskFunction call. CL= major disk function code like open, close, etc.
; @736h
BDOSDiskFnCx:
		push    bx
		push    dx
		push    cx
		xchg	bx,dx			; difference from INTEL dx,bx
		mov     cl,1Ah			; BDOS Set DMA Address to DX
		call    BDOS 			;$-738h
		pop     cx
		pop     dx
		push    dx
		push    cx			; proceed with original call
		call    BDOS 			;$-73Fh
		pop     cx
		pop     dx
		pop     bx
		ret

; @74bh
realstart:
; Offset 6 is the program segment size for COM files (a CP/M
; compatibility item) and the offset of the far call into DOS.
		mov     bx,[FPDOS]		; DOS entry offset FEF0
		mov     sp,bx
		mov     [progsz],bx 		; (9663:0103=0)
		mov     ax,bx
		sub     ax,realstart+100h	;84Bh
		or      ah,ah
		rcl     ah			; Rotate thru carry ECA5
		mov     [halpgfs],ah		; size of HAL in paragraphs??
; print signon 
		mov     ax,2			; should be 80x25 B&W
		int     10h 			; Video display   ah=functn 00h
						;  set display mode in al
		mov     bx,signon
		call    prtstring		; (0243)

; check if filename is on the command line. If you look at ds:5D in the PSP 
; in a debugger, it has "20HAL   COM" in it and not the target file name. If 
; you add a name parameter  after it, it becomes "20HAL   COM.....DOS     MAC" 
; where the "." is ASCII 0. The command tail would normally be at cs:81. 
; Possible artifact of being run inside a debugger...
		mov     al,[FNAME]		; (9663:005D=0) file name
		cmp     al," " 	
		jne     loc83 			; there's a filename, check ext.
		jmp     startup2		; no FNM on command line...

; check for file extension. If no extension was provided, add 'B20' to it.
loc83: 
		mov     bx,FEXT			; (9663:0065=0) extension?
		mov     al,[bx]
		cmp     al," " 
		jne     loc84 			; ext? yes, open file
; add filename extension in FCB to "B20"
		mov	B,[bx],"B"
		inc     bx
		mov	B,[bx],"2" 
		inc     bx
		mov	B,[bx],"0"

; go get file and jump
loc84: 
		call    BDOSOpenFile		; (06AD)
		xor     al,al 
		mov     [data7],al		; (9663:0105=0)
		jmp     startup2		; (02A2)

; @796h
signon:		db      "DEC-20 Downlink to Boca Raton [3"
		db      "00-bps]    9-Apr-81",0Dh,0Ah,0Ah,0
		db      0E9h, 00h, 00h
; @7d0h
; label at the end to get the DS to work
SSTK:		ds	47
HALEND:		db	0
ONE:		equ	1
ZERO:		equ	0
	end
