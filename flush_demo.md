# Syscalls
Register roles only matter at the moment of a function call or syscall

```assembly
print:
    mov eax, SYS_write
    mov edi, STDOUT
    syscall
    ret
```

So `print` function expects text address at `rsi` and length at `rdx`
`print_uint` builds digit ptr in `rsi` from the start

When loop finishes `rsi` already points at first digit, no extra `jmp` needed before jumping to `print` function

```assembly
print_uint:
    mov rax, rdi
    lea rsi, [num_buf + 32]
    mov ecx, 10
```

`mov rax, rdi` copies the number into `rax`, which is not a choice because `div` instruction always divides the value in `rdx:rax`, `rdx` being upper 64 bits, `rax` lower 64 bits, so the number must be in `rax`
`lea rsi, [num_buf + 32]`:`rsi` being the address one-byte past the end of 32B `num_buf`. No memory is read. Starting past the end is deliberate, since division produces digits right to left, so loop decrements `rsi` before each store filling buffer backwards, nothing is ever written to `num_buf + 32` itself
`mov ecx, 10` is the divisor, since `div` can not divide a number written in the instruction, so it has to be in the other register, writing `ecx` zeroes the upper half so `div rcx` divides by exactly 10

The rest of the function `:next_digit`

# print_uint Function explained
This function turns a number into decimal text and prints it
example number we will use for this demo "2334"

from the caller it will look something like this:
```assembly
    mov rdi, rax    ; puts the number into rdi
    call print_uint
```

first we set up
```assembly
print_uint:
    mov rax, rdi
    lea rsi, [num_buf + 32]
    mov ecx, 10

.next_digit:
    xor edx, edx
    div rcx
    add d1, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .next_digit
    lea rdx, [num_buf + 32]
    sub rdx, rsi
    jmp print
```
## `mov rax, rdi`
copies the number into `rax` (i.e. rax = 2334)
this is because `div` always takes the numerator from `rax`

## `lea rsi, [num_buf +32]`
`rsi` being the address of one-byte past the end of the 32B buffer num_buf
`lea` only computes the address and reads, no memory read or write
digits come out last digit first from the software, we are basically writing a popping algorithm for `num_buf` to convert the entire buffer into a string to be able to print it

## `mov ecx, 10`
`rcx` = 10 (i.e. the denominator) such that `div r11` on x86-64 is rax/r11
but `div r11` divides both `rdx`,`rax` by `r11` from a 128b register

## The `.next_digit` loop
### `xor edx, edx`
on x86-64 `div` has a 128b register with `rdx` being upper 64b and `rax` being lower 64b, I am not entirely sure why tf this is I will have to research this bullshit
so this makes `rdx` zero else the junk in it will ruin `rax` after we run `div`
### `div rcx`
`rax`/`rcx` and output filled into `rax`
the remainder now goes into `rdx`
e.g. 2334 / 10, `rax` = 233 and `rdx` = 4 
### `add dl, '0'`
this turns digit into its text char
`dl` being the lowest 1byte of `rdx`, we know since denominator = 10 that remainder in [0,9] so 1 byte will cover that, and in ASCII '0' to '9' are 48 to 57, adding 48 converts it to its char
e.g. 4 + 48 = 52 = 0x34, which is ASCII '4'
### `dec rsi`
steps 1 byte left, decrementing before storing is why we start 1 byte past the end
### `mov [rsi], dl`
[] on the left/dest so we are writing into a memory slot here, storing char address in `rsi`, writing 1 byte because `dl` is a 1B register
### `test rax, rax`
checks whether the quotient is 0
`test` runs bitwise AND without storing the result, keeps the flags
so '0' flag is set if `rax` is zero
### `jnz .next_digit`
if `rax` ≠ 0 go back for the next one, but when `rax` = 0 that means every digit is done and execution falls through

| Pass | `rax` in | `div`: quotient → `rax` | remainder → `rdx` | `dl` + 48 | `rsi` after `dec` | byte written |
|---|---|---|---|---|---|---|
| 1 | 2334 | 233 | 4 | 52 `'4'` | `num_buf + 31` | `'4'` |
| 2 | 233 | 23 | 3 | 51 `'3'` | `num_buf + 30` | `'3'` |
| 3 | 23 | 2 | 3 | 51 `'3'` | `num_buf + 29` | `'3'` |
| 4 | 2 | 0 | 2 | 50 `'2'` | `num_buf + 28` | `'2'` |
### `lea rdx, [num_buf + 32]`
`rdx` is the end address, 1B past the last digit of num_buf
### `sub rdx, rsi`
length = end - start
$$(\texttt{num\_buf} + 32) - (\texttt{num\_buf} + 28) = 4$$
now `rsi` is the address of '2334' and `rdx` = 4
### `jmp print`
it is not a `call`, here is what happens on the stack:
1. caller `call print_uint` pushed a return address
2. `print_uint` pushed nothing, and `jmp` pushes nothing
3. `print` runs its `ret`, top of the stack holds the caller's return address, so `print` returns straight to the caller

