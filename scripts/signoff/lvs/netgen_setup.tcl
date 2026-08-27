# LVS step 2a — additions layered on top of the PDK's gf180mcuC_setup.tcl.
# Source this AFTER the PDK setup, from a wrapper setup file handed to `netgen -batch lvs`.
#
# CELL POLICY (see reports/LVS_CELL_POLICY.md — decisions are by DEVICE CONTENT, not appearance):
#   IGNORE, symmetrically and guarded: the device-free physical-only cells. Their PDK .SUBCKT bodies
#   are empty, so ignoring them cannot hide an electrical difference. This mirrors sky130A_setup.tcl,
#   which does exactly this for sky130_fd_sc_*__fill_N / __tapvpwrvgnd_N / __fakediode_N and
#   deliberately does NOT ignore decap (which has real devices).
#   NOT IGNORED: __antenna. 27 instances x 2 REAL diodes, every one on a SIGNAL net. Excluding it
#   would hide 54 devices. Those instances are ADDED to the schematic from layout connectivity.
set fillcells {
  gf180mcu_fd_sc_mcu9t5v0__filltie
  gf180mcu_fd_sc_mcu9t5v0__endcap
  gf180mcu_fd_sc_mcu9t5v0__fill_1  gf180mcu_fd_sc_mcu9t5v0__fill_2
  gf180mcu_fd_sc_mcu9t5v0__fill_4  gf180mcu_fd_sc_mcu9t5v0__fill_8
  gf180mcu_fd_sc_mcu9t5v0__fill_16 gf180mcu_fd_sc_mcu9t5v0__fill_32
  gf180mcu_fd_sc_mcu9t5v0__fill_64
}
foreach c $fillcells {
    if {[lsearch $cells1 $c] >= 0} { ignore class "-circuit1 $c" }
    if {[lsearch $cells2 $c] >= 0} { ignore class "-circuit2 $c" }
}

# MANDATORY. gf180 quirk: the mcu9t5v0 (5 V) standard cells are built from 6V-RATED devices, so the
# PDK cell SPICE says nfet_06v0/pfet_06v0 while magic classifies the same geometry as
# nfet_05v0/pfet_05v0. gf180mcuC_setup.tcl declares both as SEPARATE device classes and never equates
# them, so without this EVERY transistor mismatches on device class alone.
catch {equate classes "-circuit1 nfet_05v0" "-circuit2 nfet_06v0"}
catch {equate classes "-circuit1 pfet_05v0" "-circuit2 pfet_06v0"}
catch {equate classes "-circuit1 nfet_06v0" "-circuit2 nfet_05v0"}
catch {equate classes "-circuit1 pfet_06v0" "-circuit2 pfet_05v0"}
