# designs/eclass_gf180/config/config_mc_rstsyncf.mk — M3.5, FILLED variant.
#
# Identical to config_mc_rstsync.mk plus USE_FILL=1, mirroring how pvfix2f related to pvfix2.
#
# WHY IT EXISTS: density is measured on the FILLED database, not the routed one. The unfilled
# rstsync GDS measured 388,526 density violations, which is expected and is not a defect — metal
# fill is what closes density, and it is inserted by this variant. The pvfix2 campaign measured
# that fill closes Metal4/Metal5/Top completely and costs nothing in timing or area, while M1-M3
# remained ">30% over the entire die", which is a CHIP-INTEGRATION obligation rather than something
# a block can close on its own. This run re-measures both facts against the reset-synchronized
# build rather than inheriting them.
include /work/designs/eclass_gf180/config/config_mc_rstsync.mk

export DESIGN_NICKNAME = eclass_gf180_rstsyncf
export USE_FILL = 1