# Register Summary
| Register | Holds |
|---|---|
| `rdi` | the number coming in (argument) |
| `rax` | the number, shrinking by a factor of 10 each pass (quotient) |
| `rcx` | 10, the divisor |
| `rdx` | 0 before each `div`, then the remainder (digit); at the end, the length |
| `dl` | the low byte of `rdx`: the digit as a character |
| `rsi` | the write position, moving left; at the end, the start of the text |

# Timer
`_start` calls `now_us` twice around each slow operation as a stopwatch

```assembly
    call    now_us              ; ① read the clock: start time in rax
    mov     r12, rax            ;    keep it safe in r12
    mov     edi, ebx            ; ┐
    lea     rsi, [user_buf]     ; │ the thing being timed:
    mov     edx, DATA_SIZE      ; │ write 8 MiB
    call    xwrite              ; ┘
    cmp     rax, DATA_SIZE
    jne     write_failed
    call    now_us              ; ② read the clock again: end time in rax
    sub     rax, r12            ;    elapsed = end - start
    mov     rdi, rax
    call    report_time         ;    prints "syscall took: 2334 us"
```

## The `now_us` function line-by-line
```assembly
now_us:
	sub     rsp, 24                 ; room for the timespec (16) + alignment
	mov     eax, SYS_clock_gettime
	mov     edi, CLOCK_MONOTONIC
	mov     rsi, rsp
	syscall
	imul    rcx, [rsp], 1000000     ; rcx = tv_sec * 1,000,000
	mov     rax, [rsp + 8]          ; rax = tv_nsec
	xor     edx, edx
	mov     r8d, 1000
	div     r8                      ; rax = tv_nsec / 1000
	add     rax, rcx                ; total microseconds
	add     rsp, 24
	ret
```

### `sub rsp, 24`
make room on the stack for a local variable
moving `rsp` down by 24 bytes claims space (i.e. rsp = X - 32)

```
X - 8    [ return address → _start ]   pushed by call
X - 16   [ unused padding          ]
X - 24   [ tv_nsec                 ]   rsp + 8   ┐ struct timespec,
X - 32   [ tv_sec                  ]   rsp + 0   ┘ filled by the kernel
```

The kernel will write `struc timespec` here, 2 8B numbers, so 16B
extra 8B padding brings it a 16 multiple
`now_us` does not call any other functions, it is not strictly needed to keep 16B alignment, but we use it out of habit
### `mov eac SYS_clock_gettime`
`rax` = 228
clock_gettime syscall
### `mov edi, CLOCK_MONOTONIC`
which clock? Linux has several
- CLOCK_REALTIME: system-wide realtime clock (wall-time) clock measures time since epoch
- CLOCK_MONOTONIC: monotonic clock that can not be set and represnts elapsed time since an unspecified starting point (usually system boot). it does not jump if the wall clock is adjusted, ideal for measuring intervals
- CLOCK_PROCESS_CPUTIME_ID: per-process CPU time clock tracking total CPU time consumed by all threads in the calling process
- CLOCK_THREAD_CPU_TIME_ID: thread-specific CPU time clock tracking CPU time consumed by the calling thread
- CLOCK_MONOTONIC_RAW: monotonic time source providing real hardware based time without NTP or skewing adjustments
- CLOCK_REALTIME_COARSE: faster, lower precision version of CLOCK_REALTIME updates only on timer ticks ~1ms avoding expensive kernel-to-user context switching
- CLOCK_MONOTONIC_COARSE: faster, lower precision version of CLOCK_MONOTONIC updated on ticks
CLOCK_BOOTTIME: similar to CLOCK_MONOTONIC, but includes any time system spent suspended in a lower power state
- CLOCK_REALTIME_ALARM: like CLOCK_REALTIME but it will wake system up if suspended
- CLOCK_TAI: International Atomic Time (TAI), counts seconds strictly without skipping leap seconds (unlike UTC based CLOCK_REALTIME)
### `mov rsi, rsp`
where the kernel should write the result (i.e. the 16 bytes that we just reserved) notice no `[]`, we want the address at `rsp` and not its memory
### `syscall`
kernel fills the struct
`[rsp]` = `tv_sec` whole seconds
`[rsp + 8]` = `tv_nsec`, extra nano seconds

