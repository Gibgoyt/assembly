# Tools
AS      := nasm
ASFLAGS := -f elf64 -g -F dwarf
LD      := ld

# Every .asm file in this folder is a program: hello.asm -> hello
SRCS    := $(wildcard *.asm)
PROGS   := $(SRCS:.asm=)

.PHONY: all clean
.SECONDARY:

# make            -> build every program
all: $(PROGS)

# make hello      -> hello.asm -> hello.o -> hello
%: %.o
	$(LD) $< -o $@

%.o: %.asm
	$(AS) $(ASFLAGS) $< -o $@

# make clean-hello -> remove just hello and hello.o
clean-%:
	$(if $(filter $*,$(PROGS)),rm -f $* $*.o,@echo "no program called '$*'")

# make clean      -> remove every program and object
clean:
	rm -f $(PROGS) $(PROGS:=.o)
