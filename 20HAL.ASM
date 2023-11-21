; 20HAL File Downloader version 1.0
; Runs on the 8086 under 86-DOS/MS-DOS
; 21-APR-81

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
;
; Using DEBUG, PSP is:
; cs:0		cd 20		; exit call
; cs:2		00 a0 		;memory ubound
; cs:4		00 		;reserved
; cs:5		9a		; CALL
; cs:6		f0 fe 1d f0	; F01D:FEF0 (*fp)(dos_entry)
; cs:5c		00		;FCB-drive# (0=A)
; cs:5d		'20HAL   '	; filename
; cs:65		'COM'		; extension
; cs:68				; reserved 
; cs:7c				; record_number-seq
; cs:7d				; record_number-rnd
; cs:80				;cnt of bytes on cmd line
; cs:81				;command tail (0dh term)
; cs:ff				; end of PSP

; MS-DOS 1.x FCB
FCB     struc
fcbDrive                db ?
fcbName                 db 8 dup (?)
fcbExtension            db 3 dup (?)
fcbCurrBlockNo          dw ?    ;EXTENT
fcbRecordSize           dw ?    ;RECSIZ
fcbFileSize             dw ?    ;FILESIZ
fcbDRVBP                dw ?    ;DRVBP first/next
fcbDate                 dw ?
fcbTime                 dw ?
fcbSFN                  db ?    ;DEVID
fcbBegClusterNo         dw ?    ;FIRCLUS  start of file cluster number
fcbLSTCLUS              dw ?    ;LSTCLUS  last cluster
fcbCLUSPOS              dw ?    ;position of last cluster
			db ?    ; align 32
fcbRandomRecNo 		dw ?	;  xref 9663:04C4 rnd rec no L
			dw ?	;  xref 9663:04C8 rnd rec no H
FCB     ends


CSEG	segment byte public
	assume cs:CSEG, ds:CSEG
; create labels for accessing the PSP. Maybe a better way, like
; using [cs:EPSP]?
		org 	1
EPSP:
		org	5	; far call to DOS
BDOS:
		org	6	; actual address of DOS entry
FPDOS:
		org	5Ch	; parent FCB in PSP
FFCB:
		org	5dh
FNAME:
		org	65h
FEXT:
		org	80h
FDTA:
		org	100h
start:
		jmp	real_start		; (074B)
off_dos		dw	0			;  xref 9663:02B3, 0325, 0751
data_7		db	0			;  xref 9663:0627, 0649, 0790
cmdcnt		dw	0			;  xref 9663:0643, 064C, 065A
		dw	0
; this is really more a pointer to the end of the "resident"
; portion because real_start is overwritten and used as a buffer
; after initialization. 
sysinit		dw	offset real_start	; 74Bh xref 9663:0343 set in sub_5
myFCB		FCB	<0>			; private FCB

;; @130h
		db	0
CurParseChar	db	0			;  xref 9663:046C, 0486, 049D
		db	0
ext_mac		db 	'MAC'			; CP/M MAC marcoassembler file
ext_com		db	'COM'			; executable
ext_rel		db	'REL'			; relocatable
		db	0,0
secbuf		db	128 dup (0)		; general purpose buffer
filecmdtp	db	0			;  xref 9663:0522
filecmdstr	dw	0			;  xref 9663:02FD, 052F, 053E
hal_pgfs	db	0			;  # of paragraphs in 20HAL xref 9663:0347, 075E
recptr		db	0			;  xref 9663:0363, 06F5 ptr into record buffer
BlockCnt	dw	0			;  xref 9663:02C1, 036F, 0374, 059B
; this breaks into the TOPS-10 monitor; PJ is short for "PJOB" which
; prints the current user information.
t10_cmd1	db	3, 3, 'PJ', 0Dh, 0	; ETX,ETX,P,J,CR,0
;
; the TTY FILL command is a TOPS-10 command to control
; character pacing after certain control codes as specified
; on page 2-275 of the TOPS-10 Operating System Commands Manual.
t10_fillcmd	db	'TTY FILL 3', 0Dh, 0	;  xref 9663:02B8
;
msg_blkcnt	db	8, ' Blocks.', 0Dh, 0Ah, 0	;  xref 9663:0317
msg_disk	db	'DISK', 0Dh		; unsure how used
msg_copdsk	db	' COP DISK='		;  xref 9663:02E8
cmd_buff	dw	12 dup (0)		;  xref 9663:0502, 0556 24-chars
; these are remote command strings. 'R' is the TOPS-10 'run' command so the two
; programs reside on the PDP-10. There is a discussion on the PDP-10
; mailing list relating to ITS that mentions remote file transfer programs
; that seem similar. If you look at the /cpm/cis archive on the WCCDROM,
; there are two programs 'dow12' and 'upload12' which download and
; upload from CompuServe using the CIS A protocol. CIS ran on PDP-10s
; and pre-dated DOS, so using it as a model for this effort wouldn't be a stretch. 
msg_rcpmt	db	'R CPMTXT', 0Dh, 0
msg_rcpml	db	'R CPMLOD', 0Dh, 0

; this routine pads each part of the filename with spaces
; depending on {ch} number of spaces. For example, this is
; used to space-pad a 5-letter file name to 8 characters.
; @21eh
pad_fnm:
		mov	byte ptr [bx],20h	; ' '
		inc	bx
		dec	ch
		jnz	pad_fnm			; Jump if not zero
		retn

