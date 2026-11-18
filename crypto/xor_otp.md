# System V Convention Reminder
Consider this
```c
xor_buf(uint8_t *dst, const uint8_t *src, const uint8_t *key, size_t len);
```

| Argument | Register | Meaning |
|----------|----------|---------|
| 1st      | rdi      | dst, the address to write result to |
| 2nd      | rsi      | src,  address of the input bytes |
| 3rd      | rdx      | key, address of the bytes we will XOR with |
| 4th      | rcx      | len, how many bytes |

# `xor_buf` Function Explained
loop through src: byte i of src XOR byte i of the key gives byte i of dst

```nasm
xor_buf:
    xor     r8d, r8d
.loop:
    cmp     r8, rcx
    jae     .done
    mov     al, [rsi + r8]
    xor     al, [rdx + r8]
    mov     [rdi + r8], al
    inc     r8
    jmp     .loop
.done:
    ret
```

## On `call`
```nasm
    lea rdi, [c1]        ; dst = address of c1 (14 empty bytes in .bss)
    lea rsi, [msg1]      ; src = address of "attack at dawn" in .rodata
    lea rdx, [key]       ; key = address of the 14 random bytes
    mov ecx, MSG_LEN     ; len = 14
    call xor_buf         ; push return address, jump
```
`al` (lowest byte of `rax`) is the scratch register throughout `xor_buf`, holding the one byte being worked on
`rdi` has the **address** of dst, where the ciphertext gets written
`rsi` has the **address** of src, the message that we are looping through (original plaintext)
`rdx` has the **address** of the key
`rcx` is len, the message length (equal to the key length here)
`r8` is i
`rdi`, `rsi`, `rdx`, `rcx` never change inside the loop, only `r8` and `al` do

### `xor r8d, r8d`
sets i=0, in this case it is the loop counter XOR with itself always = 0 (self-inversion, see XOR Mathematics below)
32b r8d zeroes all 64b
caller-saved scratch register that is **NOT** one of the 4 args, using it destroys nothing that the function needs

### `.loop`
A local label, really named `xor_buf.loop`, used to `jmp` to

### `cmp r8, rcx`
compares `i` with `len`, since `rcx` is length (computes `r8 - rcx`, keeps only the flags)

### `jae .done`
if `i>=len` then leave the loop
`jae` is unsigned, which is okay since `i` or `len` are never ever negative

### `mov al, [rsi + r8]`
`al` = src[i]
`rsi` stores the start of the message, and we know that `r8` is `i`, so `rsi + r8` is the address of byte i
from the caller, `rsi` is the message, so we are looping through the message (i.e. `src`)

### `xor al, [rdx + r8]`
`al = al ^ key[i]`
**`r8`, not `8`**: `[rdx + 8]` would always read key[8]

### `mov [rdi + r8], al`
`dst[i]` now stores the result of that single XOR from `src`

### `inc r8`
i++

### `jmp .loop`
go back and check conditions again

### `.done:` + `ret`
returns to the caller
pops return address that `call` pushed into `rip`

# `print_hex` Function Explained
prints bytes as hex text, raw 14B becomes 42 chars
equivalent function in C:
```c
void print_hex (
    const uint8_t *bytes,
    size_t len
) {
    char *out = hexbuf;
    for (
        size_t i=0; i<len; i++
    ) {
        out[0] = "012...def"[bytes[i] >> 4];    // high nibble
        out[1] = "012...def"[bytes[i] & 0x0F];  // low nibble
        out[2] = ' ';
        out += 3;
    }
    out[-1] = '\n';
    write(1, hexbuf, out - hexbuf);
}
```

`rsi` 1st arg, address of bytes to print out
`rdx` being the length of how many bytes

## On Calling `print_hex`
```nasm
    lea rsi, [c1]       ; address of dst ciphertext
    mov edx, MSG_LEN    ; len = 14
    call print_hex
```
`rsi` has the address of the bytes, this never changes inside the loop
`rdx` is the length of the bytes to print, also never changes inside the loop
`rdi` is the write cursor, that points at where the next char goes into `hexbuf`, unlike `xor_buf` the register itself moves (+3 per byte iterated over)
`r9` has the address of `hexdigits` table
`rcx` is `i`
`rax`/`al` holds the byte then its low nibble
`r8` holds the high nibble, then its char

### `lea rdi, [hexbuf]`
`rdi` being the address of hexbuf (42B that are completely empty in .bss section) where the text goes, it is the cursor, starting at the beginning and moving forward 3 per byte

