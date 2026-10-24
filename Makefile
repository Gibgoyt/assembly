# Tools
AS      := nasm
ASFLAGS := -f elf64 -g -F dwarf
LD      := ld

# Add new programs here, e.g.  PROGS := hello loop math
PROGS   := hello

.PHONY: all clean

all: $(PROGS)

# Link: hello.o -> hello
%: %.o
	$(LD) $< -o $@

# Assemble: hello.asm -> hello.o
%.o: %.asm
	$(AS) $(ASFLAGS) $< -o $@

# Keep the .o files instead of letting make delete them
.SECONDARY: $(PROGS:=.o)

clean:
	rm -f $(PROGS) $(PROGS:=.o)
