# designs/eclass_gf180/scripts/signoff_audit5.tcl — M3.5 G5, the milestone gate.
#
# HOW THIS DIFFERS FROM audit4, and why the difference is the whole point:
#   audit4 had to DROP the blanket `set_false_path -from [get_ports RST_N]` in order to see past it,
#   because that constraint disabled recovery and removal on all 1,450 async pins. It then measured
#   42 removal endpoints below zero.
#   audit5 must NOT drop anything. After M3.5 the false path is legitimate and covers exactly 3
#   pins -- the synchronizer's own flops, whose asynchronous release genuinely cannot be timed. The
#   measurement is only meaningful with that constraint IN FORCE.
#
# So audit4 asserted "I dropped something"; audit5 asserts "the thing I did not drop covers exactly
# 3 pins". Both are guards against measuring the wrong configuration and calling it clean.

set NICK [expr {[info exists ::env(SIGNOFF_NICK)] ? $::env(SIGNOFF_NICK) : "eclass_gf180_rstsync"}]
set R /work/results/gf180/$NICK/base
set P /OpenROAD-flow-scripts/flow/platforms/gf180/lib
set CELL gf180mcu_fd_sc_mcu9t5v0

define_corners c1ss c2tt c3ff
read_liberty -corner c1ss $P/${CELL}__ss_125C_4v50.lib.gz
read_liberty -corner c2tt $P/${CELL}__tt_025C_5v00.lib.gz
read_liberty -corner c3ff $P/${CELL}__ff_n40C_5v50.lib.gz
read_db $R/6_final.odb
read_sdc $R/6_final.sdc
foreach c {c1ss c2tt c3ff} { read_spef -corner $c $R/6_final.spef }
set_propagated_clock [all_clocks]

puts "=========== E1. FALSE-PATH SCOPE ==========="
# Join backslash continuations BEFORE matching. A per-line match once dropped nothing and the
# design was then "measured" with the false path still active -- a near-miss false clean.
set fh [open $R/6_final.sdc r]; set txt [read $fh]; close $fh
regsub -all {\\\s*\n\s*} $txt " " txt
set fps {}
foreach line [split $txt "\n"] {
  if {[string match "*set_false_path*RST_N*" $line]} { lappend fps $line }
}
if {[llength $fps] != 1} {
  puts "ABORT: expected exactly 1 RST_N false path in the emitted SDC, found [llength $fps]"
  exit 1
}
set fp [lindex $fps 0]
if {![string match "*-to*" $fp]} {
  puts "ABORT: the emitted RST_N false path has NO -to clause -- it is still BLANKET, disabling"
  puts "       recovery and removal on every async pin. Refusing to report a clean."
  exit 1
}
# Count the pins named in the -to clause. get_pins appears once per pin in write_sdc output.
set to [string range $fp [expr {[string first "-to" $fp] + 3}] end]
set npins [regexp -all {get_pins} $to]
if {$npins != 3} {
  puts "ABORT: emitted false path covers $npins pins, expected exactly 3 (the synchronizer)."
  puts "       $fp"
  exit 1
}
puts "FALSE PATH IN FORCE: 3 pins"
puts $fp

puts "=========== E2. EVERY REMOVAL AND RECOVERY CHECK, COUNTED ==========="
# Same method as audit4: a huge group_path_count so nothing is truncated, -slack_max 0 to keep only
# the negatives, and the count taken by arithmetic over endpoints rather than from a report's line
# count. A printed count is not a measured count.
puts "async pins total: [llength [all_registers -async_pins]]"

set paths [find_timing_paths -path_delay min -to [all_registers -async_pins] \
                             -group_path_count 100000 -slack_max 0]
puts "REMOVAL endpoints with slack < 0 : [llength $paths]"
set worst 0.0
foreach p $paths { set s [get_property $p slack]; if {$s < $worst} { set worst $s } }
puts "worst removal slack              : $worst"

set setups [find_timing_paths -path_delay max -to [all_registers -async_pins] \
                              -group_path_count 100000 -slack_max 0]
puts "RECOVERY endpoints with slack < 0: [llength $setups]"
set rworst 0.0
foreach p $setups { set s [get_property $p slack]; if {$s < $rworst} { set rworst $s } }
puts "worst recovery slack             : $rworst"

puts "=========== E3. THE WORST REMOVAL PATH, SHOWN ==========="
# Printed whether or not it violates: the point is to SEE that launch and capture now share the
# clock insertion delay, which is the structural reason the check passes.
report_checks -path_delay min -to [all_registers -async_pins] \
              -group_path_count 1 -fields {slew cap input net fanout} -format full_clock_expanded

puts "=========== E END ==========="