### `lea r9, [hexdigits]`
`r9` being the address of the table, needed because `default rel` sets rip-relative addresses (i.e. `rip` + offset) and that encoding has no slot for an index register, so `[hexdigits + r8]` can not be encoded. If we put the base into a register first, `[r9 + r8]` works

### `xor ecx, ecx`
i=0, `rcx` is a free register since `print_hex` only has 2 args that it uses

### `.loop:`
local label, `print_hex.loop`, a different label from `xor_buf.loop`

### `cmp rcx, rdx` + `jae .done`
if `i >= len`, same pattern as `xor_buf`

### `movzx eax, byte [rsi + rcx]`
read byte i + zero-extend it into `eax`: bits 8-31 become 0, and because it's a 32b write bits 32-63 of `rax` become 0 too
so all of `rax` = the byte's value, e.g. `rax = 0xe2`
needed because `rax` is used as an index later (`[r9 + rax]`), garbage in the upper bits = wrong address = crash

### `mov r8d, eax`
copy the byte into `r8`, 2 copies, one per nibble
32b write also zeroes top of `r8` which is also used as an index

### `shr r8d, 4`
shift right 4 bits, keep high nibble
$`\texttt{0xe2} \gg 4: \; 1110\,0010 \to 0000\,1110 = 14`$

### `mov r8b, [r9 + r8]`
table lookup, `r8b = hexdigits[14] = 'e'` (0x65). The index `r8` is read first, then its low byte is overwritten with the char (old value not needed any more)

### `mov [rdi], r8b`
write 'e' at the cursor (1B because `r8b` is 1B)

### `and eax, 0x0F`
keep only low 4b (low nibble)
$`1110\,0010 \mathbin{\&} 0000\,1111 = 0000\,0010 = 2`$

### `mov al, [r9 + rax]`
table lookup, `al = hexdigits[2] = '2'`

### `mov [rdi + 1], al`
writes '2' one position after the cursor

### `mov byte [rdi + 2], ' '`
write a space 2 positions after cursor, `byte` tells NASM to write 1B (neither `' '` nor a memory address has a size of its own)

### `add rdi, 3`
moves the cursor past "e2 "

### `inc rcx` + `jmp .loop`
i++, go again

### `mov byte [rdi - 1], 10`
after the loop, `rdi` points one past the last ' ' (space) so `rdi - 1` is that space, overwrite it with 10 (newline)
edge case: if len = 0, `rdi - 1` is the byte before `hexbuf` (last byte of `tmp`), a write outside the buffer. Fine here because len is always 14, but it is a bug in general

### `lea rsi, [hexbuf]` + `mov rdx, rdi` + `sub rdx, rsi`
set up `print(rsi = text, rdx = length)`, length = cursor end - start = $`14 \times 3 = 42`$

### `jmp print`
tail call (same idea as VJMP)
- jump
- push nothing
- `print` does a `ret`, popping the return address that `_start`'s `call print_hex` pushed, returning straight to `_start`. `print_hex` itself never executes a `ret`

---

# XOR Mathematics

## Notation
| Symbol | Read as | Meaning |
|--------|---------|---------|
| $`\forall`$ | "for all" | the statement holds for every value |
| $`\in`$ | "is an element of" | $`A \in S`$: $`A`$ is one of the things in set $`S`$ |
| $`\{0,1\}`$ | "the set 0, 1" | the set of the two bit values |
| $`\{0,1\}^n`$ | "zero-one to the n" | the set of **all bit strings of length $`n`$** |
| $`A_i`$ | "A sub i" | bit $`i`$ of the string $`A`$ |
| $`\oplus`$ | "XOR" | exclusive or (NASM: `xor`) |
| $`\mathbf{0}`$ | "bold zero" | the string of $`n`$ zero bits, $`00\ldots0`$ |
| $`a \bmod m`$ | "a mod m" | the remainder when $`a`$ is divided by $`m`$ |
| $`\equiv \pmod m`$ | "congruent mod m" | both sides have the same remainder when divided by $`m`$ |

## Where $`\{0,1\}^n`$ comes from
The exponent on a set means "pick $`n`$ elements from it, in order". Each pick is one bit, so the result is an $`n`$-bit string:

```math
\{0,1\}^1 = \{0,\, 1\} \qquad \{0,1\}^2 = \{00,\, 01,\, 10,\, 11\} \qquad \{0,1\}^3 = \{000,\, 001,\, \ldots,\, 111\}
```

Each extra bit doubles the count, so the set has $`2^n`$ elements. In this program:

| Thing | Set it belongs to |
|-------|-------------------|
| one byte, e.g. `0x61` | $`\{0,1\}^8`$ ($`2^8 = 256`$ possible values) |
| a 64-bit register, e.g. `rax` | $`\{0,1\}^{64}`$ |
| `key`, `msg1`, `msg2`, `c1`, `c2` (14 bytes each) | $`\{0,1\}^{112}`$ |

