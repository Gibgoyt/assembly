; memory_map.asm
; visit every region of a process address space

bits 64
default rel

; syscalls
SYS_write equ 1
SYS_mmap equ 9
SYS_brk equ 12
SYS_exit equ 60

; mmap args
PROT_READ equ 1
PROT_WRITE equ 2
MAP_PRIVATE equ 0x02
MAP_ANONYMOUS equ 0x20	; not backed by a file, plain zeroed memory

; auxillary vector (auxv) entry types
AT_NULL equ 0	; end of auxv list
AT_SYSINFO_EHDR equ 33	; address of vDSO

; sizes
PAGE equ 4096
HEAP_GROW equ 64 * 1024	; 64 KiB heap growth step
MMAP_SIZE equ 1024 * 1024	; 1MiB block from mmap()
STACK_BIG equ 1024 * 1024	; 1MiB local array on the stack

KERNEL_ADDR equ 0xffff888000000000	; this is inside kernel space

; write(1, label, label_len)
%macro PRINT 1
	lea rsi, [%1]
	mov edx, %1_len
	call print
%endmacro

section .rodata
	; writing to this memory region also segfaults
	greeting: db " .rodata says hello", 10
	greeting_len equ $ - greeting

	m_args: db "[1] argv/env/auxv at the top of the stack", 10
	m_args_len equ $ - m_args

	m_text: db "[2] .text: read our own machine code", 10
	m_text_len equ $ - m_text
	m_rodata: db "[3] .rodata: prints a constant string", 10
	m_rodata_len equ $ - m_rodata
	m_data: db "[4] .data: counter 41 -> 42", 10
	m_data_len equ $ - m_data
	m_bss: db "[5] .bss: write into a zeroed buffer", 10
	m_bss_len equ $ - m_bss
	m_heap: db "[6] heap: brk grows it by 64KiB", 10
	m_heap_len equ $ - m_heap
	m_mmap: db "[7] mmap: a fresh 1MiB block", 10
	m_mmap_len equ $ - m_mmap
	m_stack: db "[8] stack: grow it by 1MiB", 10
	m_stack_len equ $ - m_stack
	m_vdso: db "[9] vdso: read kernel's code in our address space", 10
	m_vdso_len equ $ - m_vdso
	m_crash: db "[10] crash test: about to touch forbidden memory", 10
	m_crash_len equ $ - m_crash
	m_done: db "done", 10
	m_done_len equ $ - m_done

section .data
	align 8
	counter: dq 41

section .bss
	alignb 16
	scratch: resb PAGE	; in this case, a 4KiB buffer

	; results of each stage
	; kept in memory so gdb can print at any time
	g_rsp0: resq 1	; rsp when _start began
	g_argc: resq 1	; argc
	g_mode: resq 1	; either first letter of argv[1] or 0
	g_auxv: resq 1	; address of first auxv entry
	g_vdso: resq 1	; address of vDSO (from auxv)
	g_text_byte: resq 1	; first byte of .text section (i.e. _start machine code)
	g_heap_start: resq 1	; where the heap begins
	g_heap_end: resq 1	; where the heap ends (after growing)
	g_mmap: resq 1		; address that mmap() returns
	g_rsp_deep: resq 1	; lowest rsp during stack stage
	g_vdso_magic: resq 1	; first 4B of vDSO

section .text
	global _start

print:
	mov eax, SYS_write
	mov edi, 1
	syscall

	ret

stack_grow:
	push rbp	; prologue
	mov rbp, rsp
	sub rsp, STACK_BIG	; rsp drops by 1MiB in this case

	mov rcx, rbp

.touch:
	sub rcx, PAGE		; next page down
	mov byte [rcx], 1	; first touch, kernel maps the page
	cmp rcx, rsp		;
	ja .touch

stack_deepest:			; breakpoint right here, stack is 1MiB bigger
	mov [g_rsp_deep], rsp
	mov rsp, rbp		; epilogue. free array in one step
	pop rbp
	ret