returns 0 in `rax`, syscall also overwrites `rcx` and `r11`

### `imul rcx, [rsp], 1000000`
seconds -> microseconds
2 operand perform of `imul` signed multiply reads 8B at `[rsp]` multiply by 1M and stores result at `rcx`, overwriting junk `syscall` left at `rcx`

### `mov rax, [rsp + 8]`
reads memory, `rax` = tv_nsec

### `xor edx, edx`
divides 128b `rdx`:`rax`, so the upper half must be zero
this is before we run `div`
### `mov r8d, 1000`
`div` denominator register, where `r8` is just a free scratch register
`rcx` is already taken holding the seconds part
writing to `r8d` zeroes the upper 48b of `r8` (I think???)
### `div r8`
rax = tv_nsec / 1000
the remainder inside `rdx` being the leftover nanoseconds, which are thrown away
### `add rax, rcx`
total micro seconds = seconds + microseconds part
answer in `rax` the return register
### `add rsp, 24`
free local variable
`rsp` goes back to X - 8, so return address is on the top again
every `sub rsp` must be matched by an `add rsp` before `ret`
### `ret`
pops return address and jumps back to _start `rsp` = X

# file_size Function
`file_size` is never called directly from `_start`, it goes through a small helpper `report_size`

```text
_start  →  report_size  →  file_size
```

## `_start` opens the file and keeps fd in `rbx`
```asm
_start:
	mov     eax, SYS_openat
	mov     rdi, AT_FDCWD
	lea     rsi, [fn_data]                  ; "flush_demo.dat"
	mov     edx, O_WRONLY | O_CREAT | O_TRUNC
	mov     r10d, PERMS
	syscall                                 ; rax = 3 (the new file descriptor)
	test    rax, rax
	js      error
	mov     rbx, rax                        ; rbx = 3 for the rest of the progra
```

`rbx` is callee saved so every function that the program calls leaves it alone, fd stays available the entire time

## `_start` calling `report_size`
```asm
	; stage 1
	rep stosb                       ; fill our 8 MiB buffer
	call    report_size             ; prints: file size the kernel reports: 0 bytes
	...
	; stage 2
	call    xwrite                  ; write() the 8 MiB
	...
	call    report_size             ; prints: file size the kernel reports: 8388608 bytes
```

## `report_size` prints label, calls `file_size` and prints number
```asm
report_size:
	PRINT   msg_size                ; "         file size the kernel reports: "
	mov     rdi, rbx                ; argument 1 for file_size: the fd (3)
	call    file_size               ; → rax = size in bytes
	mov     rdi, rax                ; argument 1 for print_uint: that size
	call    print_uint              ; prints "0" or "8388608"
	PRINT   msg_bytes               ; " bytes\n"
	ret
```

## `file_size` line-by-line
```asm
file_size:
	mov     eax, SYS_fstat
	lea     rsi, [stat_buf]
	syscall
	mov     rax, [stat_buf + ST_SIZE]
	ret
```

### `mov eax, SYS_fstat`
SYS_fstat = 5, `fstat` meaning file status, asks kernel for information about an open file
`rdi` is set from earlier to have `file_size` (I am quite sure??? it is done at `report_size`)

### `lea rsi, [stat_buf]`
2nd arg of syscall (i.e. where the kernel should write its answer)

### `syscall`
kernel looks up fd 3 and fills 144B of `stat_buf` with information about the file
return 0 into `rax` on success

### `mov rax, [stat_buf + ST_SIZE]`
`[]` so it reads memory 8B at address `stat_buf + 48` which is ST_SIZE

### `ret`
back to the caller, which is `report_size` with the size in `rax`

## What's Inside those 144B
| Offset | Field | Bytes | Meaning |
|---|---|---|---|
| 0 | `st_dev` | 8 | which device (disk partition) the file is on |
| 8 | `st_ino` | 8 | inode number: the file's ID on that filesystem |
| 16 | `st_nlink` | 8 | how many names (hard links) point at it |
| 24 | `st_mode` | 4 | file type and permissions (e.g. `0644`) |
| 28 | `st_uid` | 4 | owner's user ID |
| 32 | `st_gid` | 4 | owner's group ID |
| 40 | `st_rdev` | 8 | device number, for device files only |
| **48** | **`st_size`** | **8** | **size in bytes** ← the one we read |
| 56 | `st_blksize` | 8 | preferred I/O block size |
| 64 | `st_blocks` | 8 | how many 512-byte blocks are allocated on disk |
| 72 | `st_atim` | 16 | last access time (seconds + nanoseconds) |
| 88 | `st_mtim` | 16 | last modification time |
| 104 | `st_ctim` | 16 | last status change time |
| 120 | (unused) | 24 | reserved |

