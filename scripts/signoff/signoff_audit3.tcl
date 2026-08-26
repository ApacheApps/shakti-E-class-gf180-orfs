# designs/eclass_gf180/scripts/signoff_audit3.tcl
# Audit2 established two things: check_setup is genuinely checking (negative control B1 fired on
# all 187 input ports when no SDC was read), and min_pulse_width IS evaluated (C0 reports a real
# +19.055 ns MET slack) -- so those clean results are evidence, not silence.
#
# What remained unmeasured is recovery/removal on the async reset network. `set_false_path -from
# [get_ports RST_N]` disables those checks, so "no violators" proves nothing while it is in force.
#
# ⚠️ FIRST ATTEMPT AT THIS SCRIPT WAS WRONG AND REPORTED A FALSE CLEAN. The flow writes the
# constraint across two lines with a backslash continuation:
#     set_false_path\
#         -from [get_ports {RST_N}]
# so a per-line match on "*set_false_path*RST_N*" never fired, the filter dropped nothing, and the
# measurement ran with the false path still active. Line continuations are now joined BEFORE
# filtering, and the script ABORTS if it fails to drop anything -- a zero-match must never again be
# mistaken for a lifted constraint.
set NICK [expr {[info exists ::env(SIGNOFF_NICK)] ? $::env(SIGNOFF_NICK) : "eclass_gf180_mc"}]
set R /work/results/gf180/$NICK/base
set P /OpenROAD-flow-scripts/flow/platforms/gf180/lib
set CELL gf180mcu_fd_sc_mcu9t5v0

define_corners c1ss c2tt c3ff
read_liberty -corner c1ss $P/${CELL}__ss_125C_4v50.lib.gz
read_liberty -corner c2tt $P/${CELL}__tt_025C_5v00.lib.gz
read_liberty -corner c3ff $P/${CELL}__ff_n40C_5v50.lib.gz
read_db $R/6_final.odb

# Join backslash continuations, THEN filter. Everything except the reset false path is carried
# over verbatim, so that constraint is the only variable between this run and signoff.
set fh [open $R/6_final.sdc r]; set txt [read $fh]; close $fh
regsub -all {\\\s*\n\s*} $txt " " txt
set kept {}; set dropped 0
foreach line [split $txt "\n"] {
  if {[string match "*set_false_path*RST_N*" $line]} { incr dropped; continue }
  lappend kept $line
}
puts "FILTERED SDC: dropped $dropped false-path statement(s) matching RST_N"
if {$dropped < 1} {
  puts "ABORT: expected to drop the RST_N false path and dropped nothing."
  puts "       Measuring recovery/removal now would report a FALSE CLEAN. Refusing."
  exit 1
}
set fo [open /tmp/no_false_path.sdc w]; puts $fo [join $kept "\n"]; close $fo

read_sdc /tmp/no_false_path.sdc
foreach c {c1ss c2tt c3ff} { read_spef -corner $c $R/6_final.spef }
set_propagated_clock [all_clocks]

puts "=========== C1. ASYNC PIN CENSUS ==========="
puts "async (set/reset) pins: [llength [all_registers -async_pins]]"
puts "=========== C1 END ==========="

puts "=========== C2. RECOVERY / REMOVAL WITH THE FALSE PATH GENUINELY LIFTED ==========="
puts "--- recovery violators ---"
report_check_types -recovery -violators -digits 3
puts "--- removal violators ---"
report_check_types -removal -violators -digits 3
puts "=========== C2 END ==========="

puts "=========== C3. WORST RECOVERY AND REMOVAL PATHS (regardless of violation) ==========="
puts "--- worst recovery (max) into async pins ---"
report_checks -path_delay max -to [all_registers -async_pins] -group_path_count 3 -digits 3
puts "--- worst removal (min) into async pins ---"
report_checks -path_delay min -to [all_registers -async_pins] -group_path_count 3 -digits 3
puts "=========== C3 END ==========="

puts "=========== C4. RESET-NETWORK SLACK SUMMARY ==========="
# The headline numbers, so the reset network can be quoted the same way setup/hold are.
puts "recovery worst slack:"
report_worst_slack -max -digits 3
puts "removal worst slack:"
report_worst_slack -min -digits 3
puts "=========== C4 END ==========="
