; flush_demo.asm
; where are my bytes??? process buffer -> page cache -> drive

; writes 8MiB to flush_demo.dat in 3 stages, after each stage, showing where the data is
; 1 - fill process buffer
; 2 - write() -> kernel
; 3 - fsync() -> drive

; 2 measurements tell them apart:
; 1 - 	file size
;	fstat() asks kernel how big the file is
; 2 -	a line inside /proc/meminfo = kilobytes of file data that sit in RAM
;	changed not yet written into any drive
;	jumps after write() and drops back after fsync()

bits 64
default rel

; syscall numbers
SYS_read equ 0
SYS_write equ 1
SYS_close equ 3
SYS_fstat equ 5
SYS_exit equ 60
SYS_fsync equ 74
SYS_clock_gettime equ 228
SYS_openat equ 257

AT_FDCWD equ -100
O_RDONLY equ 0
O_WRONLY equ 1
O_CREAT equ 64
O_TRUNC equ 512
PERMS equ 420
CLOCK_MONOTONIC equ 1
EINTR equ 4

STDOUT equ 1
DATA_SIZE equ 8 * 1024 * 1024	; 8MiB page sizes
STAT_SIZE equ 144
ST_SIZE equ 48
MEMINFO_MAX equ 8192

%macro PRINT 1
	lea rsi, [%1]
	mov edx, %1_len
	call print
%endmacro

section .rodata
	fn_data: db "flush_demo.data", 0
	fn_meminfo: db "/proc/meminfo", 0
	dirity_key: db "Dirty:"
	
	msg_stage1: 	db "stage 1 fill our 8MiB process buffer", 10
	msg_stage1_len equ $ - msg_stage1

	msg_stage2: db 10, "stage 2 write(): handing bytes to kernel", 10
	msg_stage2_len equ $ - msg_stage2

	msg_stage3: db 10, "stage 3 fsync(): kernel flushes to disk", 10
	msg_stage3_len equ $ - msg_stage3

	msg_size: db "   file size that the kernel reports"
	msg_size_len equ $ - msg_size

	msg_bytes: db " bytes", 10
	msg_bytes_len equ $ - msg_bytes
	
	msg_took: db " syscall took"
	msg_took_len equ $ - msg_took
	
	msg_us: db " us", 10
	msg_us_len equ $ - msg_us
	msg_meminfo: db " /proc/meminfo "
	msg_meminfo_len equ $ - msg_meminfo

section .bss
	alignb 16
	user_buf: resb DATA_SIZE
	stat_buf: resb STAT_SIZE	; from fstat()
	meminfo_buf: resb MEMINFO_MAX	; buffer of /proc/meminfo
	num_buf: resb 32		; reserve space for print_uint
	g_errno: resd 1			; used by xwrite() of C++ fstream

section .text
	global _start


print:
	mov eax, SYS_write
	mov edi, STDOUT
	syscall
	ret

print_uint:
	mov rax, rdi
	lea rsi, [num_buf + 32]		; one past the end of the digit buff
	mov ecx, 10

.next_digit:
	xor edx, edx
	div rcx
	add dl, '0'
	dec rsi
	mov [rsi], dl
	test rax, rax
	jnz .next_digit
	lea rdx, [num_buf + 32]
	sub rdx, rsi
	jmp print

now_us:
	sub rsp, 24
	mov eax, SYS_clock_gettime
	mov edi, CLOCK_MONOTONIC
	mov rsi, rsp
	syscall

	imul rcx, [rsp], 1000000
	mov rax, [rsp + 8]
	xor edx, edx
	mov r8d, 1000
	div r8
	add rax, rcx
	add rsp, 24
	ret

file_size:
	mov eax, SYS_fstat
	lea rsi, [stat_buf]
	syscall

	mov rax, [stat_buf + ST_SIZE]
	ret