_start:
	mov [g_rsp0], rsp	; remember where kernel put rsp

	; [1] (argv, env, auxv)
stage_args:
	PRINT m_args
	mov rsi, [g_rsp0]	
	mov rcx, [rsi]		; argc
	mov [g_argc], rcx
	cmp rcx, 2
	jb .no_mode
	mov rax, [rsi + 16]	; argv[1] which is ptr to a string
	movzx eax, byte [rax]	; its first letter
	mov [g_mode], rax

.no_mode:
	lea rsi, [rsi + 8 + rcx*8 + 8]	; skips argc and argv[0...argc-1] and its 0
.skip_env:	; skip envp[] up to and past its 0
	mov rax, [rsi]
	add rsi, 8
	test rax, rax
	jnz .skip_env
	mov [g_auxv], rsi	; rsi being first auxv entry
.aux:
	mov rax, [rsi]		; entry type
	cmp rax, AT_NULL
	je stage_text		; end of this list
	cmp rax, AT_SYSINFO_EHDR
	jne .aux_next
	mov rax, [rsi + 8]	; entry value (vDSO's address)
	mov [g_vdso], rax
.aux_next:
	add rsi, 16	; next(type value) pair
	jmp .aux

	; [2] .text
	; code is just bytes in memory, so read the first byte of _start
stage_text:
	PRINT m_text
	lea rsi, [_start]
	movzx eax, byte [rsi]
	mov [g_text_byte], rax

	; [3] .rodata
stage_rodata:
	PRINT m_rodata
	PRINT greeting
	
	; [4] .data
stage_data:
	PRINT m_data
	inc qword [counter]	; 41 -> 42 (showcasing that .data is writable)

	; [5] .bss 
stage_bss:
	PRINT m_bss
	mov byte [scratch], 'A'	; was 0, now 'A'
	mov byte [scratch + PAGE - 1], 'Z'

	; [6] .heap
stage_heap:
	PRINT m_heap
	mov eax, SYS_brk
	xor edi, edi
	syscall

	mov [g_heap_start], rax
	lea rdi, [rax + HEAP_GROW]
	mov eax, SYS_brk
	syscall

	mov [g_heap_end], rax
	mov rdi, [g_heap_start]
	mov byte [rdi], 'H'	; first heap byte
	mov byte [rax -1], 'h'	; last heap byte

	; [7] mmap
stage_mmap:
	PRINT m_mmap
	mov eax, SYS_mmap
	xor edi, edi	; lets the kernel choose the address
	mov esi, MMAP_SIZE
	mov edx, PROT_READ | PROT_WRITE
	mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
	mov r8, -1	; no file
	xor r9d, r9d	; offset 0
	syscall

	mov [g_mmap], rax
	mov byte [rax], 'M'

	; [8] stack
stage_stack:
	PRINT m_stack
	call stack_grow		; stops at stack_deepest inside

	; [9] vDSO
	; kernel maps small ELF library into every process (Executable + Linkable Format)
stage_vdso:
	PRINT m_vdso
	mov rsi, [g_vdso]
	mov eax, [rsi]		; 4B
	mov [g_vdso_magic], rax

	; [10] crash
stage_crash:
	mov rax, [g_mode]
	test rax, rax
	jz finish
	PRINT m_crash
	mov rax, [g_mode]
	cmp al, 'n'	; al being 1B at rax
	je .null
	cmp al, 'k'
	je .kernel
	cmp al, 't'
	je .text
	cmp al, 'r'
	je .rodata
	jmp finish

.null:
	mov rax, [abs 0]	; read address at 0x00 (a plain address and not relative to rip)

.kernel:
	mov rax, KERNEL_ADDR
	mov rax, [rax]		; read kernel memory
.text:
	lea rax, [_start]
	mov byte [rax], 0x90	; write into .text section
.rodata:
	mov byte [greeting], 'H'	; writes into read-only data .rodata

finish:
	PRINT m_done
	xor edi, edi
	mov eax, SYS_exit
	syscall