; copy a string from dx to [bx]
strcpy_dxbx:					;  xref 9663:0230, 057A
		mov	si,dx
		lodsb				; String [si] to al
		mov	[bx],al
		inc	dx
		inc	bx
		dec	ch
		jnz	strcpy_dxbx		; Jump if not zero
		retn

; send a message string to COM and then  echo it to the screen
; @233h
StringToComm:					;  xref 9663:0240
		mov	al,[bx]
		and	al,7Fh
		jnz	loc_4			; end of string?
		retn				; yes, return
loc_4:	
		mov	cl,al
		call	comms			; (0698)
		inc	bx
		jmp	near ptr StringToComm	; (0233)

; @234h
prt_string:
		mov	al,[bx]
		and	al,7Fh
		jnz	loc_6			; Jump if not zero
		retn
loc_6:						;  xref 9663:0247
		call	print_char		; (0584)
		inc	bx
		jmp	near ptr prt_string	; (0243)

;error messages
; @251h
err_cmd:	db	'Command Error'		;  xref 9663:0289
		db	7, 7, 7, 0		; BEL
err_fnf:	db	'File Not Found', 0
err_df:		db	'Disk Full'
		db	7, 7, 7, 0		; BEL

; This is the error processing code. Disk Full is a fatal error exit.
; @27eh
dferror:					;  xref 9663:06E8
		mov	ax,0			; ah=functn 00h al=mode
		int	10h			; Video display 
		call	prt_string		; (0243)
		jmp	near ptr exithal	; (029D) codes as e9.14.00

; Bad command and file not found are non-fatal errors, so
; print an error and return to the command loop. BX for FNF
; error message is set in the caller.
cmderror:					;  xref 9663:04D7, 04E8, 051F, 054F
		mov	bx,offset err_cmd	; (9663:0251='Command Error')
fnferror:					;  xref 9663:06C5
		call	prt_string		; (0243)
		call	print_crlf		; (057D)
		jmp	near ptr CmdLoop	; (02B3)

; we get here from the ^C test in the keyboard loop. It
; already printed '^' and al has 'C', so print it and exit
exit_ctlc:					;  xref 9663:0434
		call	print_char		; (0584)
; exit by way other than ^C
loc_11:						;  xref 9663:063D, 0656
		mov	ax,0			; ah=functn 00h al=mode
		int	10h			; Video display 
exithal:					;  xref 9663:0286
		call	print_crlf		; (057D)
		int	20h			; DOS program terminate


;��������������������������������������������������������������������������
; startup initialization continues here from real_start
; @2a2h
startup2:					;  xref 9663:0774, 0793
		mov	ax,43h			; reset to 300,N81
		mov	dx,0			; port= COM1
		int	14h			; RS-232
; WaitForIdle polls the COM port and waits for it to be 
; ready. Once ready, print CMD1 followed by CMD2.
; The string ETX,ETX,"PJ",CR is interesting because in
; TOPS-10, ^C interrupts the current program and returns to
; the TOPS-10 command prompt. The only command close to "PJ" 
; is PJOB, which prints the current job ID, user name, 
; user ID and terminal ID. If the next step is to send a
; TTY FILL 3 command, breaking into the TOPS-10 monitor
; would make sense.
		call	WaitForIdle		; (03CF)
		mov	bx,offset t10_cmd1	; (9663:01C5=3) 3,3,"PJ",0D,0
		call	StringToComm		; (0233)

; This is the top of the command loop
CmdLoop:					;  xref 9663:0292, 032B
		mov	sp,word ptr cs:off_dos	; (9663:0103=0)
		mov	bx,offset t10_fillcmd	; TOPS-10 TTY FILL
		call	StringToComm		; (0233)

; strings printed to remote system, so continue. Check for
; a filename on the command line. Maybe this is how it
; processes a command script file?
		mov	bx,0
		mov	BlockCnt,bx		; (9663:01C3=0)
;		mov	al,[ds:5dh]		; filename
		mov	al,[myFCB.fcbName]
		cmp	al,' '			; is FCB blank?
		jne	CmdInner		; no, continue

; look for ENQ (^E) to start direct command input
		mov	ch,5			; ENQ??
		call	WaitForENQ		; (032E)
; @2d1h
CmdInner:					;  xref 9663:02CA
		call	WaitForIdle		; (03CF) wait for serial line
		call	GetCommand		; (0402) print "*" prompt and process
		call	ParseCmdLine		; (0449) bx=cmd input buffer
		call	LookForEq		; (04D0) dx=second cmd
		call	WhatFileType		; (0519) sets xfer string 
						;    filecmdstr set dx=*extension al=type
		call	CreateFileOW		; (06C8) create file
		call	IsDiskCmd		; (0502)
		jz	DiskCmd			; DISK is param2, so continue

; This sends a remote copy command to the remote system. A download request
; command line is "dest.mac=source.mac-A", so 20HAL sends 'COP DISK='
; with the source file name "source.mac". 
		mov	bx,offset msg_copdsk	; (9663:01E8=' COP DISK=')
		jz	loc_16			; print only if not disk cmd
		call	StringToComm		; (0233)

; Sits here in a loop waiting for the TOPS-10 monitor prompt to return
; after issuing the system copy command. While idling it prints a
; block on the screen for each pass.
loc_16:	
		call	com_read		; (0666)
loc_17:
		call	com_read		; (0666)
		call	print_char		; (0584)
		cmp	al,'.'			; '.'
		jne	loc_17			; Jump if not equal

