# designs/eclass_gf180/config/config_mc_pvfix2.mk
#
# The M3 signed-off configuration PLUS the two ORFS gf180 PLATFORM fixes that the real
# GlobalFoundries KLayout deck forced (reports/SIGNOFF_CLOSURE.md §5). Nothing else changes, so any
# QoR delta against the 25.0 MHz signoff is attributable to these two knobs and nothing else.
#
# Both platform variables are declared `?=` in gf180/config.mk, so they are overridden here rather
# than by patching the shared platform — this project does not own those files, and a local patch
# would silently un-apply on any image rebuild.
#
#   ITERATION 2. Iteration 1 used `-split_cuts {Metal3 0.62}` and DID clear via2/via3/comp — but it
#   introduced 51,680 NEW `M3.2a` (min metal3 spacing 0.28um) violations, because splitting cuts
#   gives every cut its OWN Metal3 enclosure rectangle and at pitch 0.62 neighbouring rects land
#   0.10um apart: too far to merge, too close to be legal. Measured rect width = 0.62 - 0.10 = 0.52.
#   Pitch 0.84 clears BOTH: cut spacing 0.58 (>= 0.36, V3.2b) and metal3 gap 0.32 (>= 0.28, M3.2a),
#   with a 5-column span of 3.88um inside the 4.48um M4 strap.
#   LESSON BAKED IN: a DRC fix must be re-verified against the WHOLE deck, not the rule it targeted.
#
#   FIX 1 — via2/via3 size (103,360 violations, rules V2.1/V3.1 "via must be exactly 0.26um").
#   The stock PDN uses `-split_cuts {Metal3 0.128}`. split_cuts is a PITCH, and 0.128 is HALF the
#   0.26 cut, so cuts overlap by 0.132 (DEF: `CUTSPACING -264`) and merge into 0.772 x 1.028 bars.
#   0.62 = 0.26 cut + 0.36 array spacing (V3.2b applies: this is a 5x7 array).
#
#   FIX 2 — well/substrate tap distance (51,214 violations, rules DF.13_MV/DF.14_MV, limit 15um
#   because these are 5V mcu9t5v0 cells; the 20um _LV figure does NOT apply). Stock tapcell.tcl
#   uses `-distance 100`, so worst-case COMP-to-tap is ~50um. Pitch must be <= 2 x 15 = 30um;
#   25 leaves margin.
#
# EXPECTED SIDE EFFECTS, stated up front so they are not mistaken for regressions:
#   - Many more tap cells (4x the tap rows) -> higher physical-cell count and some area/utilization
#     pressure. The design closed at 51% utilization, so there is room, but this needs re-measuring.
#   - Larger, properly-spaced PDN via arrays -> slightly different routing resources on Metal2-4.
#   - The routed database is invalidated: this REQUIRES a full re-run from floorplan through GDS,
#     followed by a repeat of the multi-corner signoff AND a repeat of the foundry DRC.
include /work/designs/eclass_gf180/config/config_mc.mk

export DESIGN_NICKNAME = eclass_gf180_pvfix2
export PDN_TCL     = /work/designs/eclass_gf180/config/pv_fix/pdn_9t_pvfix.cfg
export TAPCELL_TCL = /work/designs/eclass_gf180/config/pv_fix/tapcell_pvfix.tcl
