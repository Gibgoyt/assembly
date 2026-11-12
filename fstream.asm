; fstream
; from libstdc++ x86 asm
; take from gnustdlibc++ so it has C++ approaches

; 64 bit mode
bits 64		; 64-bit mode
default rel	; RIP-relative

; linux syscalls on x86
SYS_read equ 	0
SYS_write equ 	1
SYS_close equ 	3
SYS_lseek equ 	8
SYS_mmap equ 	9
SYS_munmap equ 	11
SYS_ioctl equ 	16
SYS_writev equ 	20
SYS_getpid equ 	39
SYS_exit equ	60
SYS_kill equ	62
SYS_openat equ	257

AT_FDCWD equ	-100
O_RDONLY equ	0
O_WRONLY equ	1
O_RDWR equ	2
O_CREAT equ	64
O_EXCL equ	128
O_TRUNC equ	512
O_APPEND equ	1024
FILE_PERMS equ	438
EINTR equ	4
FIONREAD equ	0x541B
PROT_RW equ	3
MAP_PRIV_ANON equ	0x22
SIGABRT equ 6

EOF equ		-1
BUFSIZ equ	8192

OM_APP equ 	1
OM_ATE equ 	2
OM_BINARY equ	4
OM_IN equ	8
OM_OUT equ	16
OM_TRUNC equ	32
ON_NOREPLACE equ	64

GOODBIT equ 	0
BADBIT equ 	1
EOFBIT equ	2
FAILBIT equ	4

F_BOOLALPHA equ	1
F_DEC equ	2
F_FIXED equ	4
F_HEX equ	8
F_INTERNAL equ	16
F_LEFT equ	32
F_OCT equ	64
F_RIGHT equ	128
F_SCIENTIFIC equ	256
F_SHOWBASE equ	512
F_SHOWPOINT equ	1024
F_SHOWPOS equ	2048
F_SKIPWS equ	4096
F_UNITBUF equ	8192
F_UPPERCASE equ	16384
F_ADJUSTFIELD equ	F_LEFT | F_RIGHT | F_INTERNAL
F_BASEFIELD equ	F_DEC | F_OCT | F_HEX
 
; ios_base::seekdir (same numbers as lseek's SEEK_SET / SEEK_CUR / SEEK_END)
SEEK_BEG equ	0
SEEK_CUR equ	1
SEEK_END equ	2
 
STREAMSIZE_MAX equ	0x7FFFFFFFFFFFFFFF
STREAMSIZE_MIN equ	0x8000000000000000
LONG_MAX equ	0x7FFFFFFFFFFFFFFF
LONG_MIN equ	0x8000000000000000
INT_MAX equ	2147483647
INT_MIN equ	-2147483648

; obj/struct layouts
struc FILEBUF
	.vptr:	resq 1	; 'resq' meaning "reserve quad-word/8 bytes"

	.in_beg:	resq 1	; start of the get area
	.in_cur:	resq 1	; next byte to read
	.in_end:	resq 1	; end of the valid data
	.out_beg:	resq 1	; start of the put area
	.out_cur:	resq 1	; next byte to write
	.out_end:	resq 1	; end of the put area

	.fd:		resq 1	; file descriptor
	
	.mode:		resq 1	; open mode
	.buf:		resq 1	; the internal buffer
	.buf_size:	resq 1	; BUFSIZ by default
	.pback_cur_save:	resq 1
	.pback_end_save:	resq 1
	.buf_allocated:	resb 1
	.reading:	resb 1
	.writing:	resb 1
	.pback:		resb 1	; one-char putback buffer
	.pback_init:	resb 1
	.pad:		resb 3	; padding for 5 bytes above us
endstruc

struc STREAM
	.vptr:		resq 1	; ptr to stream class' vtable
	.gcount:	resq 1
	.precision:	resq 1
	.width:		resq 1
	.flags:		resd 1
	.exception:	resd 1
	.state:		resd 1
	.fill:		resd 1
	.tie:		resq 1
	.sb:		resq 1
	.filebuf:	resb FILEBUF_size
endstruc

; slots of the `basic_streambuf` vtable
; in declaration order (C++ ABI)
VT_DTOR equ	0	; complete object dtor
VT_DTOR_DELETE equ	8	; deleting dtor
VT_IMBUE equ		16
VT_SETBUF equ		24
VT_SEEKOFF equ		32
VT_SEEKPOS equ		40
VT_SYNC equ		48
VT_SHOWMANYC equ	56
VT_XSGETN equ		64
VT_UNDERFLOW equ	72
VT_UFLOW equ		80
VT_PBACKFAIL equ	88
VT_XPUTN equ		96
VT_OVERFLOW equ		104

; this->v_func()
; 'this' already in 'rdi'
%macro VCALL 1
	mov rax, [rdi]	; 'rax' = this->vptr
	call [rax + %1]	; call through vtable slot
%endmacro

; return this->v_func()
; tail call (i.e. re-use our return address)
%macro VJMP 1
	mov rax, [rdi]	; 'rax' = this->vptr()
	jmp [rax + %1]
%endmacro