; Copy command done (monitor prompt received) so send the file
; transfer command based on the file type.		
; @2fdh	
DiskCmd:					;  xref 9663:02E6
		mov	bx,filecmdstr		; (9663:01BF=0)
		call	StringToComm		; (0233)
		call	print_crlf		; (057D)
		call	WaitForIdle		; (03CF)
		mov	cl,0Dh			; Is this the sync char?
		call	com_write		; (06A1)
		mov	al,' '			; ' '
		call	print_char		; (0584)
		call	BlockXfer		; (0340)
		mov	bx,offset msg_blkcnt	; (9663:01D7='  Blocks.')
		call	prt_string		; (0243)
		call	WaitForIdle		; (03CF)
		mov	cl,0Dh			; xfer over?
		call	com_write		; (06A1)
		mov	bx,word ptr off_dos	; (9663:0103=0)
		mov	sp,bx
		jmp	near ptr CmdLoop	; (02B3) go to the beginning

;��������������������������������������������������������������������������
;                              SUBROUTINE
;
;         Called from:   9663:02CE
;��������������������������������������������������������������������������
; Enters with ch=5 so this loop tests for ENQ (^E)
; @32eh
WaitForENQ:
		call	rxloop			; (05DB)
		cmp	al,ch			; ENQ?
		jne	loc_20			; Jump if not equal
		jmp	print_crlf		; (057D) returns to 02D1
loc_20:	
		mov	cl,al
		call	com_write		; (06A1)
		jmp	near ptr WaitForENQ		; (032E) loop

;���� External Entry into Subroutine ��������������������������������������
;
;         Called from:   9663:0314
; This is the actual file transfer code. It sends "B" as a "ready" char and 
; beeps, and sits in this B/beep loop until characters are received.
; @340h
BlockXfer:
		mov	bx,offset real_start	;74Bh
		mov	sysinit,bx		; (9663:010A=74Bh)
		mov	ch,hal_pgfs		; (9663:01C1=0)
		mov	cl,0

XferLoop:					;  xref 9663:039F, 03CC
		push	cx			; 
		push	bx			; DTA
		mov	dx,81h			; record size 129b

XferLoop1:					; inner loop
		call	com_read		; (0666)
		jnz	GetBlock		; char, so start collecting bytes
		jmp	CheckBuf		; (06F5) sends NAK (^U) and returns to 
						; SendSynch

; Block size DX is set above -- 128 bytes plus terminator or
; maybe a block number (max 255) followed by 128 bytes. BX 
; is the disk transfer buffer which is recycled space at the end.
; It's not clear if there is any block separation or if it
; just relies on character counting.
; @35ah
GetBlock:					;  xref 9663:0355
		mov	[bx],al			; save char in buffer
		inc	bx			;*b++
		xor	al,dh			; dh should be 0
		mov	dh,al
		dec	dl			; dl= remaining chars in buf?
		mov	recptr,dl		; save # chars left in record
		jnz	XferLoop1		; more space? continue
; record full
		or	al,dh			; zero?
		jnz	SendSynch		; send synch to resend block?
		xchg	dx,bx			; count the block
		mov	bx,BlockCnt
		inc	bx
		mov	BlockCnt,bx		; (9663:01C3=0)
		xchg	dx,bx
		dec	bx
		pop	cx
		pop	cx
		inc	cl
		push	cx
		mov	al,cl
		cmp	al,ch
		pushf				; Push flags
		push	ax
		jnz	loc_25			; done with file, get more?
		call	DiskWriteRec		; (071C) write record and get next

loc_25:						;  xref 9663:0386
		push	bx
		call	PrintBlkCnt		; (0596)
		pop	bx
		mov	al,' '			; ' '
		call	print_char		; (0584)
		mov	cl,'A'			; 'A'
		call	com_write		; (06A1)
		pop	ax
		popf
		pop	cx
		jz	BlockXfer		; restart next block
		jmp	near ptr XferLoop	; (034D) loop in current block

; this sounds the bell, prints backspace and ^C, so I suspect it's the
; "ready for block" process.
; @3a2h
SendSynch:					;  xref 9663:036B, 06FC
		mov	al,7			; BEL
		call	print_char		; (0584)
		inc	al			; BS
		call	print_char		; (0584)
		mov	al,3			; this is a loop of 256*256*3
		mov	cx,0
loc_27:	
		dec	ch
		jnz	loc_27	
		dec	cl
		jnz	loc_27
		dec	al
		jnz	loc_27
		call	WaitForIdle		; (03CF)
		mov	cl,'B'			; 'B'
		mov	al,cl
		call	print_char		; (0584)
		call	com_write		; (06A1)
		pop	bx
		pop	cx
		jmp	XferLoop		; (034D)

;���� External Entry into Subroutine ��������������������������������������
;
;         Called from:   9663:02AA, 02D1, 0307, 031D, 03BD
; @3cfh
WaitForIdle:
		push	bx
		push	dx
		push	cx
		mov	cx,0
loc_28:						;  xref 9663:03F6
		mov	al,1
; looks like this is some sort of wait loop for 256*256
loc_29:						;  xref 9663:03D9, 03DD, 03E1
		dec	ch
		jnz	loc_29			; Jump if not zero
		dec	cl
		jnz	loc_29			; Jump if not zero
		dec	al
		jnz	loc_29			; Jump if not zero

