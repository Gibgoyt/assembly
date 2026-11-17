# memory_map.gdb  -  stop at every stage of memory_map.asm
#
# Usage:   gdb -q -x memory_map.gdb ./memory_map
#          then:  run          (normal run)
#             or: run null     (crash tests: null, kernel, text, rodata)
#          At each stop:  continue  (or c) goes to the next stage.

set debuginfod enabled off
set disassembly-flavor intel
set pagination off

# "maps" = show this process's memory regions, same as /proc/PID/maps
define maps
  info proc mappings
end

# "results" = everything the program has recorded so far
define results
  printf "rsp at start  = %#lx\n", (long)g_rsp0
  printf "argc          = %ld\n",  (long)g_argc
  printf "auxv at       = %#lx\n", (long)g_auxv
  printf "vdso at       = %#lx\n", (long)g_vdso
  printf "text byte     = %#lx\n", (long)g_text_byte
  printf "counter       = %ld\n",  (long)counter
  printf "heap start    = %#lx\n", (long)g_heap_start
  printf "heap end      = %#lx\n", (long)g_heap_end
  printf "mmap block    = %#lx\n", (long)g_mmap
  printf "deepest rsp   = %#lx\n", (long)g_rsp_deep
  printf "vdso magic    = %#lx\n", (long)g_vdso_magic
end

break stage_args
break stage_text
break stage_rodata
break stage_data
break stage_bss
break stage_heap
break stage_mmap
break stage_stack
break stack_deepest
break stage_vdso
break stage_crash
