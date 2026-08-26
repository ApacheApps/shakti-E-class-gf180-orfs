# designs/eclass_gf180/scripts/mc_signoff.tcl
# Multi-corner signoff STA on the FINAL routed database, with EXTRACTED PARASITICS.
#
# Two lessons from mlkem_gf180 are baked in:
#  1. read_spef is mandatory. A signoff run on estimated RC is not signoff -- mlkem measured a
#     0.7 ns gap between estimated and extracted, which sent a hold-repair pass into a
#     22,000-buffer runaway.
#  2. Clocks must be PROPAGATED, not ideal, or CTS insertion delay and skew are invisible.
# Design nickname is overridable so the same signoff script certifies config variants
# (e.g. the counters-off experiment) rather than being copy-pasted per run.
set NICK [expr {[info exists ::env(SIGNOFF_NICK)] ? $::env(SIGNOFF_NICK) : "eclass_gf180_mc"}]
set R /work/results/gf180/$NICK/base
set P /OpenROAD-flow-scripts/flow/platforms/gf180/lib
set CELL gf180mcu_fd_sc_mcu9t5v0

define_corners c1ss c2tt c3ff
read_liberty -corner c1ss $P/${CELL}__ss_125C_4v50.lib.gz
read_liberty -corner c2tt $P/${CELL}__tt_025C_5v00.lib.gz
read_liberty -corner c3ff $P/${CELL}__ff_n40C_5v50.lib.gz

read_db  $R/6_final.odb
read_sdc $R/6_final.sdc
foreach c {c1ss c2tt c3ff} { read_spef -corner $c $R/6_final.spef }
set_propagated_clock [all_clocks]

puts "=========== WORST ACROSS ALL CORNERS ==========="
# With define_corners in effect, the default report is already the worst across every corner --
# which IS the signoff criterion. (`-corner` is not a flag on report_worst_slack/report_tns; the
# per-corner attribution comes from report_checks below, which prints the corner it used.)
puts "SETUP:"
report_worst_slack -max -digits 3
report_tns -max -digits 3
puts "HOLD:"
report_worst_slack -min -digits 3
report_tns -min -digits 3
puts "=========== WORST SETUP PATH ==========="
report_checks -path_delay max -group_count 2 -digits 3
puts "=========== WORST HOLD PATH ==========="
report_checks -path_delay min -group_count 2 -digits 3
puts "=========== DRV vs the OPTIMIZATION TARGET (SDC set_max_transition) ==========="
# The SDC carries a target TIGHTER than the library requires (1.6 ns vs the library's 2.80 ns).
# That margin exists only to drive repair_design hard enough that the routed result lands inside
# the library limit. Pins between the two numbers are NOT signoff violations.
report_check_types -max_slew -max_capacitance -max_fanout -violators

puts "=========== DRV vs the LIBRARY LIMIT  <<< THIS IS THE SIGNOFF CRITERION >>> ==========="
# 2.80 ns is the gf180 cells' own max_transition attribute -- the real constraint. Relaxing the
# report to it is not moving the goalposts: it is reporting against the limit that actually binds,
# after having optimized against a deliberately tighter one.
set_max_transition 2.80 [current_design]
report_check_types -max_slew -max_capacitance -max_fanout -violators