So $`\forall A, B \in \{0,1\}^n`$ reads: "for every pair of bit strings $`A`$ and $`B`$, both of length $`n`$". The properties work for strings of any length, as long as both sides are the same length.

## XOR on one bit, defined with mod 2
$`a \bmod 2`$ is the remainder after dividing by 2: $`0 \bmod 2 = 0`$, $`1 \bmod 2 = 1`$, $`2 \bmod 2 = 0`$, $`3 \bmod 2 = 1`$. It's 0 for even numbers and 1 for odd ones.

For bits $`x, y \in \{0,1\}`$:

```math
x \oplus y = (x + y) \bmod 2
```

| $`x`$ | $`y`$ | $`x + y`$ | $`(x + y) \bmod 2 = x \oplus y`$ |
|-----|-----|---------|--------------------------------|
| 0 | 0 | 0 | 0 |
| 0 | 1 | 1 | 1 |
| 1 | 0 | 1 | 1 |
| 1 | 1 | 2 | **0** |

XOR is **addition that throws away the carry**. $`1 + 1 = 10_2`$, keep the 0, drop the carry 1.

The notation $`X \oplus Y \equiv X + Y \pmod 2`$ is also correct maths: $`\equiv`$ with $`\pmod 2`$ at the end says both sides have the same remainder after dividing by 2. For single bits the two forms mean the same thing.

## XOR on strings: bit by bit
For $`A, B \in \{0,1\}^n`$, XOR works on each position separately, with no carries between positions:

```math
(A \oplus B)_i = A_i \oplus B_i \qquad \text{for each } i = 0, 1, \ldots, n-1
```

```math
\begin{array}{lr}
A = \texttt{0x61} & 0110\,0001 \\
B = \texttt{0x83} & 1000\,0011 \\ \hline
A \oplus B = \texttt{0xe2} & 1110\,0010
\end{array}
```

This is why every property below only needs proving for **one bit**: if it holds at every position $`i`$, it holds for the whole string. One `xor rax, rbx` does this for 64 positions at once.

## Not the same as $`\cup`$ (OR)
$`A \cup B`$ is set **union**, which matches bitwise **OR** (`or`). It differs from XOR in exactly one row:

| $`x`$ | $`y`$ | OR $`x \lor y`$ | XOR $`x \oplus y`$ |
|-----|-----|---------------|------------------|
| 1 | 1 | **1** | **0** |

OR is commutative and associative too, but it is **not** self-inverse: $`1 \lor 1 = 1`$. So OR can't undo itself, and you can't decrypt with it. That one row is why ciphers use XOR. (The set operation that does match XOR is the **symmetric difference** $`A \,\triangle\, B`$: the elements in exactly one of the two sets.)

## The four properties, proved

### 1. Identity
```math
\forall A \in \{0,1\}^n, \quad A \oplus \mathbf{0} = A
```

Per bit: $`a \oplus 0 = (a + 0) \bmod 2 = a \bmod 2 = a`$, since $`a`$ is already 0 or 1.
Example: $`\texttt{0x61} \oplus \texttt{0x00} = \texttt{0x61}`$

### 2. Commutativity
```math
\forall A, B \in \{0,1\}^n, \quad A \oplus B = B \oplus A
```

Per bit: $`a \oplus b = (a + b) \bmod 2 = (b + a) \bmod 2 = b \oplus a`$, because ordinary addition doesn't care about order.
Example: $`\texttt{0x61} \oplus \texttt{0x83} = \texttt{0x83} \oplus \texttt{0x61} = \texttt{0xe2}`$

### 3. Associativity
```math
\forall A, B, C \in \{0,1\}^n, \quad (A \oplus B) \oplus C = A \oplus (B \oplus C)
```

Per bit:

```math
(a \oplus b) \oplus c = \big((a + b) \bmod 2 + c\big) \bmod 2 = (a + b + c) \bmod 2
```
```math
a \oplus (b \oplus c) = \big(a + (b + c) \bmod 2\big) \bmod 2 = (a + b + c) \bmod 2
```

Both equal $`(a + b + c) \bmod 2`$. Taking "mod 2" in the middle doesn't change the final answer: it only removes a multiple of 2 (subtracts 2 or 0), and whether the total is even or odd stays the same.

So XOR of any number of bits is 1 exactly when an **odd** number of them are 1, whatever the grouping. All 8 cases:

| $`a`$ | $`b`$ | $`c`$ | $`(a \oplus b) \oplus c`$ | $`a \oplus (b \oplus c)`$ |
|-----|-----|-----|-------------------------|-------------------------|
| 0 | 0 | 0 | $`0 \oplus 0 = 0`$ | $`0 \oplus 0 = 0`$ |
| 0 | 0 | 1 | $`0 \oplus 1 = 1`$ | $`0 \oplus 1 = 1`$ |
| 0 | 1 | 0 | $`1 \oplus 0 = 1`$ | $`0 \oplus 1 = 1`$ |
| 0 | 1 | 1 | $`1 \oplus 1 = 0`$ | $`0 \oplus 0 = 0`$ |
| 1 | 0 | 0 | $`1 \oplus 0 = 1`$ | $`1 \oplus 0 = 1`$ |
| 1 | 0 | 1 | $`1 \oplus 1 = 0`$ | $`1 \oplus 1 = 0`$ |
| 1 | 1 | 0 | $`0 \oplus 0 = 0`$ | $`1 \oplus 1 = 0`$ |
| 1 | 1 | 1 | $`0 \oplus 1 = 1`$ | $`1 \oplus 0 = 1`$ |

Example: $`(\texttt{0x61} \oplus \texttt{0x83}) \oplus \texttt{0x64} = \texttt{0xe2} \oplus \texttt{0x64} = \texttt{0x86}`$, and $`\texttt{0x61} \oplus (\texttt{0x83} \oplus \texttt{0x64}) = \texttt{0x61} \oplus \texttt{0xe7} = \texttt{0x86}`$

Commutativity + associativity together mean: **in a chain of XORs, order and brackets don't matter**. You can rearrange freely.

### 4. Self-inversion
```math
\forall A \in \{0,1\}^n, \quad A \oplus A = \mathbf{0}
```

Per bit: $`a \oplus a = (a + a) \bmod 2 = 2a \bmod 2 = 0`$, because $`2a`$ is always even.
Example: $`\texttt{0x83} \oplus \texttt{0x83} = \texttt{0x00}`$. In asm: `xor edi, edi` sets `edi` to 0.

### Together: XOR undoes itself
These four combine into the one fact all of this lesson uses:

```math
\forall A, B \in \{0,1\}^n, \quad (A \oplus B) \oplus B = A
```

```math
\begin{aligned}
(A \oplus B) \oplus B &= A \oplus (B \oplus B) && \text{associativity} \\
&= A \oplus \mathbf{0} && \text{self-inversion} \\
&= A && \text{identity}
\end{aligned}
```

XOR with $`B`$ once changes $`A`$; XOR with $`B`$ again changes it back.

---

# `_start` Explained
This is where all the business logic for the XOR One-Time Pad lives

|Name|Role|Has the key?|
|----|----|------------|
|Alice|sender + encrypts|yes|
|Bob|receiver + decrypts|yes|
|Eve|eavesdropper (sees all ciphertext over the network)|no|

Threat model: what the attacker can do. Eve is **passive**: she can read everything that was sent over the network, but she can not change it, and she doesn't have the key (she can still compute with what she sees, see Steps 5 and 6)
Kerckhoffs's principle: Eve knows the algorithm (XOR), the only secret is the key that we used. Real crypto works the same way, AES and ChaCha20 are public standards. If security depended on hiding the algorithm, one leak would break it forever. A key can however be replaced

## Setup & Definitions
Let $`p_1, p_2, k \in \{0,1\}^n`$ be bit strings of equal length $`n`$ (here $`n = 112`$, 14 bytes), where:

- $`p_1`$ = `msg1` = "attack at dawn", $`p_2`$ = `msg2` = "defend at dusk"
- $`k`$ = `key`, 14 random bytes
- Encryption of $`p_1`$: $`c_1 = p_1 \oplus k`$
- Encryption of $`p_2`$: $`c_2 = p_2 \oplus k`$

