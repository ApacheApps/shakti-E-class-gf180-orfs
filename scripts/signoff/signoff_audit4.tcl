# designs/eclass_gf180/scripts/signoff_audit4.tcl
# One loose end from audit3: it reported "42 removal violators" because that is how many lines
# `report_check_types -violators` printed. A printed count is not a measured count -- if that
# command caps its output, the real number is larger and the dossier understates the finding.
#
# This enumerates EVERY removal check individually and counts the negative ones directly, so the
# number in the dossier comes from arithmetic over all endpoints rather than from a report's
# line count.
set NICK [expr {[info exists ::env(SIGNOFF_NICK)] ? $::env(SIGNOFF_NICK) : "eclass_gf180_mc"}]
set R /work/results/gf180/$NICK/base
set P /OpenROAD-flow-scripts/flow/platforms/gf180/lib
set CELL gf180mcu_fd_sc_mcu9t5v0

define_corners c1ss c2tt c3ff
read_liberty -corner c1ss $P/${CELL}__ss_125C_4v50.lib.gz
read_liberty -corner c2tt $P/${CELL}__tt_025C_5v00.lib.gz
read_liberty -corner c3ff $P/${CELL}__ff_n40C_5v50.lib.gz
read_db $R/6_final.odb

# Same filtered-SDC trick as audit3, with the same abort guard.
set fh [open $R/6_final.sdc r]; set txt [read $fh]; close $fh
regsub -all {\\\s*\n\s*} $txt " " txt
set kept {}; set dropped 0
foreach line [split $txt "\n"] {
  if {[string match "*set_false_path*RST_N*" $line]} { incr dropped; continue }
  lappend kept $line
}
if {$dropped < 1} { puts "ABORT: RST_N false path not dropped; refusing to measure"; exit 1 }
set fo [open /tmp/nfp.sdc w]; puts $fo [join $kept "\n"]; close $fo
read_sdc /tmp/nfp.sdc
foreach c {c1ss c2tt c3ff} { read_spef -corner $c $R/6_final.spef }
set_propagated_clock [all_clocks]

puts "=========== D1. EVERY REMOVAL CHECK, COUNTED ==========="
# -endpoint_count is a very large number so nothing is truncated; -slack_max 0 keeps only the
# negative ones. If the true violator count exceeded 42, this will say so.
puts "async pins total: [llength [all_registers -async_pins]]"

# Count negative-slack removal endpoints by asking for a huge path list and tallying.
set paths [find_timing_paths -path_delay min -to [all_registers -async_pins] \
                             -group_path_count 100000 -slack_max 0]
puts "REMOVAL endpoints with slack < 0 : [llength $paths]"
set worst 0.0
foreach p $paths { set s [get_property $p slack]; if {$s < $worst} { set worst $s } }
puts "worst removal slack              : $worst"

set setups [find_timing_paths -path_delay max -to [all_registers -async_pins] \
                              -group_path_count 100000 -slack_max 0]
puts "RECOVERY endpoints with slack < 0: [llength $setups]"
puts "=========== D1 END ==========="
