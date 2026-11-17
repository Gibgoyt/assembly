# stack_demo.gdb

# shows rip, rsp, rbp, the next instruction at the top of the stack

set disassembly-flavor intel
set pagination off

starti

display/i $rip
display/x $rip
display/x $rsp
display/x $rsp
display/x $rbp
display/6gx $rsp
