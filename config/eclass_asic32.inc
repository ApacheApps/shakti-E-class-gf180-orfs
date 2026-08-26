# ip/cores/eclass/config/eclass_asic32.inc
# Our ASIC configuration, derived from upstream templates/synth32.inc — the ONLY template family
# that sets MUL=asic and SYNTH=ASIC. All four non-synth templates set MUL=fpga, which pulls in a
# Xilinx mult_gen_0 BVI import. This file is documentation of intent; scripts/gen.sh is the
# executable form (we call bsc directly rather than upstream's Makefile — see spec AMENDMENT 1).
# THESE TWO MUST BE KEPT IN SYNC BY HAND.
ISA        = RV32IMAC
MUL        = asic
SYNTH      = ASIC
COREFABRIC = AXI4Lite
SYNTHTOP   = mkeclass_axi4lite
MULSTAGES  = 4        # NOTE: binary on ASIC. The unroll rule hardcodes `rg_count[1] != 4`, so
                      # MULSTAGES 4 and 8 are IDENTICAL hardware. Only 0 (combinational) vs
                      # non-zero (sequential) changes structure. M2 sweeps 0 vs non-zero.
DIVSTAGES  = 32
PADDR      = 32
RESETPC    = 4096
CAUSESIZE  = 6
DTVEC_BASE = 0
PMP        = enable
PMPSIZE    = 4
TRIGGERS   = enable
TRIGGER_NUM= 2
COUNTERS   = 4
USER       = enable
USERTRAPS  = enable
DEBUG      = disable  # USER DECISION 2026-08-23 (option (a)) after M1 MEASURED that DEBUG=enable
                      # makes EBREAK non-compliant: mcause=2 (illegal instruction) instead of
                      # mcause=3 (breakpoint). A debug-off rebuild of identical source removed the
                      # mismatch. Not waivable under M1-G4 (JTAG/software breakpoints reach EBREAK),
                      # so M2/M3 characterise and close the COMPLIANT configuration. Restoring JTAG
                      # debug is an M5 item and carries this defect as a known blocker.
                      # See sim/RESULTS/COMPLIANCE.md -> DEVIATION: ebreak.S
VERBOSITY  = 0
