# stack_demo: rip, rsp, rbp and stack frames

## What the program does

In C, `stack_demo.asm` looks something like this:

```c
long square_plus (
    long a,
    long b
) {
    long s = a*a;
    long t = s + b;

    return t;
}

long outer (
    long x
) {
    long r = square_plus(x, 5);

    return r + x;
}

/* _start: a push/pop demo, then exit(outer(3)) */
```

`outer(3)` = `square_plus(3, 5) + 3` = `(3*3 + 5) + 3` = **17**.

```bash
make stack_demo
./stack_demo; echo $?      # prints nothing, then 17 (the exit code)
```

## The three registers

| Register | Holds | Changes when |
|----------|-------|--------------|
| `rip` | address of the **next** instruction to run | after every instruction (moves forward by its length); `jmp`, `call`, `ret` set it directly |
| `rsp` | address of the **top of the stack**: the most recently pushed value | `push`, `pop`, `call`, `ret`, `sub rsp`, `add rsp`, `mov rsp, ...` |
| `rbp` | address of the **base of the current function's frame** | only when code sets it (function prologue and epilogue) |

The stack grows **downward**: pushing makes `rsp` smaller, popping makes it larger.
The "top" of the stack is its **lowest** used address.

| Instruction | Does |
|-------------|------|
| `push X` | `rsp -= 8`, then `[rsp] = X` |
| `pop R` | `R = [rsp]`, then `rsp += 8` |
| `call f` | `push` the address of the next instruction (the return address), then `rip = f` |
| `ret` | `rip = [rsp]`, then `rsp += 8` (pops the return address into `rip`) |

## Setup: two terminals

**Terminal 1: gdb**

```bash
gdb -q -x stack_demo.gdb ./stack_demo
```

`starti` stops the program before its first instruction. Then:

- `si`: run **one** instruction (steps into `call`s)
- Enter on its own: repeat the last command
- `ni`: like `si`, but runs a whole `call` as one step

After each step gdb prints the `display` list:

```
44      push 0x22        ← the source line ABOUT TO RUN (not yet executed)
1: x/i $rip
=> 0x401044 <_start+2>: push 0x22      ← same: the next instruction
2: /x $rip = 0x401044                  ← where the CPU is
3: /x $rsp = 0x7fffffffdb28            ← top of the stack
4: /x $rbp = 0x0                       ← base of the current frame
5: /x $rax = ...
6: x/6xg $rsp                          ← 6 values starting at the top
0x7fffffffdb28: 0x0000000000000011  0x0000000000000001
```

The instruction shown is always the **next** one. The values shown are the
result of the instruction that **just** ran.

**Terminal 2: watching from outside the process**

While gdb has the program paused, the process exists and the kernel will
describe it:

```bash
pid=$(pidof stack_demo)
cat /proc/$pid/maps                        # every memory region of the process
grep VmStk /proc/$pid/status               # how big the stack region is
```

Read the top of the stack directly from the process's memory, without gdb
(replace the address with the current `rsp` from terminal 1):

```bash
rsp=0x7fffffffdb28
sudo dd if=/proc/$pid/mem bs=8 skip=$(( rsp / 8 )) count=6 2>/dev/null | od -A x -t x8   # as 8-byte values
sudo dd if=/proc/$pid/mem bs=8 skip=$(( rsp / 8 )) count=2 2>/dev/null | od -A x -t x1   # as single bytes
```

The byte view shows `11 00 00 00 00 00 00 00`: x86-64 stores the lowest byte
first (little-endian).

What terminal 2 is for in this program:

- confirm `rsp` lies inside the `[stack]` line of `maps`
- see the same bytes gdb shows, read straight from memory
- `maps` does **not** change while this program runs: the stack region is already
  big enough. It will change in the heap demo, when a `[heap]` line appears.

## The memory map

`cat /proc/$pid/maps` while paused:

```
00400000-00401000 r--p 00000000 103:05 16832873   .../memory-lab/stack_demo
00401000-00402000 r-xp 00001000 103:05 16832873   .../memory-lab/stack_demo
7ffff7ff7000-7ffff7ffb000 r--p 00000000 00:00 0   [vvar]
7ffff7ffb000-7ffff7ffd000 r--p 00000000 00:00 0   [vvar_vclock]
7ffff7ffd000-7ffff7fff000 r-xp 00000000 00:00 0   [vdso]
7ffffffde000-7ffffffff000 rw-p 00000000 00:00 0   [stack]
ffffffffff600000-ffffffffff601000 --xp 00000000 00:00 0   [vsyscall]
```

Columns: address range, permissions (`r`ead `w`rite e`x`ecute, `p`rivate),
offset into the file, device (major:minor), inode, name.