; get line status
		mov	ah,3
		mov	dx,0
		int	14h			; RS-232   dx=com1, ah=func 03h
						;  get status al=modem, ah=line
		and	ah,1			; RDR?
		jz	loc_30			; Rx data available

		mov	ah,2
		mov	dx,0
		int	14h			; RS-232   dx=com1, ah=func 02h
						;  get char al, ah=return status
; line still not ready, so wait again
		jmp	short loc_28		; (03D5)
; line is idle and ready, so return
loc_30:						;  xref 9663:03ED
		pop	cx
		pop	dx
		pop	bx
		retn


; Command line processor
; @3fch
GetCommandTop:					;  xref 9663:0439
		call	print_char		; (0584)
		call	print_crlf		; (057D)
;         Called from:   9663:02D4
; seems like the only way to get the * prompt is from hitting
; ^E
GetCommand:
		mov	al,'*'			; '*'
		call	print_char		; (0584)
		mov	bx,offset secbuf	; 128-byte command line buffer
CmdFetchChar:					;  xref 9663:0424, 043E
		call	rxloop			; (05DB)
		call	toupper			; (061A)
		cmp	al,0Dh			; CR?
		je	GotCmdLine		; yes
		cmp	al,0Ah			; LF?
		je	loc_33			; yes
		cmp	al,' '			; space
		je	loc_33			; yes
		jc	prt_ctrl		; print other control chars
		mov	[bx],al			; save it
		inc	bx			; next buffer slot

; process characters LF and print SPACE
loc_33:	
		call	print_char		; (0584)
		jmp	near ptr CmdFetchChar	; (040A)

; print/expand control character
; @427h
prt_ctrl:					;  xref 9663:041C
		push	ax
		mov	al,'^'			;5Eh '^'
		call	print_char		; (0584)
		pop	ax
		add	al,'@'			; ASCII adjust ctrl_char
		cmp	al,'C'			; 43h 'C' control-C?
		jne	NotCtlC			; Jump if not equal
		jmp	exit_ctlc		; (0295) ^C, so exit

; check other control characters (only one is ^U to cancel command)
NotCtlC:
		cmp	al,'U'			; 55h ^U
		je	GetCommandTop		; cancel command and restart
		call	print_char		; (0584)
		jmp	near ptr CmdFetchChar	; (040A) top of loop

; CR received, so return command line to parent
GotCmdLine:					;  xref 9663:0412
		mov	[bx],al
		mov	bx,offset secbuf	; reset BX to top of buffer
		jmp	print_crlf		; (057D)

;���� External Entry into Subroutine ��������������������������������������
;
;         Called from:   9663:02D7
; Parse command line. Enters with BX= buffer set in GetCommand.
; @449h
ParseCmdLine:
		push	bx
		push	dx
		push	cx
		xchg	dx,bx			; save *cmd to DX
;		mov	bx,offset tempFCB1	; (9663:010C=0)
		mov	bx,offset [myFCB.fcbDrive]	; bb.0c.01
		inc	dx
		mov	si,dx
		lodsb				; String [si] to al
		dec	dx
		cmp	al,':'			; ':'
		mov	al,0
		jnz	loc_37			; Jump if not zero
		mov	si,dx
		lodsb				; String [si] to al
		inc	dx
		inc	dx
		sub	al,'@'			; '@' ASCII adjust
loc_37:						;  xref 9663:045A
		mov	[bx],al
		inc	bx
; the above looks for a drive letter and if one is
; specified, it gets the letter, determines the drive 
; number for the FCB (0=default; 1=A) and then stores it in
; the FCB. The next 11 characters are a file name or
; possibly just "DISK", resulting in a command like:
; "A:=DISK-"
;
; get the next 8 characters which is assumed to be a file name.
; @466h
		mov	ch,8			; 8 character loop?
loc_38:						;  xref 9663:0480
		mov	si,dx
		lodsb				; String [si] to al
		inc	dx
		mov	CurParseChar,al		; (9663:0131=0)
		cmp	al,'.'			; '.' = file extension so short FNM
		je	loc_40
		cmp	al,'='			; '=' check for second command
		je	loc_40
		cmp	al,'!'			; '!'
		jb	loc_40			; <1Dh is space and control chars
		mov	[bx],al			; save the char
		inc	bx
		dec	ch
		jnz	loc_38			; not done yet, so loop

; done with first 8 characters, so check for a file extension or
; a secondary command marker.
; @482h
loc_39:						;  xref 9663:0493
		mov	si,dx
		lodsb				; String [si] to al
		inc	dx
		mov	CurParseChar,al		; (9663:0131=0)
		cmp	al,'.'			; '.'
		je	loc_41
		cmp	al,'='			; '='
		je	loc_41
		cmp	al,'!'			; '!'
		jae	loc_39			; keep parsing
		jmp	near ptr loc_41		; (049B)

; got some sort of delimiter so check things a bit more
loc_40:						;  xref 9663:0471, 0475, 0479
		call	pad_fnm			; (021E)
; '.' and '=' get here. If there's a '.' we assume an extension exists
; and then copy it to the buffer. 
loc_41:						;  xref 9663:048B, 048F, 0495
		mov	ch,3
		mov	al,CurParseChar		; (9663:0131=0)
		cmp	al,'.'			; '.'
		je	loc_42			; Jump if equal
		mov	dx,132h			; this points to file extensions - 1
