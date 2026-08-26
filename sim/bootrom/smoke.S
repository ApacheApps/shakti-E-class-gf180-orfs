# ip/cores/eclass/sim/bootrom/smoke.S
# Ten instructions with a known-at-compile-time result. No memory ops beyond the final store,
# so a failure isolates to fetch+decode+ALU rather than the load/store path.
    .section .text
    .globl _start
_start:
    li   x1, 5              # x1 = 5
    li   x2, 7              # x2 = 7
    add  x3, x1, x2         # x3 = 12
    sub  x4, x3, x1         # x4 = 7
    slli x5, x4, 2          # x5 = 28
    xori x6, x5, 0xF        # x6 = 28 ^ 15 = 19
    and  x7, x6, x3         # x7 = 19 & 12 = 0
    ori  x8, x7, 0x7AB      # x8 = 0x7AB (0xABC would be ILLEGAL: I-type imm is 12-bit SIGNED, max 2047)
    li   x9, 0x10000000     # signature address (BFM watches this)
    sw   x8, 0(x9)          # store 0xABC -> BFM reports the SMOKE result
1:  j    1b
