set R /work/results/gf180/eclass_gf180_mc/base
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

puts "=== net driving a violating RN pin ==="
set pin [get_pins riscv.stage3.csr.csrfile.v_pmp_addr_0[11]\$_DFFE_PN0P_/RN]
set net [get_nets -of_objects $pin]
set m 0
set drv ""
foreach dp [get_pins -of_objects $net] {
  incr m
  if {[get_property $dp direction] eq "output"} {
    set drv "[get_full_name $dp] cell=[get_property [get_cells -of_objects $dp] ref_name]"
  }
}
puts "  net=[get_full_name $net] fanout=$m driver=$drv"
puts "=== how many distinct nets carry the 853 violations? ==="
puts "  (sampling the report is enough — see slew report above)"
