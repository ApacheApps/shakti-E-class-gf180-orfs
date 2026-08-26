// ip/cores/eclass/rtl/eclass_reset_sync.sv
//
// Async-assert / sync-deassert reset synchronizer for the E-class core.
//
// WHY THIS EXISTS (measured, not theoretical): mkeclass_axi4lite is bsc output, and bsc expects the
// PARENT to supply a synchronized reset. It does not synchronize RST_N itself, so before this module
// existed, RST_N was a raw port feeding 1,450 async pins directly. Three-corner STA with the blanket
// false path lifted measured 41 removal endpoints below zero, worst -0.622 ns: reset deassertion
// reached those flops ~3.5 ns BEFORE the clock edge did, because the reset tree was 0.684 ns against
// a 4.223 ns clock insertion delay. See reports/SIGNOFF_CLOSURE.md section 2.
//
// CONTAINMENT, not elimination: these STAGES flops are the only ones in the whole design driven by a
// raw asynchronous reset. Metastability lives here, in 3 flops, instead of being spread across 1,450.
//
// Assertion stays ASYNCHRONOUS on purpose -- reset must work with no clock running. Only the
// DEASSERTION is synchronized, which is the edge that was unconstrained.
//
// NOT A METASTABILITY PROOF. We compute no MTBF number: there is no measured metastability window
// (tau, T0) published for gf180mcu_fd_sc_mcu9t5v0 flops, and inventing one would be fabrication.

(* keep_hierarchy *)
module eclass_reset_sync #(
  parameter integer STAGES = 3
) (
  input  wire clk,
  input  wire arst_n,       // asynchronous, active low, released at an arbitrary phase
  output wire rst_n_sync    // async assert, sync deassert
);

  // dont_touch is load-bearing: without it, retiming or resynthesis is free to collapse or
  // restructure this chain, which silently destroys the very margin it exists to provide.
  (* dont_touch = "true" *) reg [STAGES-1:0] eclass_rstsync_q;

  always @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      eclass_rstsync_q <= {STAGES{1'b0}};
    end else begin
      eclass_rstsync_q <= {eclass_rstsync_q[STAGES-2:0], 1'b1};
    end
  end

  assign rst_n_sync = eclass_rstsync_q[STAGES-1];

endmodule