## `_start` Entire Function
```nasm
_start:
    ; ---- 0. key = 14 random bytes -------------------------------
    mov     eax, SYS_getrandom
    lea     rdi, [key]
    mov     esi, MSG_LEN
    xor     edx, edx
    syscall
    cmp     rax, MSG_LEN
    jne     fail

    ; ---- 1. show the key and the plaintext ----------------------
    PRINT   lbl_key
    lea     rsi, [key]
    mov     edx, MSG_LEN
    call    print_hex

    PRINT   lbl_p1
    lea     rsi, [msg1]
    mov     edx, MSG_LEN
    call    print_hex

    ; ---- 2. Alice encrypts: c1 = msg1 ^ key ---------------------
    lea     rdi, [c1]
    lea     rsi, [msg1]
    lea     rdx, [key]
    mov     ecx, MSG_LEN
    call    xor_buf

    PRINT   lbl_c1
    lea     rsi, [c1]
    mov     edx, MSG_LEN
    call    print_hex

    ; ---- 3. Bob decrypts: tmp = c1 ^ key ------------------------
    lea     rdi, [tmp]
    lea     rsi, [c1]
    lea     rdx, [key]
    mov     ecx, MSG_LEN
    call    xor_buf

    PRINT   lbl_d1
    lea     rsi, [tmp]
    mov     edx, MSG_LEN
    call    print_text

    ; ---- 4. the mistake: c2 = msg2 ^ SAME key -------------------
    lea     rdi, [c2]
    lea     rsi, [msg2]
    lea     rdx, [key]
    mov     ecx, MSG_LEN
    call    xor_buf

    PRINT   lbl_c2
    lea     rsi, [c2]
    mov     edx, MSG_LEN
    call    print_hex

    ; ---- 5. Eve: tmp = c1 ^ c2  (no key) ------------------------
    lea     rdi, [tmp]
    lea     rsi, [c1]
    lea     rdx, [c2]
    mov     ecx, MSG_LEN
    call    xor_buf

    PRINT   lbl_x
    lea     rsi, [tmp]
    mov     edx, MSG_LEN
    call    print_hex

    ;      proof only: c2 = msg1 ^ msg2  (Eve can't do this one)
    lea     rdi, [c2]
    lea     rsi, [msg1]
    lea     rdx, [msg2]
    mov     ecx, MSG_LEN
    call    xor_buf

    PRINT   lbl_pp
    lea     rsi, [c2]
    mov     edx, MSG_LEN
    call    print_hex

    ; ---- 6. Eve guesses msg1: c2 = (c1 ^ c2) ^ msg1 = msg2 ------
    lea     rdi, [c2]
    lea     rsi, [tmp]
    lea     rdx, [msg1]
    mov     ecx, MSG_LEN
    call    xor_buf

    PRINT   lbl_rec
    lea     rsi, [c2]
    mov     edx, MSG_LEN
    call    print_text

    xor     edi, edi        ; exit(0)
    mov     eax, SYS_exit
    syscall

fail:
    mov     edi, 1          ; exit(1)
    mov     eax, SYS_exit
    syscall
```

All values here are from a real run, with key `83 6b 6e 95 5c 05 60 f5 75 b6 c4 59 e0 21`

Two rules for all of `_start`:
1. `_start` is not a function, nobody `call`ed it, so there's no return address on the stack and it must never `ret`. It ends with the `exit` syscall instead
2. every `call` sets every argument again, `rdi`, `rsi`, `rdx`, `rcx` are caller-saved, so relying on a leftover value is exactly what crashed with `rdx = 42`

## Step 0: Make the key
```nasm
    mov     eax, SYS_getrandom   ; rax = 318
    lea     rdi, [key]           ; arg 1: buffer = address of key (14 bytes in .bss)
    mov     esi, MSG_LEN         ; arg 2: how many bytes = 14
    xor     edx, edx             ; arg 3: flags = 0 (default behaviour)
    syscall                      ; kernel fills key[0..13]; rax = bytes written or -errno

    cmp     rax, MSG_LEN
    jne     fail                 ; anything but exactly 14 = give up
```

This is a syscall, `rax` = syscall number, `rdi`,`rsi`,`rdx` = syscall args
`jne` (jump if not equal) catches both a negative error and a short fill with one check, never encrypt with a key that might be partly zeros
`getrandom()` reads the kernel's CSPRNG (cryptographically secure pseudo-random number generator), the kernel seeds it from unpredictable hardware events, then runs it through crypto. Never make keys from the time or `rand()`
The key is 14B = 112b, so $`k \in \{0,1\}^{112}`$ and the number of possible keys is
```math
\left|\{0,1\}^{112}\right| = 2^{112} \approx 5.2 \times 10^{33}
```

But even attempting to try every key does not get Eve anything, and Step 2 explains why

## Step 1: Show Key + Plaintext Hex
```nasm
    PRINT   lbl_key              ; expands to: lea rsi,[lbl_key] / mov edx,lbl_key_len / call print
    lea     rsi, [key]
    mov     edx, MSG_LEN
    call    print_hex            ; "83 6b 6e 95 ..."
```

`PRINT` macro pasted via NASM. Hex and not text because key + ciphertext bytes can be any value 0-255, bytes like 0x0a ('\n') or 0x07 (beep) would wreck the terminal, and 0x80-0xff aren't ASCII at all, so let's print as pure hex, showing every byte safely