loc_42:						;  xref 9663:04A2, 04B4
		mov	si,dx
		lodsb				; String [si] to al
		cmp	al,'='			; '=' then skip rest of extension
		je	loc_43			; extension is specified and we have '='
						;   so skip copying a default.
		inc	dx
		mov	[bx],al
		inc	bx
		dec	ch
		jnz	loc_42			; Jump if not zero
		jmp	near ptr loc_44		; (04BC) codes e9.03.00
loc_43:						;  xref 9663:04AC
		call	pad_fnm			; (021E)

;ds:1 is the exit interrupt number in the PSP (CD 20). In the
; caller, ch is used as a loop variable that is used to check
; file extensions against MAC, COM, REL (note the move absolute
; of 132h which is ds:132h).
; @4bch
loc_44:						;  xref 9663:04B6
		mov	cl,0
		mov	[bx],ch
		mov	byte ptr ds:[bx+EPSP],ch ; (9663:0001=0)
;		mov	tempFCBrecL,cx		; (9663:012C=0)
		mov	[myFCB.fcbRandomRecNo],cx
;		mov	tempFCBrecH,cx		; (9663:012E=0)
		mov	[myFCB.fcbRandomRecNo+2],cx
;
		pop	cx
		pop	dx
		pop	bx
		retn

;���� External Entry into Subroutine ��������������������������������������
;
;         Called from:   9663:02DA
; on entry, BX points to the command buffer. Returns with dx pointing to a
; "second command" buffer. {BX popped at end of ParseCmdLine.}
; @4d0h
LookForEq:
		mov	al,[bx]
		inc	bx
		cmp	al,0Dh			; EOL? {empty command line}
		jne	loc_46			; no, keep processing
		jmp	cmderror		; (0289) process CR
loc_46:	
		cmp	al,'='			; '='
		jne	LookForEq		; no, loop back

; so far, the command line is "[d:]file.ext=" or "d:=" so get up to 
; 24-bytes for whatever is after. '=' with nothing is ERR				
		mov	dx,offset cmd_buff	; 1F2h 24-char buffer?
loc_47:						;  xref 9663:04F3
		mov	al,[bx]
		inc	bx
		cmp	al,0Dh
		jne	loc_48			; Jump if not equal
		jmp	cmderror		; (0289)

; parse the second part of the command; "-" is a flag for the file
; type A, B or R. Command is copied from the input buffer in BX to DX.
loc_48:						;  xref 9663:04E6
		cmp	al,'-'			; '-'
		je	loc_49			; Jump if equal
		mov	di,dx
		stosb				; Store al to es:[di]
		inc	dx
		jmp	near ptr loc_47		; (04E1) e9.eb.ff

; second terminator, so replace '-' with a <CR><0>
loc_49:						;  xref 9663:04ED
		mov	al,0Dh
		mov	di,dx
		stosb				; Store al to es:[di]
		inc	dx
		xor	al,al			; Zero register
		mov	di,dx
		stosb				; Store al to es:[di]
		retn

;���� External Entry into Subroutine ��������������������������������������
;
;         Called from:   9663:02E3
; test to see if "DISK" command received? 
; @502h
IsDiskCmd:					;  xref 9663:02E3
		mov	bx,offset cmd_buff	; (9663:01F2=0)
		mov	dx,offset msg_disk	;1E3h msg_disk??
		mov	ch,5
loc_50:						;  xref 9663:0516
		mov	si,dx
		lodsb				; String [si] to al
		cmp	al,[bx]
		je	loc_51			; Jump if equal
		retn
loc_51:						;  xref 9663:050F
		inc	bx
		inc	dx
		dec	ch
		jnz	loc_50			; Jump if not zero
		retn

;���� External Entry into Subroutine ��������������������������������������
;
;         Called from:   9663:02DD
; looks like this figures out what kind of file is being sent? Called with
; BX= command input buffer pointing at next char after parsing second part
; of command. DI points to second command.
; @519h
WhatFileType:
		mov	al,[bx]
		cmp	al,0Dh			; EOL? {empty command line}
		jne	loc_52			; no, process command
		jmp	cmderror		; (0289) yes, exit

; setup registers for the specific request type. BX contains
; return location which is pushed on the stack and then popped
; into IP on the RETN after file type parameters are set.
loc_52:						;  xref 9663:051D
		mov	filecmdtp,al		; (9663:01BE=0)
		mov	bx,offset loc_55a	;552h "error" address
		push	bx

; "A" = MAC file
		mov	bx,offset msg_rcpmt	;20Ah CPMTTY
		mov	dx,offset ext_mac	;133h
		mov	filecmdstr,bx		; (9663:01BF=0)
		cmp	al,'A'			;41h 'A' CPMTXT
		jne	loc_53			; Jump if not equal
		retn

; "B" = COM file
loc_53:						;  xref 9663:0535
		mov	bx,offset msg_rcpml	;214h CPMLOD
		mov	dx,offset ext_com	;136h
		mov	filecmdstr,bx		; (9663:01BF=0)
		cmp	al,'B'			; 42h B
		jne	loc_54			; Jump if not equal
		retn

; "R" = REL file
loc_54:						;  xref 9663:0544
		mov	dx,offset ext_rel	;139h
		cmp	al,'R'			; 52h 'R'
		jne	loc_55			; not A, B, or R
		retn				; do a return to loc_55a

loc_55:						;  xref 9663:054C
		jmp	cmderror		; (0289)

