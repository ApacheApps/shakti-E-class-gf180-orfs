// ip/cores/eclass/sim/tb_eclass_smoke.sv
// Cheapest possible detector of gross breakage in the generated E-class netlist: run ten
// instructions and check the single store they produce. Runs in seconds; gates the ~1-day RISCOF
// investment in Task 8.
//
// Two BFMs because E-class has two AXI4-Lite masters. They hold SEPARATE memories, which is fine
// here on purpose: the program performs no loads, and its one store targets 0x10000000 — far
// outside the data BFM's range — so we observe it via wr_seen rather than by reading it back.
`timescale 1ns/1ps
module tb_eclass_smoke;
  localparam int    WORDS     = 1 << 16;          // 256 KiB per BFM
  localparam int    LOAD_WORD = 32'h1000 >> 2;    // RESETPC 4096, matches the linker script
  localparam [31:0] SIG_ADDR  = 32'h1000_0000;
  localparam [31:0] SIG_EXPECT= 32'h0000_07AB;

  logic CLK = 0, RST_N = 0;
  always #5 CLK = ~CLK;                           // 100 MHz sim clock; timing is irrelevant here

  integer cycles = 0;
  int fd;
  logic [31:0] resetpc_i = 32'h0000_1000;   // matches RESETPC=4096 in eclass_asic32.inc

  // fetch port (read-only) and data port
  logic [31:0] bfm0_araddr, bfm0_awaddr, bfm0_wdata, bfm0_rdata, bfm0_wr_addr, bfm0_wr_data;
  logic [3:0]  bfm0_wstrb;
  logic [1:0]  bfm0_bresp, bfm0_rresp;
  logic bfm0_arvalid, bfm0_arready, bfm0_awvalid, bfm0_awready, bfm0_wvalid, bfm0_wready;
  logic bfm0_bvalid, bfm0_bready, bfm0_rvalid, bfm0_rready, bfm0_wr_seen;

  logic [31:0] bfm1_araddr, bfm1_awaddr, bfm1_wdata, bfm1_rdata, bfm1_wr_addr, bfm1_wr_data;
  logic [3:0]  bfm1_wstrb;
  logic [1:0]  bfm1_bresp, bfm1_rresp;
  logic bfm1_arvalid, bfm1_arready, bfm1_awvalid, bfm1_awready, bfm1_wvalid, bfm1_wready;
  logic bfm1_bvalid, bfm1_bready, bfm1_rvalid, bfm1_rready, bfm1_wr_seen;

  axil_mem_bfm #(.WORDS(WORDS), .READ_ONLY(1),
                 .MEMFILE("bootrom/smoke.hex"), .LOAD_WORD(LOAD_WORD)) bfm0 (
    .clk(CLK), .rst_n(RST_N),
    .awaddr(bfm0_awaddr), .awvalid(bfm0_awvalid), .awready(bfm0_awready),
    .wdata(bfm0_wdata), .wstrb(bfm0_wstrb), .wvalid(bfm0_wvalid), .wready(bfm0_wready),
    .bresp(bfm0_bresp), .bvalid(bfm0_bvalid), .bready(bfm0_bready),
    .araddr(bfm0_araddr), .arvalid(bfm0_arvalid), .arready(bfm0_arready),
    .rdata(bfm0_rdata), .rresp(bfm0_rresp), .rvalid(bfm0_rvalid), .rready(bfm0_rready),
    .wr_seen(bfm0_wr_seen), .wr_addr(bfm0_wr_addr), .wr_data(bfm0_wr_data),
    .dump_req(1'b0), .sig_begin(32'h0), .sig_end(32'h0));

  axil_mem_bfm #(.WORDS(WORDS), .READ_ONLY(0),
                 .MEMFILE("bootrom/smoke.hex"), .LOAD_WORD(LOAD_WORD)) bfm1 (
    .clk(CLK), .rst_n(RST_N),
    .awaddr(bfm1_awaddr), .awvalid(bfm1_awvalid), .awready(bfm1_awready),
    .wdata(bfm1_wdata), .wstrb(bfm1_wstrb), .wvalid(bfm1_wvalid), .wready(bfm1_wready),
    .bresp(bfm1_bresp), .bvalid(bfm1_bvalid), .bready(bfm1_bready),
    .araddr(bfm1_araddr), .arvalid(bfm1_arvalid), .arready(bfm1_arready),
    .rdata(bfm1_rdata), .rresp(bfm1_rresp), .rvalid(bfm1_rvalid), .rready(bfm1_rready),
    .wr_seen(bfm1_wr_seen), .wr_addr(bfm1_wr_addr), .wr_data(bfm1_wr_data),
    .dump_req(1'b0), .sig_begin(32'h0), .sig_end(32'h0));

`include "dut_binding.svh"

  initial begin
    // Log destination is a plusarg so the same TB can produce a core baseline and a wrapper run
    // without one clobbering the other -- otherwise test_wrapper_and_core_agree would be comparing
    // a file with itself, i.e. a test that passes while proving nothing.
    begin
      string logpath;
      if (!$value$plusargs("log=%s", logpath)) logpath = "RESULTS/smoke.log";
      fd = $fopen(logpath, "w");
    end
    repeat (20) @(posedge CLK);
    RST_N = 1;
  end

  always @(posedge CLK) if (RST_N) begin
    cycles <= cycles + 1;

    if (bfm1_wr_seen) begin
      if (bfm1_wr_addr == SIG_ADDR) begin
        if (bfm1_wr_data == SIG_EXPECT)
          $fdisplay(fd, "SMOKE_PASS data=0x%08x cycles=%0d", bfm1_wr_data, cycles);
        else
          $fdisplay(fd, "SMOKE_FAIL data=0x%08x expected=0x%08x", bfm1_wr_data, SIG_EXPECT);
        $fclose(fd); $finish;
      end else begin
        $fdisplay(fd, "note: write to 0x%08x = 0x%08x", bfm1_wr_addr, bfm1_wr_data);
      end
    end

    if (cycles > 100000) begin
      $fdisplay(fd, "SMOKE_FAIL timeout after %0d cycles (no store to the signature address)", cycles);
      $fdisplay(fd, "  last fetch: araddr=0x%08x arvalid=%b arready=%b rvalid=%b",
                bfm0_araddr, bfm0_arvalid, bfm0_arready, bfm0_rvalid);
      $fclose(fd); $finish;
    end
  end
endmodule