example, "attack at dawn" as hex:
```text
a  t  t  a  c  k     a  t     d  a  w  n
61 74 74 61 63 6b 20 61 74 20 64 61 77 6e
```

## Step 2: Alice encrypts
```nasm
    lea     rdi, [c1]            ; dst
    lea     rsi, [msg1]          ; src = plaintext
    lea     rdx, [key]           ; key
    mov     ecx, MSG_LEN
    call    xor_buf              ; c1 = msg1 ^ key
```

```math
c_1 = p_1 \oplus k \qquad \text{byte by byte: } c_1[i] = p_1[i] \oplus k[i]
```

| i | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| $`p_1`$ | `a` 61 | `t` 74 | `t` 74 | `a` 61 | `c` 63 | `k` 6b | ` ` 20 | `a` 61 | `t` 74 | ` ` 20 | `d` 64 | `a` 61 | `w` 77 | `n` 6e |
| $`k`$ | 83 | 6b | 6e | 95 | 5c | 05 | 60 | f5 | 75 | b6 | c4 | 59 | e0 | 21 |
| $`c_1`$ | e2 | 1f | 1a | f4 | 3f | 6e | 40 | 94 | 01 | 96 | a0 | 38 | 97 | 4f |

Same letter, different ciphertext: 'a' appears in positions 0, 3, 7, 11, respectively encrypting to `e2`, `f4`, `94`, `38`, since every key byte is different, so the output is different. This kills frequency analysis.
But yes, yes, I hear you "Ahmed what the fuck is frequency analysis???", for example in English 'e', 't', and 'a' are the most common letters, old ciphers always turn those into the same output, so those ciphers can easily be deciphered by counting, but in this cipher it gives absolutely nada my brada
it is perfectly secure

What Eve sees:
$`c_1[0] = \texttt{e2}`$
for any plaintext byte $`p \in \{0,1\}^8`$ she guesses, there is exactly one key byte that would produce it
```math
k[0] = \texttt{e2} \oplus p \qquad \text{check: } p \oplus k[0] = p \oplus (\texttt{e2} \oplus p) = \texttt{e2}
```

Since every key byte was equally likely (i.e. defined at step 0, where we made the key), every plaintext is equally likely. Even trying all $`2^{112}`$ keys is completely useless: some key turns $`c_1`$ into "attack at dawn", another into "defend at dusk", another into "retreat now!!!", every possible 14B message is in the list, and nothing marks the right one.
This is known as Shannon's perfect secrecy, a standard of information-theoretic security introduced by mathematician Claude Shannon ("the father of information theory") in 1949. Anthropic's Claude is widely said to be named after him, though Anthropic hasn't officially confirmed it

```math
\forall p \in \{0,1\}^n,\ \forall c \in \{0,1\}^n, \quad \Pr[P = p \mid C = c] = \Pr[P = p]
```

Seeing the ciphertext does not change what Eve knows about the plaintext, but it is bound by these 3 conditions, if any is broken, then it is no longer perfect
1. key is truly random
2. key is at least as long as the message
3. key is used once

## Step 3: Bob Decrypts

```nasm
    lea     rdi, [tmp]           ; dst
    lea     rsi, [c1]            ; src = ciphertext
    lea     rdx, [key]           ; the same key
    mov     ecx, MSG_LEN
    call    xor_buf              ; tmp = c1 ^ key

    PRINT   lbl_d1
    lea     rsi, [tmp]
    mov     edx, MSG_LEN
    call    print_text           ; text, not hex: it's readable again
```

```math
\begin{aligned}
c_1 \oplus k &= (p_1 \oplus k) \oplus k && \text{definition of } c_1 \\
&= p_1 \oplus (k \oplus k) && \text{associativity} \\
&= p_1 \oplus \mathbf{0} && \text{self-inversion} \\
&= p_1 && \text{identity}
\end{aligned}
```

Byte 0: $`\texttt{e2} \oplus \texttt{83} = \texttt{61}`$ = a
This is symmetric encryption, the same key decrypts and encrypts, and `xor_buf` does both

The problem this shows is that Bob needs the exact 14B key, how does Bob get them??? Alice sending them means anybody can see them! This is the **KEY DISTRIBUTION PROBLEM** which asymmetric cryptography solves, that will be covered later

## Step 4: The Mistake

```nasm
    lea     rdi, [c2]
    lea     rsi, [msg2]          ; "defend at dusk"
    lea     rdx, [key]           ; SAME key
    mov     ecx, MSG_LEN
    call    xor_buf
```