# `xwrite` function explained

## Stage 2 of `_start`
```asm
	call    now_us
	mov     r12, rax                ; r12 = start time        ← _start relies on r12
	mov     edi, ebx                ; arg 1: fd (3)           ← _start keeps the fd in rbx
	lea     rsi, [user_buf]         ; arg 2: address of the 8 MiB
	mov     edx, DATA_SIZE          ; arg 3: 8,388,608 bytes
	call    xwrite                  ; → rax = how many bytes were written
	cmp     rax, DATA_SIZE
	jne     write_failed            ; not all of it: fail
```

The usual System V registers on calling `xwrite`:
| Register | Value | Meaning |
|---|---|---|
| `edi` | from `rbx` from the stage 0 `SYS_openat` syscall | the file descriptor |
| `rsi` | address of `user_buf` | where the bytes are |
| `rdx` | 8,388,608 | how many to write |

`rbx` holds the fd from SYS_openat and `r12` holds the start time
a plain `write(fd, buf, n)` is allowed to write fewer than `n` bytes + return smaller count, which is a partial write, common for pipes/sockets/terminals
but for files it happens when a single write is huge, linux caps at 0x7FFFF000 (around under 2GiB), syscall can also be interruped before writing anything

`xwrite` hides all of that, keeping `write()` until every single byte has been accepted or a real error happens

## Save Registers
### `push rbp`
saves caller's `rbp`, where `rbp` is the bottom of the stack frame
### `mov rbp, rsp`
points `rbp` at the **CURRENT** top of the stack
### `push X`
This entire block here:
```asm
    push rbx
    push r12
    push r13
    push r14
```
saves 4 callee-saved registers before overwriting them
`push` instruction decrements stack ptr `rsp` and stores its value at the top of the stack, copying a register's value onto the stack
matching `pop` and then end copies the values back in
This matters because our `xwrite` function is about to use `rbx` and `r12` for its own variables, we are pushing from `_start` where `rbx` holds fd from SYS_openat and start time from `r12`, if we didn't save these values returning to `_start` would read the wrong file + garbage time, so `pop` at the end from the caller's perspective has the illsusion that the registers were untouched, which is why `r13` and `r14` are also saved (which I am also so fucking confused about???)

## Setting Up The Variables
### `mov r12d, edi`
this is the fd, it never changes, on Linux x86-64 a fd is 32b hence `r12d`
### `mov r13, rsi`
`__s`, the next byte to send, starts at the address of `user_buf`, moves forward after a partial write
### `mov r14, rdx`
`__n` the original total, starts at 8MiB (i.e. 8 * 1024 * 1024)
this never changes, it is kept constant
### `mov rbx, rdx`
`__nleft` initialized to `__n`, the bytes still left to send, starts at 8MiB, shrinking after every write

## The Loop
```asm
.loop:
    ; write()
	mov     eax, SYS_write
	mov     edi, r12d
	mov     rsi, r13
	mov     rdx, rbx
	syscall

	cmp     rax, -EINTR
	je      .loop               ; interrupted: continue

	test    rax, rax
	js      .error              ; real error: break

	sub     rbx, rax            ; __nleft -= __ret
	jz      .done               ; if (__nleft == 0) break

	add     r13, rax            ; __s += __ret  (the kernel took only part)
	jmp     .loop
```

### `write(fd, s, nleft)`
arguments are reloaded from variables on every pass
### `cmp rax, -EINTR`
interrupted?? EINTR=4, this error means a signal arrived while the kernel was waiting, and nothing was written
a "signal", being a notification the kernel delivers to a process, e.g. a timer, a child process ending Ctrl+Z then `fg`, etc...
### `je .loop`
the correct response is to try again

### `test rax, rax` + `js .error`
any other negative value is a real error

### `sub rbx, rax` + `jz .done`
subtract what was accepted from what's left
if nothing is left then job is done

### `add r13, rax`
partial write, move to the ptr **PAST** the bytes already sent
without this, the next `write()` will send from the start of the buffer again
### `jmp .loop`
then loop to send the rest

## Closing Out
```asm
.error:
    neg eax
    mov [g_errno], eax
```
only reached from `js .error`, storing positive error number in `g_errno` so the caller can find out why it failed
no `jmp` after so falls through to `.done`, which is delibirate since error still needs return value + `pop` back everything

```asm
.done:
    mov rax, r14
    sub rax, rbx
```
return value being the bytes actually written (original total - bytes left)
on success that's a full 8MiB, after error it is how ever many bytes before failing

```asm
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
```

restores saved registers in reverse order, last value pushed is first to be popped
