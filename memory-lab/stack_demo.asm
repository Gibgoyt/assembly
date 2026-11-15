; stack demo
; rip, rsp, rbp, push/pop, call/ret and stack frames

bits 64
default rel

SYS_exit equ 60
section .text
	global _start

square_plus:
	push rbp	; save caller's rbp
	mov rbp, rsp	; rbp = base of our frame
	sub rsp, 16	; room for 16B (2 locals 8B each)

	mov rax, rdi	; from `_start` rdi contains 3
	imul rax, rdi	; rax = a*a
	mov [rbp - 8], rax	; s = a*a
	add rax, rsi	; rax=s+b, rsi is set to 5 from `outer`
	mov [rbp - 16], rax	; t = s+b
	mov rax, [rbp - 16]	; return t

	mov rsp, rbp	; free the locals
	pop rbp		; restore caller's rbp
	ret		; jump to return address on the stack

outer:
	push rbp
	mov rbp, rsp
	sub rsp, 16	; 8 bytes for x + 8 to keep 16B aligned

	mov [rbp - 8], rdi	; save x onto the stack
	mov esi, 5	; arg 2 = 5 (arg 1, rdi = x, already set from _start)
	call square_plus	; rax = x*x + 5
	add rax, [rbp - 8]	; r+x (x is read back from the stack)

	mov rsp, rbp
	pop rbp
	ret

_start:
	; push/pop on their own
	push 0x11	; rsp -= 8, then store 0x11 at [rsp]
	push 0x22	; rsp -= 8, then store 0x22 at [rsp]
	pop rax		; rax = [rsp] = 0x22, then rsp += 8
	pop rbx		; rbx = [rsp] = 0x11, then rsp += 8

	; call with stack frames
	mov edi, 3	; arg 1: x=3
	call outer	; rax = 17

	mov edi, eax	; exit(17)
	mov eax, SYS_exit
	syscall