| Region | What it is |
|--------|------------|
| `00400000` `r--p` | start of the executable file: the ELF header |
| `00401000` `r-xp` | `.text`: the code. Read + execute, never write |
| `[vvar]`, `[vvar_vclock]` | read-only data the kernel shares with every process (used for fast clock reads) |
| `[vdso]` | a small piece of kernel-provided code mapped into every process (lets `clock_gettime` run without a real syscall) |
| `[stack]` | the stack: read + write, no execute. `0x21000` bytes = 132 KiB right now; grows on demand up to `ulimit -s` (8 MiB by default) |
| `[vsyscall]` | an old, fixed-address page kept for very old programs |

Not listed: no `.data`, `.bss` or `[heap]`, because this program uses none.
A region only exists when something needs it. The kernel's own memory (the top
half of the address space, from `0xffff800000000000`) is never listed.

Compared with the classic 32-bit picture: same order (code low, stack high),
different addresses. Code starts at `0x400000` instead of `0x08048000`, and the
stack sits just below `0x7ffffffff000` instead of `0xC0000000`.

Under gdb the stack is always near `0x7fffffffdb30`, because gdb turns off
address randomization (ASLR). Outside gdb the stack address changes on every run.

## Step 1: `push 0x11`

```text
(gdb) si
_start () at stack_demo.asm:44
44      push 0x22   ; rsp -= 8, then store 0x22 at [rsp]
1: x/i $rip
=> 0x401044 <_start+2>: push   0x22
2: /x $rip = 0x401044
3: /x $rsp = 0x7fffffffdb28
4: /x $rbp = 0x0
6: x/6xg $rsp
0x7fffffffdb28: 0x0000000000000011  0x0000000000000001
0x7fffffffdb38: 0x00007fffffffe008  0x0000000000000000
0x7fffffffdb48: 0x00007fffffffe045  0x00007fffffffe059
```

What happened:

- `push 0x11` ran: `rsp` went from `0x7fffffffdb30` to `0x7fffffffdb28`
  (`0xdb30 - 8 = 0xdb28`), and `0x11` was stored there. It is the first value in
  the `x/6xg` dump.
- `rip` moved from `0x401042` (`_start`) to `0x401044` (`_start+2`).
  `push 0x11` is 2 bytes of machine code (`6a 11`), so `rip` advanced by 2.
- `rbp` is 0: no function has set up a frame yet.

The other five values were put there **by the kernel** before `_start` ran.
This is the starting stack every Linux program gets:

| Address | Value | Meaning |
|---------|-------|---------|
| `db28` | `0x11` | pushed by step 1 |
| `db30` | `0x1` | `argc`: 1 argument (the program's own name) |
| `db38` | `0x7fffffffe008` | `argv[0]`: pointer to the string `"/home/ahmed/.../stack_demo"` |
| `db40` | `0x0` | NULL: end of the `argv` list |
| `db48` | `0x7fffffffe045` | `envp[0]`: pointer to the first environment variable |
| `db50` | `0x7fffffffe059` | `envp[1]`: the second one |

Check the strings in gdb:

```
(gdb) x/s 0x7fffffffe008      → the program's path
(gdb) x/s 0x7fffffffe045      → e.g. "SHELL=/bin/bash"
```

That is where C's `main(int argc, char **argv, char **envp)` gets its arguments.
The strings themselves live at the very top of the `[stack]` region.

## All steps: what to look for

Addresses are from this machine under gdb (start `rsp = 0x7fffffffdb30`).
Stack addresses are shortened to their last 4 hex digits: `db28` = `0x7fffffffdb28`.

| Step | Just ran | `rip` now | `rsp` | `rbp` | Look for |
|------|----------|-----------|-------|-------|----------|
| 0 | (start) | `_start` | `db30` | 0 | `[rsp]` = argc = 1 |
| 1 | `push 0x11` | `_start+2` | `db28` | 0 | `rsp` −8, `[db28] = 0x11` |
| 2 | `push 0x22` | `_start+4` | `db20` | 0 | `rsp` −8, `[db20] = 0x22` |
| 3 | `pop rax` | `_start+5` | `db28` | 0 | `rax = 0x22` (last in, first out), `rsp` +8 |
| 4 | `pop rbx` | `_start+6` | `db30` | 0 | `rsp` back where it started |
| 5 | `mov edi, 3` | `_start+11` | `db30` | 0 | argument 1 ready |
| 6 | `call outer` | `outer` | `db28` | 0 | **`rip` jumped**; `[db28] = 0x401052` = return address `_start+16` |
| 7 | `push rbp` | `outer+1` | `db20` | 0 | caller's `rbp` (0) saved at `db20` |
| 8 | `mov rbp, rsp` | `outer+4` | `db20` | `db20` | **`rbp` set**: outer's frame base |
| 9 | `sub rsp, 16` | `outer+8` | `db10` | `db20` | 16 bytes reserved for locals |
| 10 | `mov [rbp-8], rdi` | `outer+12` | `db10` | `db20` | `x = 3` stored at `db18` (`db20 - 8`) |
| 11 | `mov esi, 5` | `outer+17` | `db10` | `db20` | argument 2 ready |
| 12 | `call square_plus` | `square_plus` | `db08` | `db20` | `[db08] = 0x401039` = return address `outer+22` |
| 13 | `push rbp` | `square_plus+1` | `db00` | `db20` | outer's `rbp` (`0x7fffffffdb20`) saved at `db00` |
| 14 | `mov rbp, rsp` | `square_plus+4` | `db00` | `db00` | square_plus's frame base |
| 15 | `sub rsp, 16` | `square_plus+8` | `daf0` | `db00` | room for `s` and `t` |
| 16 | `mov rax, rdi` | `square_plus+11` | `daf0` | `db00` | `rax = 3` |
| 17 | `imul rax, rdi` | `square_plus+15` | `daf0` | `db00` | `rax = 9` |
| 18 | `mov [rbp-8], rax` | `square_plus+19` | `daf0` | `db00` | `s = 9` at `daf8` |
| 19 | `add rax, rsi` | `square_plus+22` | `daf0` | `db00` | `rax = 0xe` (14) |
| 20 | `mov [rbp-16], rax` | `square_plus+26` | `daf0` | `db00` | `t = 14` at `daf0`. **Deepest point**, see below |
| 21 | `mov rax, [rbp-16]` | `square_plus+30` | `daf0` | `db00` | return value in `rax` |
| 22 | `mov rsp, rbp` | `square_plus+33` | `db00` | `db00` | locals freed in one step |
| 23 | `pop rbp` | `square_plus+34` | `db08` | `db20` | **`rbp` back to outer's frame** |
| 24 | `ret` | `outer+22` | `db10` | `db20` | **`rip` jumped back** into outer |
| 25 | `add rax, [rbp-8]` | `outer+26` | `db10` | `db20` | `x` read back from the stack: `rax = 0x11` (17) |
| 26 | `mov rsp, rbp` | `outer+29` | `db20` | `db20` | outer's locals freed |
| 27 | `pop rbp` | `outer+30` | `db28` | 0 | `rbp` back to 0 |
| 28 | `ret` | `_start+16` | `db30` | 0 | back in `_start`, `rsp` exactly where it started |
| 29 | `mov edi, eax` | `_start+18` | `db30` | 0 | exit code = 17 |
| 30 | `mov eax, 60` | `_start+23` | `db30` | 0 | syscall number for exit |
| 31 | `syscall` | | | | gdb: `exited with code 021` (021 is octal: 17) |

## The deepest point (step 20)

Run `x/8gx $rsp` here:

```
address  value             meaning                          frame
db28     0x401052          return address → _start+16       ┐
db20     0x0               _start's saved rbp               │ outer
db18     0x3               x            [outer rbp - 8]     │
db10     (padding)         keeps rsp 16-byte aligned        ┘
db08     0x401039          return address → outer+22        ┐
db00     0x7fffffffdb20    outer's saved rbp     ← rbp      │ square_plus
daf8     0x9               s            [rbp - 8]           │
daf0     0xe               t            [rbp - 16] ← rsp    ┘
```

- A **stack frame** is the block of stack one function call uses: return address,
  saved `rbp`, local variables.
- **Prologue** (start of a function) builds it:
  `push rbp` / `mov rbp, rsp` / `sub rsp, N`.
- **Epilogue** (end) removes it: `mov rsp, rbp` / `pop rbp` / `ret`.
- Locals are addressed from `rbp` (`[rbp - 8]`), because `rbp` stays fixed while
  `rsp` moves with every push.
- `outer`'s `x` survives the call at `db18`. `rdi` would not: any function may
  overwrite it. **That is why local variables live on the stack.**

## The rbp chain and `bt`

Each frame's `[rbp]` holds the previous frame's `rbp`, and `[rbp + 8]` holds that
frame's return address:

```
rbp = db00 → [db00] = db20 → [db20] = 0      (0 = end of the chain)
             [db08] = outer+22   [db28] = _start+16
```

`bt` in gdb walks exactly this chain:

```
#0  square_plus () at stack_demo.asm:...
#1  0x0000000000401039 in outer () ...
#2  0x0000000000401052 in _start () ...
```

## gdb cheat sheet

| Command | Does |
|---------|------|
| `starti` | start and stop before the first instruction |
| `si` | one instruction, into calls |
| `ni` | one instruction, over calls |
| `x/8gx $rsp` | 8 values (8 bytes each, hex) from the top of the stack |
| `x/gx $rbp-8` | the local at `rbp - 8` |
| `x/s ADDR` | the string at an address |
| `p $rax` | print a register (decimal); `p/x $rax` in hex |
| `bt` | the call chain |
| `info frame` | details of the current frame |
| `info proc mappings` | same as `/proc/PID/maps` |
| `quit` | exit gdb |

## Experiments

1. At step 20, compare `x/8gx $rsp` with the table above.
2. At step 20, in terminal 2, read the same 8 values with `dd ... | od -t x8`.
3. Remove `push rbp` / `pop rbp` from `square_plus`, rebuild, step into it and
   run `bt`. The chain is broken, so the backtrace goes wrong.