; We get here by pushing the return address on the stack
; (the "push bx" in loc_52) and the retn in 
; loc_54 which pops it into IP. Execution comes here with:
;
;	al= transfer command A, B, or R
;	bx= TOPS-10 transfer command based on file type
;	dx= offset to related extension
; @552h
loc_55a:
		cmp	al,'A'			; 'A'
		jne	loc_57			; COM or REL

; get here if it's a type "A" (MAC) file (so, non-executable)
; reset BX to beginning of the second-command buffer used in
; loc_47.
		mov	bx,offset cmd_buff	; (9663:01F2=0)
; find the end of the buffer and terminate it with /N<0>
loc_56:	
		inc	bx
		mov	al,[bx]
		cmp	al,0Dh			; EOL?
		jne	loc_56			; no, loop
; terminate line with "/N<CR>0". Almost looks like a C-style
; string termination except that would be '\n0'
		mov	byte ptr [bx],'/'	; 2Fh '/'
		inc	bx
		mov	byte ptr [bx],'N'	; 4Eh  'N'
		inc	bx
		mov	[bx],al			; put <CR>
		inc	bx
		mov	byte ptr [bx],0
; process COM/REL. This should return to 02DD if there's already
; an extension, otherwise copy the extension into the FCB.
loc_57:						;  xref 9663:0554
;		mov	bx,offset tempFCB1_ext	; (9663:0115=0)
		mov	bx,offset [myFCB.fcbExtension]	;bb.15.01
		mov	al,[bx]
		or	al,al			; Zero ?
		jz	padext
		retn

; this will space-pad the file extension if needed.
padext:						;  xref 9663:0575
		mov	ch,3
		jmp	strcpy_dxbx		; (0227)


;���� External Entry into Subroutine ��������������������������������������
;
;         Called from:   9663:028F, 029D, 0304, 03FF
; @57dh
print_crlf:
		mov	al,0Dh
		call	print_char			; (0584)
		mov	al,0Ah

; Although Sourcer decompiles it with a negative offset to the 
; current PC, it's really a "CALL 0005" to the PSP which is the CP/M
; equivalent to calling the BDOS. Function 6 is
; the call to Direct Console I/O. CL= BDOS function; DL= character.
print_char:
		push	bx
		push	dx
		push	cx
		push	ax
		pushf				; Push flags
		mov	cl,6
		mov	dl,al
		call	near ptr BDOS		;$-588h
		popf				; Pop flags
		pop	ax
		pop	cx
		pop	dx
		pop	bx
		retn


;��������������������������������������������������������������������������
;                              SUBROUTINE
;
;         Called from:   9663:038C
;��������������������������������������������������������������������������
; @596h
PrintBlkCnt:
		mov	al,0Dh
		call	print_char		; (0584)
		mov	bx,BlockCnt		; (9663:01C3=0)
		mov	cl,0
		mov	dx,3E8h			;
		call	BX2DEC			; (05BC)
		mov	dx,64h			; 'd'??
		call	BX2DEC			; (05BC)
		mov	dx,0Ah
		call	BX2DEC			; (05BC)
		mov	al,'0'
		add	al,bl
		mov	ch,al
		jmp	near ptr loc_62		; (05D4) eb.18.00

; routine BX2DEC - print BX in decimal
BX2DEC:	
		mov	ch,'/'
loc_61:						;  xref 9663:05C2
		inc	ch			; '0' 30h
		sub	bx,dx			; bx=BlockCnt from PrintBlkCnt
		jnc	loc_61			; Jump if carry=0
		add	bx,dx
		mov	al,ch
		sub	al,'0'			; '0'
		jnz	loc_62			; Jump if not zero
		cmp	al,cl
		jne	loc_62			; Jump if not equal
		mov	ch,' '			; ' '
		jmp	short loc_63		; (05D6)
loc_62:						;  xref 9663:05B9, 05CA, 05CE
		inc	cl
loc_63:						;  xref 9663:05D2
		mov	al,ch
		jmp	near ptr print_char	; (0584) exits through print_char


;��������������������������������������������������������������������������
;                              SUBROUTINE
;
;         Called from:   9663:032E, 040A
;��������������������������������������������������������������������������
; looks like this gets a character from the first serial channel if 
; available. If not, polls the keyboard for a character.
; @5dbh
rxloop:
		push	cx
		push	dx
		push	bx
loc_64:	
		mov	ah,3			; ah=port status
		mov	dx,0			; dx=port_num 0...3
		int	14h			; RS-232 get status al=modem, ah=line
		and	ah,1			; ah=LSR  b.1=RDR
		jz	loc_65			; no char, move on
		mov	ah,2			; ah=2 get char
		mov	dx,0			; port 0
		int	14h			; RS-232 get char al, ah=return status
		and	ah,1Eh			; any line errors? (brk,frm,pty,OR)
		jnz	loc_64			; line error, try again.
		and	al,7Fh			; no line error...make 7-bit
		cmp	al,7Fh			; DEL?
		je	loc_64			; yes, DEL key so get another
		call	print_char		; (0584) print it...
		jmp	near ptr loc_64		; (05DE) ...and loop e9.dc.ff