| i | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| $`c_1`$ | e2 | 1f | 1a | f4 | 3f | 6e | **40** | **94** | **01** | **96** | **a0** | 38 | 97 | 4f |
| $`c_2`$ | e7 | 0e | 08 | f0 | 32 | 61 | **40** | **94** | **01** | **96** | **a0** | 2c | 93 | 4a |

Eve learns something before even doing any Math, positions 6 to 10 are identical in both ciphertexts, same key byte and so
```math
c_1[i] = c_2[i] \iff p_1[i] \oplus k[i] = p_2[i] \oplus k[i] \iff p_1[i] = p_2[i]
```

(the second $`\iff`$: XOR both sides with $`k[i]`$, which cancels it by "XOR undoes itself")

She now knows that both messages have the same 5 chars in the middle (i.e. ..." at d"...), so perfect secrecy is already gone

## Step 5: Eve XORs the 2 Ciphertexts

```nasm
    lea     rdi, [tmp]           ; dst
    lea     rsi, [c1]
    lea     rdx, [c2]            ; the OTHER CIPHERTEXT, not the key
    mov     ecx, MSG_LEN
    call    xor_buf              ; tmp = c1 ^ c2
```

### The proof: $`c_1 \oplus c_2 = p_1 \oplus p_2`$

```math
\begin{aligned}
c_1 \oplus c_2 &= (p_1 \oplus k) \oplus (p_2 \oplus k) && \text{1. substitute } c_1, c_2 \\
&= p_1 \oplus \big(k \oplus (p_2 \oplus k)\big) && \text{2a. associativity} \\
&= p_1 \oplus \big((k \oplus p_2) \oplus k\big) && \text{2b. associativity} \\
&= p_1 \oplus \big((p_2 \oplus k) \oplus k\big) && \text{3. commutativity: } k \oplus p_2 = p_2 \oplus k \\
&= p_1 \oplus \big(p_2 \oplus (k \oplus k)\big) && \text{4. associativity} \\
&= p_1 \oplus (p_2 \oplus \mathbf{0}) && \text{5. self-inversion: } k \oplus k = \mathbf{0} \\
&= p_1 \oplus p_2 && \text{6. identity: } p_2 \oplus \mathbf{0} = p_2
\end{aligned}
```

Step 2 is two uses of associativity: first $`(X \oplus Y) \oplus Z = X \oplus (Y \oplus Z)`$ with $`X = p_1`$, $`Y = k`$, $`Z = p_2 \oplus k`$, then $`Y \oplus (Z_1 \oplus Z_2) = (Y \oplus Z_1) \oplus Z_2`$ inside the brackets. The whole proof is just moving the two $`k`$'s next to each other so self-inversion can delete them.

**The key cancels out.** The proof holds $`\forall p_1, p_2, k \in \{0,1\}^n`$, so it's true whatever the key is. Checked on byte 0 of the real run:

```math
c_1[0] \oplus c_2[0] = \texttt{e2} \oplus \texttt{e7} = \texttt{05} \qquad p_1[0] \oplus p_2[0] = \texttt{61} \oplus \texttt{64} = \texttt{05}
```

and per bit, showing the key bits cancelling:

```math
\begin{array}{lr}
c_1[0] = \texttt{e2} & 1110\,0010 \\
c_2[0] = \texttt{e7} & 1110\,0111 \\ \hline
\texttt{05} & 0000\,0101
\end{array}
\qquad
\begin{array}{lr}
p_1[0] = \texttt{61}\ (\texttt{a}) & 0110\,0001 \\
p_2[0] = \texttt{64}\ (\texttt{d}) & 0110\,0100 \\ \hline
\texttt{05} & 0000\,0101
\end{array}
```

The full result:
```text
c1 XOR c2 : 05 11 12 04 0d 0f 00 00 00 00 00 14 04 05
```

"Proof" call computes `msg1 ^ msg2` directly, Eve can not do this because she does not have the original plaintexts, it's only there so we can see the 2 lines match

```text
p1 XOR p2 : 05 11 12 04 0d 0f 00 00 00 00 00 14 04 05
```

`c1 ^ c2` matches `p1 ^ p2` on every single run, whatever the key is, because the key is not in the result

