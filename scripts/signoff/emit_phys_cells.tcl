# designs/eclass_gf180/scripts/emit_phys_cells.tcl
# Emit SPICE lines for EVERY physical-only cell — instances that exist in the layout but never in
# the Verilog netlist, so a schematic built from the Verilog alone cannot know about them.
#
# ⚠️ CORRECTED. The first version emitted only DEVICE-BEARING physical cells (the antenna diodes),
# on the reasoning that fill/tap/endcap contain no transistors and so could not produce extracted
# devices. That reasoning was WRONG, and LVS said so: with only the antennas added it still failed,
# and the cross-reference database listed TEN mismatching circuits, every one of them a physical-only
# cell —
#     ANTENNA, ENDCAP, FILLTIE, FILL_1, FILL_2, FILL_4, FILL_16, FILL_32, ...
# KLayout's LVS builds a circuit for every cell it finds in the layout, whether or not that cell
# contains devices, and expects a matching circuit on the schematic side. "Has no devices" does not
# mean "is invisible to LVS".
#
# Usage: SIGNOFF_NICK=<nick> openroad -exit emit_phys_cells.tcl   (prints SPICE X-lines on stdout)
set NICK [expr {[info exists ::env(SIGNOFF_NICK)] ? $::env(SIGNOFF_NICK) : "eclass_gf180_mc"}]
read_db /work/results/gf180/$NICK/base/6_final.odb
set b [[[::ord::get_db] getChip] getBlock]

# Physical-only masters: everything the router/floorplanner inserts that synthesis never emitted.
set PHYS_PATTERNS {__fill_[0-9]+$ __filltie$ __endcap$ __antenna$ __fillcap_[0-9]+$ __tap}

array set counts {}
set n 0
foreach i [$b getInsts] {
  set m [[$i getMaster] getName]
  set hit 0
  foreach pat $PHYS_PATTERNS { if {[regexp $pat $m]} { set hit 1; break } }
  if {!$hit} { continue }

  # Emit pin=net PAIRS, not a positional list. The LEF MTerm order is NOT guaranteed to match the
  # PDK SPICE .SUBCKT order, and a SPICE subcircuit call is positional -- ordering by the wrong
  # source produces a netlist that parses cleanly and then fails LVS for a reason unrelated to the
  # layout. add_phys_cells.py reorders these against the PDK's own .SUBCKT lines, exactly as
  # v2spice.py does for the logic cells.
  set pairs {}
  foreach mt [[$i getMaster] getMTerms] {
    set pn [$mt getName]
    set net ""
    foreach it [$i getITerms] {
      if {[[$it getMTerm] getName] eq $pn} {
        set nn [$it getNet]
        if {$nn != "NULL"} { set net [$nn getName] }
      }
    }
    if {$net eq ""} { set net "UNCONN_[$i getName]_$pn" }
    lappend pairs "$pn=$net"
  }
  puts "PHYSCELL X[$i getName] $m [join $pairs { }]"
  incr counts($m)
  incr n
}
foreach k [lsort [array names counts]] { puts "PHYSCELL_STAT $counts($k) $k" }
puts "PHYSCELL_COUNT $n"
