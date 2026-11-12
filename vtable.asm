; vtable.asm
; virtual functions built by hand

bits 64
default rel

SYS_write equ 1
SYS_exit equ 60

; vtable layout
; a vtable is an array of function addresses, 8 bytes each
; slot n sits at bytes offset 8 * n
VT_NAME equ 0
VT_AREA equ 8

; struc layouts
; every obj starts with its vptr
; (i.e. the address of its vtable)
struc SQUARE
	.vptr: 	resq 1
	.side: 	resq 1
endstruc

struct RECT
	.vptr: 	resq 1
	.w:	resq 1
	.h:	resq 1
endstruc

%macro VCALL 1
	mov rax, [rdi]	; 'rax' is vptr of the struc
	call [rax + %1]	; push return address, jump to vtable slot
%endmacro

%macro VJMP 1
	mov rax, [rdi]	; same lookup as VCALL
	jmp [rax + %1]	; jump to the slot, push nothing
%endmacro

section .rodata
	; one vtable per class
	; same slot order in both
	; that is the entire trick
	; linker fills 'dq' with function's 64 bit address
	square_vtable:
		dq square_name
		dq square_area
	rect_vtable:
		dq rect_name
		dq rect_area
	
	str_square: db "Square", 10
	str_square_len equ $ - str_square
	str_rect: db "Rect", 10
	str_rect_len equ $ - str_rect

section .bss
	sq: resb SQUARE_size
	rc: resb RECT_size

section .text
	global _start

; ctors
square_ctor:
	lea rax, [square_vtable]
	mov [rdi + SQUARE.vptr], rax	; this->vptr = &square_vptr
	mov [rdi + SQUARE.side], rsi
	ret

_start:

