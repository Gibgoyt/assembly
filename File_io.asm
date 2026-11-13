; open, write, read, and close a file
; raw linux syscalls

bits 64
default rel

; syscall numbers
SYS_read equ 0
SYS_write equ 1
SYS_close equ 3
SYS_exit equ 60
SYS_openat equ 257

AT_FDCWD equ -100
O_RDONLY equ 0
O_WRONLY equ 1
O_CREAT equ 64
O_TRUNC equ 512
PERMS equ 420

STDOUT equ 1
BUFSIZE equ 64

section .rodata
	filename: db "hello.text", 0
	text: db "written by File_io.asm", 10
	text_len equ $ - text

section .text
	global _start

_start
	; open file for writing into
	mov eax, SYS_openat
	mov rdi, AT_FDCWD
	lea rsi, [filename]
	mov edx, O_WRONLY | O_CREAT | O_TRUNC
	mov r10d, PERMS
	syscall

	test rax, rax
	js .error
	mov rbx, rax

	; write the
	mov eax, SYS_write
	mov rdi, rbx
	lea rsi, [text]
	mov edx, text_len
	syscall

	test rax, rax
	js .error

	; close the file
	mov eax, SYS_close
	mov rdi, rbx
	syscall

	; open the file again in read-only
	mov eax, SYS_openat
	mov rdi, AT_FDCWD
	lea rsi, [filename]
	mov edx, O_RDONLY
	syscall

	test rax, rax
	js .error
	mov rbx, rax

	; read file into a stack-allocated buffer
	sub rsp, BUFSIZE	; reserving bytes (64B)
	mov eax, SYS_read
	mov rdi, rbx
	mov rsi, rsp
	mov edx, BUFSIZE
	syscall

	test rax, rax
	js .error
	mov r12, rax		; keep byte count

	; print what we just read
	mov eax, SYS_write
	mov edi, STDOUT
	mov rsi, rsp
	mov rdx, r12
	syscall

	add rsp, BUFSIZE	; return the stack space back

	; close and exit
	mov eax, SYS_close
	mov rdi, rbx
	syscall

	xor edi, edi
	mov eax, SYS_exit

	; failed syscall returns -errno in rax
.error:
	neg rax
	mov edi, eax
	mov eax, SYS_exit
	syscall
