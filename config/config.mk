# designs/eclass_gf180/config/config.mk — M3: CORE ONLY, no SRAM macros (those are M4).
export DESIGN_NAME     = mkeclass_axi4lite
export DESIGN_NICKNAME = eclass_gf180
export PLATFORM        = gf180

IP = /work/ip/cores/eclass
export VERILOG_FILES = $(filter-out %mkTb.v, $(wildcard $(IP)/gen/vlog/*.v)) \
                       $(wildcard $(IP)/gen/prims/*.v)
export SDC_FILE = /work/designs/eclass_gf180/config/constraint.sdc

# 9-track. This IS the platform default (TRACK_OPTION ?= 9t) but is pinned explicitly per the
# project's documented-defaults-are-not-implicit-behavior rule. Measured in M2: 9t is 20.7% larger
# than 7t, and the research measured 7t as 1.35-1.38x SLOWER at realistic loads. fmax is the
# objective, so 9t wins.
export TRACK_OPTION = 9t
export METAL_OPTION = 5LM_1TM
export POWER_OPTION = 5v0

# NOTE: DONT_USE_CELLS is set unconditionally by the gf180 platform config (`=`, not `?=`) to
# `*_1`, so drive-1 cells are banned here whether or not we say so. We deliberately do NOT try to
# override it. CONSEQUENCE: M2's synthesis numbers used the UNFILTERED liberty and therefore
# permitted drive-1 cells, so M3 will not reproduce M2's areas exactly. See DATASHEET.md.

# The platform also sets MAX_FANOUT = 20 during synthesis. M2 (raw yosys, no fanout constraint)
# measured signal nets at 357/346/277 fanout; ORFS will split those during synthesis, so the M3
# netlist is expected to differ structurally from the M2 one. That is the point -- E-class is
# drive-limited, and this is the first lever that attacks it.

# Floorplan initialization. REQUIRED: ORFS aborts with "No floorplan initialization method
# specified" without one of DIE_AREA/CORE_AREA or CORE_UTILIZATION. These mirror the anchor in
# agent/pda/designs.py so a bare `make` and a `run_pda` run start from the same floorplan --
# the registry default is NOT visible to a direct make invocation.
export CORE_UTILIZATION   = 40
export CORE_ASPECT_RATIO  = 1.0
export CORE_MARGIN        = 2.0

export PLACE_DENSITY = 0.40
