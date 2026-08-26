// ip/cores/eclass/sim/tb_eclass_arch.sv
// RISCOF DUT harness: run one riscv-arch-test image on the generated E-class netlist and write the
// signature RISCOF compares against Spike's.
//
// Everything that varies per test arrives as a plusarg, so one compiled binary runs the whole suite:
//   +memfile=<hex>   one 32-bit LE word per line (bin2hex.py), loaded at MEM_BASE
//   +resetpc=<hex>   ELF entry point (rvtest_entry_point)
//   +sigbegin=<hex>  begin_signature   (from nm)
//   +sigend=<hex>    end_signature     (from nm)
//   +sigout=<path>   signature file to write
//   +timeout=<dec>   optional cycle cap
//
// Halt is detected as a store to HALT_ADDR, which our env/model_test.h RVMODEL_HALT performs.
// That is deliberately simpler and more observable than decoding HTIF tohost.
`timescale 1ns/1ps
module tb_eclass_arch;
  // 4 MiB per BFM. Sized from the real worst case, not a guess: rv32i_m/I/jal-01.S has a
  // .text.init of 0x1acc72 (~1.75 MiB) because the jal tests span the full +/-1 MiB jump range.
  // A 1 MiB array aborted that test with "$readmem file address beyond bounds of array".
  localparam int    WORDS    = 1 << 20;
  localparam [31:0] MEM_BASE = 32'h8000_0000;      // matches env/link.ld and spike's default map
  localparam [31:0] HALT_ADDR= 32'h1000_0000;      // outside memory: observed via wr_seen

  logic CLK = 0, RST_N = 0;
  always #5 CLK = ~CLK;

  integer cycles = 0;
  int unsigned timeout = 2_000_000;
  logic [31:0] resetpc_i = 32'h8000_0000;
  logic [31:0] sig_begin = 0, sig_end = 0;
  logic        dump_req = 0;
  int          post_dump = 0;
  string       memfile;

  initial begin
    if (!$value$plusargs("memfile=%s", memfile)) begin
      $display("tb_eclass_arch: FATAL +memfile is required"); $finish;
    end
    if (!$value$plusargs("resetpc=%h", resetpc_i))
      $display("tb_eclass_arch: WARNING no +resetpc, defaulting to 0x%08x", resetpc_i);
    if (!$value$plusargs("sigbegin=%h", sig_begin) || !$value$plusargs("sigend=%h", sig_end)) begin
      $display("tb_eclass_arch: FATAL +sigbegin and +sigend are required"); $finish;
    end
    void'($value$plusargs("timeout=%d", timeout));
    repeat (20) @(posedge CLK);
    RST_N = 1;
  end

  logic [31:0] bfm0_araddr, bfm0_awaddr, bfm0_wdata, bfm0_rdata, bfm0_wr_addr, bfm0_wr_data;
  logic [3:0]  bfm0_wstrb;  logic [1:0] bfm0_bresp, bfm0_rresp;
  logic bfm0_arvalid, bfm0_arready, bfm0_awvalid, bfm0_awready, bfm0_wvalid, bfm0_wready;
  logic bfm0_bvalid, bfm0_bready, bfm0_rvalid, bfm0_rready, bfm0_wr_seen;

  logic [31:0] bfm1_araddr, bfm1_awaddr, bfm1_wdata, bfm1_rdata, bfm1_wr_addr, bfm1_wr_data;
  logic [3:0]  bfm1_wstrb;  logic [1:0] bfm1_bresp, bfm1_rresp;
  logic bfm1_arvalid, bfm1_arready, bfm1_awvalid, bfm1_awready, bfm1_wvalid, bfm1_wready;
  logic bfm1_bvalid, bfm1_bready, bfm1_rvalid, bfm1_rready, bfm1_wr_seen;

  // ONE shared memory for both masters (see axil_mem2_bfm.sv): stores through the data port must
  // be visible to instruction fetch, which is precisely what rv32i_m/Zifencei exercises.
  axil_mem2_bfm #(.WORDS(WORDS), .MEM_BASE(MEM_BASE)) mem_bfm (
    .clk(CLK), .rst_n(RST_N),
    .a_araddr(bfm0_araddr), .a_arvalid(bfm0_arvalid), .a_arready(bfm0_arready),
    .a_rdata(bfm0_rdata), .a_rresp(bfm0_rresp), .a_rvalid(bfm0_rvalid), .a_rready(bfm0_rready),
    .a_awaddr(bfm0_awaddr), .a_awvalid(bfm0_awvalid), .a_awready(bfm0_awready),
    .a_wdata(bfm0_wdata), .a_wstrb(bfm0_wstrb), .a_wvalid(bfm0_wvalid), .a_wready(bfm0_wready),
    .a_bresp(bfm0_bresp), .a_bvalid(bfm0_bvalid), .a_bready(bfm0_bready),
    .b_araddr(bfm1_araddr), .b_arvalid(bfm1_arvalid), .b_arready(bfm1_arready),
    .b_rdata(bfm1_rdata), .b_rresp(bfm1_rresp), .b_rvalid(bfm1_rvalid), .b_rready(bfm1_rready),
    .b_awaddr(bfm1_awaddr), .b_awvalid(bfm1_awvalid), .b_awready(bfm1_awready),
    .b_wdata(bfm1_wdata), .b_wstrb(bfm1_wstrb), .b_wvalid(bfm1_wvalid), .b_wready(bfm1_wready),
    .b_bresp(bfm1_bresp), .b_bvalid(bfm1_bvalid), .b_bready(bfm1_bready),
    .wr_seen(bfm1_wr_seen), .wr_addr(bfm1_wr_addr), .wr_data(bfm1_wr_data),
    .dump_req(dump_req), .sig_begin(sig_begin), .sig_end(sig_end));

  assign bfm0_wr_seen = 1'b0;   // fetch port never writes

`include "dut_binding.svh"

  // NOTE: both BFMs load +memfile themselves (see axil_mem_bfm's initial block). The TB reads the
  // plusarg only to fail fast with a clear message when it is missing.

  always @(posedge CLK) if (RST_N) begin
    cycles <= cycles + 1;

    if (bfm1_wr_seen && bfm1_wr_addr == HALT_ADDR && !dump_req) begin
      $display("tb_eclass_arch: HALT after %0d cycles", cycles);
      dump_req <= 1;
    end

    if (cycles > timeout && !dump_req) begin
      $display("tb_eclass_arch: TIMEOUT after %0d cycles (no halt store); last fetch araddr=0x%08x",
               cycles, bfm0_araddr);
      dump_req <= 1;                 // dump anyway: a partial signature is more diagnostic than none
    end

    // give the BFM's dump block a few cycles to complete, then stop
    if (dump_req) post_dump <= post_dump + 1;
    if (post_dump > 4) $finish;
  end
endmodule