loc_65:						;  xref 9663:05E8
;		mov	al,[ds:5dh]		; filename
		mov	al,[myFCB.fcbName]
		cmp	al,' '
		jne	loc_68			; FCB has something in it so go

		mov	cl,6			; BDOS call Direct Console I/O
		mov	dl,0FFh			; SubFx=get_char_nonblock
		call	near ptr BDOS		;$-608h
		or	al,al			; Zero ?
		jz	loc_64			; no keyboard char waiting, loop
		and	al,7Fh			; force 7-bit ASCII
		pop	bx			; and return
		pop	dx
		pop	cx
		retn

;convert LC to UC
; @61ah
toupper:
		cmp	al,'a'			; 'a'
		jae	loc_66			; Jump if above or =
		retn
loc_66:						;  xref 9663:061C
		cmp	al,'{'			; '{'
		jb	loc_67			; Jump if below
		retn
loc_67:						;  xref 9663:0621
		xor	al,20h			; ' '
		retn

; get here from comm loop if the FCB has a filename in it
; so if the FCB is valid, it assumes that a file transfer
; is in progress and we are grabbing records from disk.
loc_68:						;  xref 9663:0607, 0660
		mov	al,data_7		; count (9663:0105=0)
		dec	al
		jns	loc_70			; not negative?

		mov	cl,14h			; BDOS 14h ReadNextRecord
;		mov	dx,5Ch			; FCB
		mov	dx,offset FFCB		; pointer to our FCB
;		mov	bx,80h			; DTA
		mov	bx,offset FDTA 		; pointer to our DTA
		call	BDOS_DiskFnCx		; (0736)
		add	al,0FFh			; 0=success
		jnc	loc_69			; Jump if carry=0
		jmp	loc_11			; error exit (0298)
loc_69:						;  xref 9663:063B
		mov	bx,80h			; DTA?
;		mov	bx,offset FDTA		; ??
		mov	cmdcnt,bx		; index into DTA (9663:0106=0)
		mov	al,7Fh			; default char
loc_70:						;  xref 9663:062C
		mov	data_7,al		; save char (9663:0105=0)
		mov	bx,cmdcnt		; DTA index (9663:0106=0)
		mov	al,[bx]			; get char
		cmp	al,1Ah			; ^Z end of record?
		jne	loc_71			; no, keep parsing
		jmp	loc_11			; (0298) exit program

loc_71:						;  xref 9663:0654
		inc	bx			; next char on command line
		mov	cmdcnt,bx		; (9663:0106=0)
		or	al,al			; Zero ?
		js	loc_68			; yes, get next record
		pop	bx
		pop	dx
		pop	cx
		retn

; @666h
com_read:
		push	dx
		push	cx
		mov	cl,0
		mov	ch,80h
		call	com_stat		; (0680)
		pop	cx
		pop	dx
		jnz	loc_72			; Jump if not zero
		retn
loc_72:						;  xref 9663:0671
		push	dx
		mov	ah,2			; RS-232 get char
		mov	dx,0			; port 0
		int	14h			; RS-232  get char al, ah=return status
		inc	ah
		pop	dx
		retn

; @680h
com_stat:					;  xref 9663:0691, 0695
		mov	ah,3
		push	cx
		mov	dx,0
		int	14h			; RS-232   dx=com1, ah=func 03h
						;  get status al=modem, ah=line
		pop	cx
		and	ah,1
		jz	loc_74			; Jump if zero
		retn

loc_74:						;  xref 9663:068C
		dec	cl
		jnz	com_stat		; Jump if not zero
		dec	ch
		jnz	com_stat		; Jump if not zero
		retn

; @698h
comms:
		call	com_write		; (06A1)
		call	com_read		; (0666)
		jmp	print_char		; (0584)

; @6a1
com_write:
		push	dx
		mov	ah,1
		mov	dx,0
		mov	al,cl
		int	14h			; RS-232   dx=com1, ah=func 01h
		pop	dx			;  write char al, ah=retn status
		retn

; @6ad
BDOS_OpenFile:
		mov	cl,0Fh			; BDOS Open File
						; Open returns al=0-3 or ffh=error
;		mov	dx,5Ch			; FCB
		mov	dx,offset FFCB
;		mov	bx,80h			; DTA
		mov	bx,offset FDTA
		call	BDOS_DiskFnCx		; (0736)
		inc	al			; 0ffh+1=0 for error
		jz	loc_75			; file not found, so print error
		retn
loc_75:
;		mov	byte ptr [ds:5dh],20h	; mark FCB as invalid
		mov	byte ptr [myFCB.fcbName],20h
		mov	bx,offset err_fnf	; file not found 262h
		jmp	fnferror		; (028C)



;��������������������������������������������������������������������������
;                              SUBROUTINE
;
;         Called from:   9663:02E0
;��������������������������������������������������������������������������
; This routine opens a file in OW (overwrite) mode.
; @6c8
CreateFileOW:
		mov	dx,offset real_start	;74Bh real_start (end of code)
		mov	cl,1Ah			; BDOS Set_DMA_Address DX
		call	near ptr BDOS		;$-6c8h
;		mov	dx,offset tempFCB1	;10Ch
		mov	dx, offset [myFCB.fcbDrive]
		push	dx
		mov	cl,13h			; BDOS Delete_File
		call	near ptr BDOS		;$-6d1h
		pop	dx
		push	dx
		mov	cl,16h			; BDOS Create_File
		call	near ptr BDOS		;$-6d8h
		pop	dx
		inc	al
		jnz	open_ok			; Jump if not zero
er_dff:						;  xref 9663:06F2, 0733
		mov	bx,offset err_df	; disk full 271h
		jmp	dferror			; (027E) exit with DF
