/* RESETPC is 4096 (0x1000) per config/eclass_asic32.inc and the tb's resetpc tie-off. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS { . = 0x1000; .text : { *(.text) } }
