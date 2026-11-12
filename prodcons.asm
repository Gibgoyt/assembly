; producer, queue, consumer
; single threaded

bits 64
default rel

SYS_write equ 1
SYS_exit equ 60

; the queue's shape
QCAP equ 4
QMASK equ QCAP - 1
SLOT_SIZE equ 16

section .rodata
	m1: db "order #1: 3 apples", 10
	m1_len equ $ - m1
	m2: db "order #2: 5 pears", 10
	m2_len equ $ - m2
	m3: db "order #3: 1 melon", 10
	m3_len equ $ - m3

	str_posted: db "producer: posted 3 messages, nobody read them yet", 10
	str_posted_len equ $ - str_posted
	str_got: db "consumer got: "
	str_got_len equ $ - str_got

section .bss
	q_slots: resb QCAP * SLOT_SIZE
	q_head: resq 1
	q_tail: resq 1
	; no padding???

section .text
	global _start


produce:
	mov rax, [q_tail]
	mov rcx, rax
	sub rcx, [q_head]
	cmp rcx, QCAP
	jae .full
	mov rcx, rax
	and rcx, QMASK
	shl rcx, 4
	lea rdx, [q_slots]
	mov [rdx + rcx], rdi
	mov [rdx + rcx + 8], rsi
	inc rax
	mov [q_tail], rax
	mov eax, 1
	ret

.full:
	xor eax, eax
	ret

consume:
	mov rax, [q_head]
	cmp rax, [q_tail]
	je .empty
	mov rcx, rax
	and rcx, QMASK
	shl rcx, 4
	lea rsi, [q_slots]
	mov rdx, [rsi + rcx + 8]
	mov rcx, [rsi + rcx]
	inc rax
	mov [q_head], rax
	mov rax, rcx
	ret

.empty:
	xor eax, eax
	ret

print:
	mov eax, SYS_write
	mov edi, 1
	syscall
	ret

_start:
	lea rdi, [m1]
	mov esi, m1_len
	call produce
	lea rdi, [m2]
	mov esi, m2_len
	call produce
	lea rdi, [m3]
	mov esi, m3_len
	call produce

	lea rsi, [str_posted]
	mov edx, str_posted_len
	call print

	xor ebx, ebx

.consume_loop:
	call consume
	test rax, rax
	jz .done
	mov r12, rax
	mov r13, rdx
	lea rsi, [str_got]
	mov edx, str_got_len
	call print
	mov rsi, r12
	mov rdx, r13
	call print
	inc ebx
	jmp .consume_loop

.done:
	mov edi, ebx
	mov eax, SYS_exit
	syscall
