# designs/eclass_gf180/config/config_mc_rstsync.mk -- M3.5.
#
# The pvfix2 configuration (M3 signoff + the two GF-deck platform fixes) with EXACTLY ONE change:
# the hardened top is now eclass_top, which wraps the byte-identical core with a 3-stage reset
# synchronizer, and the SDC scopes the RST_N false path to that synchronizer's 3 pins instead of
# blanketing all 1,450.
#
# Everything else -- clock period, uncertainties, I/O delays, max_transition, PDN, tapcell pitch,
# corners, CTS pinning, hold margin, utilization, image -- is inherited unchanged, so any QoR delta
# is attributable to the reset synchronizer alone. Same discipline as the pvfix2 campaign.
#
# The two GF-deck platform fixes are inherited via config_mc_pvfix2.mk and remain in force:
#   PDN_TCL     -> -split_cuts {Metal3 0.84}   (via2/via3, 103,360 violations)
#   TAPCELL_TCL -> tapcell -distance 25        (comp-to-tap, 51,214 violations)
include /work/designs/eclass_gf180/config/config_mc_pvfix2.mk

export DESIGN_NAME     = eclass_top
export DESIGN_NICKNAME = eclass_gf180_rstsync

# The wrapper and the synchronizer live in rtl/, deliberately OUTSIDE gen/: gen/ is covered by
# MANIFEST.sha256 with a "byte-reproducible from bsc" contract, and our own RTL must never land
# there. Wrapper first for readability.
IP = /work/ip/cores/eclass
export VERILOG_FILES = $(IP)/rtl/eclass_top.sv \
                       $(IP)/rtl/eclass_reset_sync.sv \
                       $(filter-out %mkTb.v, $(wildcard $(IP)/gen/vlog/*.v)) \
                       $(wildcard $(IP)/gen/prims/*.v)

export SDC_FILE = /work/designs/eclass_gf180/config/constraint_rstsync.sdc
