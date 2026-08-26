# designs/eclass_gf180/config/constraint.sdc — M3: ONE clock domain, on a TOP-LEVEL PORT.
#
# Design rule (spec §4): every clock enters as a top-level port; dividers and clock gates live in
# the parent. There are deliberately NO generated clocks here -- an internally-rooted generated
# clock silently loses all its timing arcs in write_timing_model, and it is what cost mlkem_gf180
# a 19-hour hold-repair run.
#
# gf180 liberty declares `time_unit : 1ns`, so every number here is NANOSECONDS.
# 40.0 = 25 MHz = the commit target (spec §2.5).
create_clock -name clk -period 40.0 [get_ports CLK]

# ---------------------------------------------------------------------------------------------
# Clock uncertainty: SETUP and HOLD are budgeted SEPARATELY, and deliberately so.
#
# Run 1 applied a single 0.5 ns uncertainty to both, which is a modelling error: it demanded 0.5 ns
# of HOLD margin on every path in the design. Setup uncertainty budgets clock jitter plus design
# margin (0.5 ns = 1.25% of a 40 ns period); hold uncertainty budgets only on-chip skew estimation
# error, for which 0.5 ns is wildly pessimistic and would force large, purposeless buffer trees.
# Run 1's hold violation was -0.075 ns against that 0.5 ns -- i.e. the physics was already fine and
# the constraint was wrong. 0.1 ns is retained as a real (not token) hold margin.
set_clock_uncertainty -setup 0.5 [get_clocks clk]
set_clock_uncertainty -hold  0.1 [get_clocks clk]

set_input_delay  4.0 -clock clk [all_inputs -no_clocks]
set_output_delay 4.0 -clock clk [all_outputs]

# Reset is an asynchronous top-level input; it is buffered as a broadcast net (M2 measured RST_N
# fanout at 1468) and must not be timed as a data path.
set_false_path -from [get_ports RST_N]

# ---------------------------------------------------------------------------------------------
# Design-rule constraints. REQUIRED, and their absence is what broke run 1.
#
# The gf180 liberty carries no default_max_transition in its header -- the 2.80 ns limit lives as a
# per-pin attribute -- and the platform's MAX_FANOUT=20 applies to SYNTHESIS ONLY. So the resizer
# was free to leave a placement-inserted buf_16 driving 193 sinks (net1489), which measured 9.12 ns
# slew post-route: 1303 max-slew violations.
#
# Constraining them here makes repair_design build real buffer trees during placement. The target
# sits below the 2.80 ns library limit on purpose, to leave headroom for the slew degradation that
# only appears once real routed parasitics are extracted.
#
# TUNING HISTORY (measured, not guessed):
#   run 1: no constraint  -> 1303 violators, worst 9.12 ns (a buf_16 driving 193 sinks)
#   run 2: 2.0            -> 853 flagged vs the 2.0 target, but only 28 exceed the 2.80 LIBRARY
#                            limit, worst 2.91 ns -- all on the reset tree (net6514: a buf_20
#                            driving 97 sinks). Typical nets landed at 2.01-2.13, i.e. repair
#                            hits this target accurately; the reset tree was the outlier because
#                            its placement-time slew estimate understated the routed result.
#   run 3: 1.6            -> chosen so the same ~1.46x placement-to-routed degradation lands the
#                            worst case near 2.3 ns, comfortably inside 2.80.
set_max_transition 1.6 [current_design]

# NOTE: set_max_fanout is retained for documentation but is NOT the binding lever on gf180 --
# measured: net6514 carries fanout 97 while report_check_types -max_fanout reports zero violators,
# so the library's fanout_load does not make this check bind. max_transition is what actually
# drives repair_design here.
set_max_fanout 20 [current_design]
