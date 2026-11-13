# Read/Only Data
```asm
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
```

This is **NOT** part of `.data`, it is a separate area of the program with different permissions

A program is split into sections

| Section | Holds | Address | Permissions at run time |
|---|---|---|---|
| `.text` | instructions | `0x401000` | `r-x` read + execute |
| `.rodata` | constants: vtables, strings | `0x402000` | `r--` **read only** |
| `.data` | variables with starting values | (none in this file) | `rw-` read + write |
| `.bss` | variables that start as zero: `sq`, `rc` | `0x40302c` | `rw-` read + write |

#Constructors
## Square Constructor
```asm
square_ctor:
	lea rax, [square_vtable]	
	mov [rdi + SQUARE.vptr], rax
	mov [rdi + SQUARE.side], rsi
	ret
```

`lea rax, [square_vtable]` rax is not acting as a return register here
because square_ctor does not return anything, it is being used here as a scratch
register
`[ ]` means "the memory at this address", the text inside the `[...]` computes an address
`mov rax, [X]` reads 8 bytes from address `X` into rax, reads the memory
`mov [X], rax` write `rax` into memory at address `X`, writes memory
`lea rax, [X]` put address X itself into `rax` does not read or write memory

## Rectangle Constructor

```asm
rect_ctor:
	lea rax, [rect_vtable]
	mov [rdi + RECT.vptr], rax
	mov [rdi + RECT.w], rsi
	mov [rdi + RECT.h], rdx
	ret
```

Please remember, that `mov [X], rax` copies 8 bytes inside `rax` into memory starting at address `X`
`rax` keeps its value, `mov` does a copy and nothing is moved out
writes 8 bytes because `rax` is a 64-bit register, the hardware register's size sets how many bytes get written

all 4 registers take part in this ctor
`rdi` holds `this` the address of the object
`rsi` holds the rectangle's width
`rdx` holds the rectangles height

Look at RECT struct
```asm
struc RECT
    .vptr:  resq 1      ; RECT.vptr = 0
    .w:     resq 1      ; RECT.w    = 8
    .h:     resq 1      ; RECT.h    = 16
endstruc                ; RECT_size = 2
```

and its call from `_start`
```asm
lea     rdi, [rc]       ; rdi = 0x40303c  (the object rc)
mov     esi, 2          ; rsi = 2
mov     edx, 5          ; rdx = 5
call    rect_ctor
```

`lea rax, [rect_vtable]` rax=0x402010, the address of `rect_vtable` inside .rodata, no memory is read
`mov [rdi + RECT.vptr], rax` now writes rax to memory at 0x40303c + 0 = 0x40303c
`mov [rdi + RECT.w], rsi` write w to memory at 0x40303c + 8 = 0x403044, and this address now holds the width of our rectangle
`mov [rdi + RECT.h], rdx` write h to memory at 0x40303c + 16 = 0x40304c

this results in 34 bytes of memory
|Address|Offset|Contents|
|---|---|---|
|0x40303c|+0|0x402010 -> rect_table: rect_name, rect_area|
|0x403044|+8|actual width|
|0x40304c|+16|actual height|

# File Descriptors
for any syscall, it will look something like this:
```assembly
mov rax, SYS_action
mov edi, FILE_DESCRIPTOR
mov rsi, VALUE
mov rdx, VALUE_LENGTH
syscall
```

|fd|name|
|---|---|
|0|stdin|
|1|stdout|
|2|stderr|
|3+|dynamic allocation|

fds are non-negative integers, when a process opens a file, pipe or dir or device using a ssycall, the kernel hands back the lowest numbered un-used integer

# RIP and RSP

Instruction Pointer and Stack Pointer
on x86-64 the stack grows downwards
push, pop, call, and ret all changes `rsp`

`ret` reads return address from the top of the stack into `rip` then adds 8 to `rsp`
rip <- mem[rsp]
rsp <- rsp + 8

`rip` holds address of the next instruction to run, changing it makes the CPU jump

# VCALL and VJMP

