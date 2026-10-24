; hello.asm
; hello world

section .data
	; i belive this is that __data__ section that GCC would create???
	msg db "Hello World!", 10
	msglen equ $ - msg	; curr pos. - start

section .text
	; i believe this is the __text__ section that GCC would create???
	global _start	; start variable to the linker

_start:
	mov eax, 1	; print message to screen '1' is a syscall to 'write'
	; 'eax' is the register linux looks for a syscall oh my fucking word that makes so much fucking sense!!
	mov edi, 1	; arg 'edi' register used for the first piece of info. '1' being stdout on linux
	lea rsi, [rel msg]	; 'lea' load effective address. 'rsi' used for 2nd arg. '[rel msg]' find memory location of 'msg' 
				; variable 'rel' meaning relative addressing

	mov edx, msglen		; 'edx' is the argument used for the 3rd argument
	syscall		; let the kernel execute this program???

	; now onto gracefully exiting this program

	mov eax, 60	; 'eax' remember the register that linux looks for syscall. '60' being a constant for exit
	xor edi, edi	; 'edi' being 1st arg register. XOR (a, a) = 0. '0' constant for linux meaning exit without failure
	syscall