open_ok:
		mov	cl,0Fh			; BDOS Open_File
		call	near ptr BDOS		;$-6e8h
		inc	al
		jz	er_dff			; disk full
		retn

; looks like this checks how full the buffer is and either sends
; a sync character if empty or flushes it if full.
; @6f5h
CheckBuf:					;  xref 9663:0357
		mov	al,recptr		; (9663:01C2=0) get curr pos in buffer
		sub	al,80h
		jz	FlushBuf		; buffer full? write it
		jmp	SendSynch		; (03A2) sends synch and loop

; record buffer full, so write it.
; @6ffh
FlushBuf:
		mov	cl,15h			; send NAK to the channel
		call	com_write		; (06A1)
		call	com_read		; (0666)
		pop	bx
		pop	cx
; @709h
		cmp	cl,0			;82.f9.00
		je	loc_80			; Jump if equal
		call	DiskWriteRec		; (071C)

; done writing records, so close and flush the file.
loc_80:						;  xref 9663:070C
;		mov	dx,offset tempFCB1	;10Ch
		mov	dx,offset [myFCB.fcbDrive]
		mov	bx,offset real_start	; 74Bh
		mov	cl,10h			; BDOS Close_File
		jmp	near ptr BDOS_DiskFnCx	; (0736)

;��������������������������������������������������������������������������
;                              SUBROUTINE
;
;         Called from:   9663:0388, 070E
;��������������������������������������������������������������������������
; writes a block of data
; @71ch
DiskWriteRec:
		mov	ch,0
		or	cx,cx			; Zero ?
		jnz	WrtBuf			; buffer full, so write it
		retn
WrtBuf:	
		mov	ah,1Ah
		mov	dx,offset real_start	; 74Bh (9663:074B=8Bh)
		int	21h			; DOS Services  ah=function 1Ah
						;  set DTA(disk xfer area) ds:dx
		mov	ah,28h
;		mov	dx,offset tempFCB1	; (9663:010C=0)
		mov	dx,offset [myFCB.fcbDrive]
		int	21h			; DOS Services  ah=function 28h
						;  random block write FCB @ds:dx
						;   cx=#records to write,Returns
						;   al=0 ok,cx=actual write recs
		or	al,al			; Zero ?
		jnz	er_dff			; error: disk full
		retn


; Looks like a general DiskFunction call. Called with:
;	BX= *FCB
;	CL= major function code
;	DX= *DTA [PSP:80h]	
; @736h
BDOS_DiskFnCx:
		push	bx
		push	dx
		push	cx
		xchg	dx,bx
		mov	cl,1Ah			; BDOS Set DMA Address to DX
		call	BDOS			;$-738h
		pop	cx
		pop	dx
		push	dx
		push	cx			; proceed with original call
		call	BDOS			;$-73Fh
		pop	cx
		pop	dx
		pop	bx
		retn

;resident_end	equ	$

;��������������������������������������������������������������������������
;��������������������������������������������������������������������������
; this area recycled as a buffer area after initialization
; @74bh
real_start:
;		mov	bx,[cs:6]
		mov	bx,word ptr [FPDOS]	; DOS entry offset FEF0
		mov	sp,bx
		mov	word ptr off_dos,bx	; (9663:0103=0)
		mov	ax,bx
		sub	ax,(real_start+100h)	;84Bh
		or	ah,ah
		rcl	ah,1			; Rotate thru carry ECA5
		mov	hal_pgfs,ah		; size of HAL in paragraphs??
; print signon 
		mov	ax,2
		int	10h			; Video display   ah=functn 00h
						;  set display mode in al
		mov	bx,offset signon
		call	prt_string		; (0243)

; check if filename is on the command line? Interestingly, if
; you look at ds:5D in the PSP, it has "20HAL   COM" in it. If you
; add a name parameter after it, it becomes "20HAL   COM.....DOS     MAC"
; where the "." is ASCII 0. The command tail would normally
; be at cs:81. Maybe it's an artifact of being run inside a
; debugger.
;		mov	al,[5Dh]		; (9663:005D=0)
		mov	al,byte ptr [FNAME]	; is command line empty?
		cmp	al,' '			; ' '
		jne	loc_83			; there's a filename, check ext.
		jmp	startup2		; no FNM on command line...

; check for file extension. If no extension was provided, 
; add 'B20' to it.
loc_83:	
;		mov	bx,65h			; (9663:0065=0) extension?
		mov	bx,offset FEXT
		mov	al,[bx]
		cmp	al,' '			; ' '
		jne	loc_84			; ext? yes, open file
; add filename extension in FCB to "B20"
		mov	byte ptr [bx],'B'	; 'B'
		inc	bx
		mov	byte ptr [bx],'2'	; '2'
		inc	bx
		mov	byte ptr [bx],'0'	; '0'

; go get file and jump
loc_84:	
		call	BDOS_OpenFile		; (06AD)
		xor	al,al
		mov	data_7,al		; (9663:0105=0)
		jmp	startup2		; (02A2)

; @796h
signon:		db	'DEC-20 Downlink to Boca Raton [3'	;  xref 9663:0767
		db	'00-bps]    9-Apr-81',0Dh,0Ah,0Ah,0
		db	0E9h, 00h, 00h
; @7d0h
; padding
		db	47 dup (0)
;		db	(offset 20halend - $) dup (0)
halend:		db	0
; should end @7ff
CSEG	ends
end	start