## VCALL
```assembly
%macro VCALL 1                 ; define a macro named VCALL that takes 1 argument
    mov     rax, [rdi]
    call    [rax + %1]         ; %1 = whatever you wrote after VCALL
%endmacro
```

`% macro NAME n` starts a definition, where `n` is the number of arguments it takes
`%1` is replaced by the first argument

```assembly
shape_area_call:
 sub rsp, 8
 mov rax, [rdi]
 call [rax + VT_AREA]
 add rsp, 8
 ret
```

`sub rsp, 8` moves the stack ptr down 8 bytes, nothing stored there, it is just padding
`mov rax, [rdi]` read object's first 8 bytes, its vptr
`call [rax + VT_AREA]` read address in slot 1 + push a return address then jump there (i.e. now in square_area or rect_area)
`add rsp, 8` remove the padding
`ret` pop the return address into `rip`

`rax` is used twice, first vtable address goes into it, then `square_area` overwrites it with its return, which is fine because vptr no longer needed by then

## RSP Padding Explained
`sub rsp, 8`
The system V convention requires `rsp` to be a mutliple of 16 at the moment of every call. The called function knows how its stack is aligned. Some instructions demand 16-byte aligned memory and crash otherwise. `movaps` used inside C library functions like `printf()` is a classic example

`square_area` does not actually need the alignment, but we use the alignment becauase the code doing the VCALL will never know which function the vtable will send to

## Example VCALL + VJMP Explained

```assembly
SYS_exit equ 60

VT_NAME equ 0
VT_AREA equ 8

%macro VCALL 1
    mov rax, [rdi]  ; `rax` being obj 1st bytes. its vptr
    call [rax + %1] ; push return address + jump to vtable slot
%endmacro

%macro VJMP 1
    mov rax, [rdi]
    jmp [rax + %1]  ; jump to vtable slot (pushes nothing)
%endmacro
```

at compile time `VCALL VT_AREA` becomes `mov rax, [rdi]` + `call rax + 8` vtable entries left ass placholders because function addresses are not known yet

at link time addresses are decided and the placeholders are filled
at runtime ctor writes vptr into object, every VCALL/VJMP reads obj vptr, then reads slot, then jump

vtables itself built before runtime, choosing which function to call happens at runtime

link time builds into `.rodata` something that looks like this:
```assembly
square_vtable:      ; 0x402000
    dq square_name  ; 0x402000 holds 0x401022
    dq square_area  ; 0x402008 holds 0x40103b
rect_vtable:
    dq rect_name    ; 0x402010 holds 0x401044
    dq rect_area    ; 0x402018 holds 0x40105d
```

and at runtime the ctor write these:
```assembly
square_ctor:
    lea rax, [square_vtable]
    mov [rdi + SQUARE.vptr], rax    ; sq+0 = 0x402000
    mov [rdi + SQUARE.side], rsi    ; sq+8 = 3
```

```
sq 0x40302c: [0x402000][3] -> square_vtable
rc 0x40303c: [0x402010][2][5] -> rect vtable
```

area call 1 inside `_start`
```assembly
lea rdi, [sq]
call shape_area_call
```

`shape_area_call` with macro expanded
```assembly
shape_area_call:
    sub rsp, 8  ; padding so multiple of 16
    mov rax, [rdi]  
    call [rax + 8]  ; these 2 lines expanded from `VCALL VT_AREA`
    add rsp, 8
    ret
```

`mov rax, [rdi]` reads object first bytes, its vptr
`call [rax + 8]` reads slot 1 of the table + pushes return address + jumps
then `square_area` function runs with `rdi` still pointing at `sq`

```assembly
square_area:
    mov rax, [rdi + SQUARE.side]
    imul rax, rax
    ret
```

then back inside `shape_area_call` function `add rsp, 8` removes the padding and `ret` pops `0x4010c7`

| Call | rdi | [rdi] (vptr) | [vptr + 8] | runs |
|------|-----|--------------|------------|------|
|shape_area_call(&sq) | 0x40302c | 0x402000 | square_area -> 9 |
| shape_area(&rc) | 0x40303c | 0x402010 | 0x40105d | rect_area -> 10 |