(the `c2` buffer is reused as scratch here, fine because `c2` isn't needed anymore, `tmp` holds what Step 6 needs)

What Eve can read from $`p_1 \oplus p_2`$ alone:
- `00` = same character in both (Step 4's leak, $`x \oplus x = 0`$)
- lowercase letters are `0x61`-`0x7a`, their top 3 bits are both `011` and cancel, so two letters XOR to a small value `0x00`-`0x1f`: `05` = `a` $`\oplus`$ `d`
- a space (`0x20` = `0010 0000`) XOR a lowercase letter gives `0x41`-`0x5a`, which stands out, so spaces reveal where words break

Real text has so much structure that this leak alone is usually enough to recover both messages

## Step 6: Eve Guesses One Message and Gets the Other

```nasm
    lea     rdi, [c2]            ; dst (scratch)
    lea     rsi, [tmp]           ; c1 ^ c2 from Step 5
    lea     rdx, [msg1]          ; Eve's GUESS of message 1
    mov     ecx, MSG_LEN
    call    xor_buf

    PRINT   lbl_rec
    lea     rsi, [c2]
    mov     edx, MSG_LEN
    call    print_text           ; "defend at dusk"
```

```math
\begin{aligned}
(c_1 \oplus c_2) \oplus p_1 &= (p_1 \oplus p_2) \oplus p_1 && \text{Step 5 proof} \\
&= (p_2 \oplus p_1) \oplus p_1 && \text{commutativity} \\
&= p_2 \oplus (p_1 \oplus p_1) && \text{associativity} \\
&= p_2 \oplus \mathbf{0} && \text{self-inversion} \\
&= p_2 && \text{identity}
\end{aligned}
```

A guessed plaintext is called a **crib**. Real traffic is full of them: `"GET / HTTP/1.1"`, `"<html>"`, file headers, a fixed greeting at the start of every message

A partial guess still works. Guess `"attack at noon"` instead:
```text
attacker recovers p2: defend at n{kk
```
every position where the guess is right gives the right letter of message 2 (`defend at `), the wrong ones give junk. Eve guesses one word, checks whether the other message becomes readable there, and slides along: **crib dragging**

And it's worse, a correct guess gives the key itself:

```math
\begin{aligned}
c_1 \oplus p_1 &= (p_1 \oplus k) \oplus p_1 && \text{definition of } c_1 \\
&= (k \oplus p_1) \oplus p_1 && \text{commutativity} \\
&= k \oplus (p_1 \oplus p_1) && \text{associativity} \\
&= k \oplus \mathbf{0} = k && \text{self-inversion, identity}
\end{aligned}
```

Now she can read every message ever sent with that key: a **known-plaintext attack**

## Exit

```nasm
    xor     edi, edi             ; status 0 = success
    mov     eax, SYS_exit
    syscall                      ; never returns

fail:
    mov     edi, 1               ; status 1 = getrandom failed
    mov     eax, SYS_exit
    syscall
```

`echo $?` after the run shows which one happened

---

# Foundations This Lesson Sets Up

| Principle | Seen in | Where it comes back |
|-----------|---------|---------------------|
| The algorithm is public; only the key is secret (Kerckhoffs) | `_start` intro | every cipher |
| Keys come from a CSPRNG, never from time or `rand()` | Step 0 | every key, every nonce |
| Encrypt = XOR with secret bytes; decrypt = XOR again: $`(A \oplus B) \oplus B = A`$ | Steps 2-3 | ChaCha20, AES-CTR, AES-GCM all end this way |
| One-time pad: perfect, but the key must be as long as the data | Step 2 | why we need ciphers that **expand** a short key |
| Bob needs the same key: key distribution problem | Step 3 | asymmetric crypto, key exchange, TLS handshake |
| **Never reuse keystream**: $`c_1 \oplus c_2 = p_1 \oplus p_2`$ | Steps 4-6 | the **nonce** in ChaCha20 / AES-GCM |
| Attackers know or guess plaintext | Step 6 | ciphers must stay secure even then |

How this becomes a real cipher: a one-time pad needs a key as long as the data. Real stream ciphers generate the "pad" from a short key $`k`$ and a **nonce** $`N`$ ("number used once"):

```math
c = p \oplus \text{ChaCha20}(k, N) \qquad k \in \{0,1\}^{256} \text{ (reused)} \qquad N \in \{0,1\}^{96} \text{ (new every message)}
```

Same $`k`$ with a different $`N`$ gives a completely different keystream, so Step 5's cancellation never happens. Same $`k`$ **and** same $`N`$ twice is exactly the attack in this lesson

Preview, encryption alone doesn't stop tampering: if Eve can *change* ciphertext in transit (an *active* attacker), she can flip plaintext bits without the key. For any $`\Delta \in \{0,1\}^n`$:

```math
(c \oplus \Delta) \oplus k = (p \oplus k \oplus \Delta) \oplus k = p \oplus \Delta
```

with $`\Delta = \texttt{"dawn"} \oplus \texttt{"dusk"}`$ on the last 4 bytes, Bob decrypts "attack at dusk". Stopping that needs a **MAC** (message authentication code), the job of GHASH and Poly1305 in the transcript
