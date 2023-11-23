# 20HAL
Code reconstruction of the "20HAL" file transfer program found on a diskette containing a pre-release version of MS-DOS 1.0.
Additional details are provided on my web site http://cini.classiccmp.org/hal.htm

The code clean-compiles with MASM 6.11 and produces a binary-identical object file but is inauthentic. I've posted a second
version compiled with Seattle Computer's ASM. There are some syntactical differences, so a lot of editing was required.
This also produces a binary-identical object file.

What is still unknown is the actual blocking/transmission protocol. As noted, the program sends remote commands to a 
DECSYSTEM-10 to facilitate file transfers between Microsoft and IBM. The two programs that resided on the DECSYSTEM 
are not known to exist. One would have transferred binary-type files and the other, text-based files such as plain 
text or MAC (assembler MACro) files.
