# designs/eclass_gf180/config/config_mc.mk — M3 multi-corner, CORE ONLY (no SRAM macros).
#
# WHY THIS FILE EXISTS: the gf180 platform defaults `CORNER ?= BC` (ff_n40C_5v50 cells +
# FuncRCmin extraction). On mlkem_gf180 that default silently synthesized, placed, repaired and
# REPORTED an entire flow at the FAST corner; real 3-corner STA later showed SS setup -31.4 ns.
# This config makes the FLOW ITSELF optimize at SS and bind hold at FF.
#
# read_liberty.tcl fact: with CORNERS set, the flow loads ONLY <CORNER>_LIB_FILES per corner
# (NOT LIB_FILES / ADDITIONAL_LIBS). Corner names MUST sort SLOW FIRST (c1ss < c2tt < c3ff) so
# that SS is the command/setup corner.

include /work/designs/eclass_gf180/config/config.mk

export DESIGN_NICKNAME = eclass_gf180_mc

export CORNERS = c1ss c2tt c3ff
export C1SS_LIB_FILES = $(WC_LIB_FILES)
export C2TT_LIB_FILES = $(TC_LIB_FILES)
export C3FF_LIB_FILES = $(BC_LIB_FILES)
# M4 will append the SRAM macro's matching per-corner .lib to each of the three lists above.

# Single-corner knobs (CORNER) still drive RCX rules / TEMPERATURE / VOLTAGE / set_wire_rc.
export CORNER = WC

# Pin CTS defaults explicitly (project mandate: documented-defaults-are-not-implicit-behavior --
# ORFS stage TCLs only pass an arg when the env var EXISTS, so an unset knob falls through to the
# tool's internal behaviour, NOT the documented default). Worth +437ps WNS on ibex-class designs.
export CTS_CLUSTER_SIZE = 30
export CTS_CLUSTER_DIAMETER = 100
export CTS_BUF_DISTANCE = 100

# Give hold repair a positive target rather than aiming at exactly zero, so that post-route
# parasitic extraction cannot push a marginally-met path back into violation.
export HOLD_SLACK_MARGIN = 0.05
