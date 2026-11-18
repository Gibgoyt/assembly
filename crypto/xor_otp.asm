; xor_otp.asm
; XOR, one-time pad, and why a key is never re-used

bits 64
default rel

; syscalls
SYS_write equ 1
SYS_exit equ 60
SYS_getrandom equ 318	; fill a buffer with random bytes

STDOUT equ 1
MSG_LEN equ 14		; both messages exactly 14B

; PRINT label
%macro PRINT 1
	lea rsi, [%1]
	mov edx, %1_len
	call print
%endmacro

section .rodata
	msg1: db "attack at dawn"	; 14B, now \n
	msg2: db "defend at dusk"	; 14B, now \n
	hexdigits: db "0123456789abcdef"	; nibble value -> hex char

	lbl_key: db "key	: "
	lbl_key_len equ $ - lbl_key
	lbl_p1: db "plaintext 1 (hex) : "
	lbl_p1_len equ $ - lbl_p1
	lbl_c1: db "ciphertext 1 : "
	lbl_c1_len equ $ - lbl_c1
	lbl_d1: db "decrypt c1 with key : "
	lbl_d1_len equ $ - lbl_d1
	lbl_c2: db 10, "-- key RE-USED for message 2 --", 10, "ciphertext 2 : "
	lbl_c2_len equ $ - lbl_c2
	lbl_x: db "c1 XOR c2	: "
	lbl_x_len equ $ - lbl_x
	lbl_pp: db "p1 XOR p2	: "
	lbl_pp_len equ $ - lbl_pp
	lbl_rec: db "attacker recovers p2: "
	lbl_rec_len equ $ - lbl_rec
	newline: db 10
	newline_len equ 1

section .bss
	alignb 16
	key: resb MSG_LEN
	c1: resb MSG_LEN
	c2: resb MSG_LEN
	tmp: resb MSG_LEN
	hexbuf: resb MSG_LEN * 3	; "xx " per byte

section .text
	global _start

print:
	mov eax, SYS_write
	mov edi, STDOUT
	syscall
	ret

xor_buf:
	xor r8d, r8d
.loop:
	cmp r8, rcx
	jae .done	; >= len (finished)
	mov al, [rsi + r8]	; al = src[i] (1B)
	xor al, [rdx + r8]	; src[i] ^ key[i]
	mov [rdi + r8], al	; dst[i] = al
	inc r8
	jmp .loop
.done:
	ret

print_hex:
	lea rdi, [hexbuf]	; where the text goes
	lea r9, [hexdigits]	; table base (RIP-relative can not take an index, so put address into register first)
	xor ecx, ecx
.loop:
	cmp rcx, rdx
	jae .done
	movzx eax, byte [rsi + rcx]	; eax 1B
	mov r8d, eax
	shr r8d, 4	; high-nibble (0..15)
	mov r8b, [r9 + r8]	; -> '0'...'f'
	mov [rdi], r8b
	and eax, 0x0F		; low nibble (0...15)
	mov al, [r9 + rax]
	mov [rdi + 1], al
	mov byte [rdi + 2], ' '
	add rdi, 3
	inc rcx
	jmp .loop
.done:
	mov byte [rdi -1], 10	; turns the last ' ' space into a newline
	lea rsi, [hexbuf]
	mov rdx, rdi
	sub rdx, rsi
	jmp print

print_text:
	call print
	PRINT newline
	ret

_start:
	; a random key
	mov eax, SYS_getrandom
	lea rdi, [key]
	mov esi, MSG_LEN
	xor edx, edx
	syscall

	cmp rax, MSG_LEN
	jne fail

	PRINT lbl_key
	lea rsi, [key]
	mov edx, MSG_LEN
	call print_hex

	PRINT lbl_p1
	lea rsi, [msg1]
	mov edx, MSG_LEN
	call print_hex

	; encrypt: c1 = msg1 ^ key
	lea rdi, [c1]
	lea rsi, [msg1]
	lea rdx, [key]
	mov ecx, MSG_LEN
	call xor_buf

	; decrypt: tmp = c1 ^ key
	lea rdi, [tmp]
	lea rsi, [c1]
	lea rdx, [key]
	mov ecx, MSG_LEN
	call xor_buf

	PRINT lbl_d1
	lea rsi, [tmp]
	mov edx, MSG_LEN
	call print_text

	; the mistake: c2 = msg2 ^ SAME key
	lea rdi, [c2]
	lea rsi, [msg2]
	lea rdx, [key]
	mov ecx, MSG_LEN
	call xor_buf

	PRINT lbl_c2
	lea rsi, [c2]
	mov edx, MSG_LEN
	call print_hex

	; what an evesdropper computes
	lea rdi, [tmp]
	lea rsi, [c1]
	lea rdx, [c2]
	mov ecx, MSG_LEN
	call xor_buf

	PRINT lbl_x
	lea rsi, [tmp]
	mov edx, MSG_LEN
	call print_hex

	; for comparison, p1 ^ p2 directly
	lea rdi, [c2]
	lea rsi, [msg1]
	lea rdx, [msg2]
	mov ecx, MSG_LEN
	call xor_buf

	PRINT lbl_pp
	lea rsi, [c2]
	mov edx, MSG_LEN
	call print_hex

	; attacker guesses p1, gets p2: (c1 ^ c2) ^ p1 = p2
	lea rdi, [c2]
	lea rsi, [tmp]
	lea rdx, [msg1]
	mov ecx, MSG_LEN
	call xor_buf

	PRINT lbl_rec
	lea rsi, [c2]
	mov edx, MSG_LEN
	call print_text

	xor edi, edi
	mov eax, SYS_exit
	syscall

fail:
	mov edi, 1
	mov eax, SYS_exit
	syscall
