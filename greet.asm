; greet.asm
; ask stdin for a name. read it to the stack buffer. printing "Hello $NAME"

BUFSIZE equ 64		; size of name stack buffer (constant in .data I think)

section .data
	prompt db "Please enter your name", 10
	prompt_len equ $ - prompt
	hello db "Hello "
	hello_len equ $ - hello

section .text
	global _start

_start:
	; first we gotta reserve stack space manually
	sub rsp, BUFSIZE	; 'sub' subtract. 'rsp' being the stack ptr. linux sets up 'rsp' to the stack ptr.
				; BUFSIZE manually subtracted from stack size of this linux process.
				; this results in `rsp = rsp - 64`

	; now, we are effectively doing this: `write(1, prompt, promtp_len)` to print the prompt
	mov eax, 1		; 'mov' copy src into dest. 'eax' being the destination
				; 'rax' now looks something like this: `FFFFFFFF 00000001`
	mov edi, 1		; 'rdi' now also = 1
				; 'rdi' now = `00000000 00000001`
	lea rsi, [rel prompt]	; 'load effective address'
				; works our address + puts that address into destination 'rsi'
				; 'rsi' 2nd syscall arg
	mov edx, prompt_len	; 'rdx' is the 3rd arg of the syscall
	syscall			; switches from this programme to linux kernel

	; read(0, buffer, BUFSIZE);
	; read name from stdin
	xor eax, eax		; 'rax' = 0
	xor edi, edi		; 'rdi' = 0
	mov rsi, rsp		; copies 'rsp' into rsi (i.e. 'rsp' is the stack ptr, 'rsi' is syscall 2nd arg)
	mov edx, BUFSIZE	; 'rdx' is the 3rd arg of syscall
				; i.e. rdx=64, the max. no. of bytes to read, stops the read from overflow read
	syscall			; enter kernel mode to perform the read.
				; our programme waits here until we press "Enter"
				; kernel returns inside 'rax' (i.e. syscall operation)
					; a positive no. how many bytes were read
					; 0 end of input
					; a negative no. error code
	
	; checking the result
	test rax, rax		; bitwise AND
	jle .exit		; 'jle' jump if less or equal (i.e. jump if <=)
				; this is the same as `if (rax <= 0) goto exit;`
	mov r12, rax		; copies byte count from 'rax'

	; write(1, hello, hello_len)
	; print "Hello"
	mov eax, 1		; 'rax' is syscall no. '1' being write
	mov edi, 1		; 'rdi' being 1st syscall arg
	lea rsi, [rel hello]	; 'rsi' being 2nd syscall arg. address of "Hello " string.
	mov edx, hello_len	; 'rdx' being 3rd syscall arg.
	syscall

	; write(1, buffer, bytes_read)
	mov eax, 1		; 'rax' being syscall no. '1' being write
	mov edi, 1		; 'rdi' being 1st syscall arg '1' being write
	mov rsi, rsp		; 'rsi' being 2nd syscall arg 'rsp' being stack ptr
	mov rdx, r12		; 'rdx' being 3rd syscall arg 'r12' being length of bytes read
	syscall

; cleaning up and exiting
.exit:
	add rsp, BUFSIZE	; 'add' destination = destination + src (i.e. rsp = rsp + 64)
				; moves stack ptr back to where it started (i.e. releasing 64 bytes)
			
	mov eax, 60		; rax being syscall no. 1 60 being exit
	xor edi, edi		; reset 'rdi' 1st syscall arg
	syscall
