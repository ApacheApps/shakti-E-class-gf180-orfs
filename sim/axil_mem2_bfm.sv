// ip/cores/eclass/sim/axil_mem2_bfm.sv
// ONE memory array serving BOTH E-class AXI4-Lite masters: port A = instruction fetch (read only),
// port B = data (read/write).
//
// WHY THIS EXISTS: the first harness gave each master its own array, with a comment claiming "arch
// tests are not self-modifying, so separate arrays are safe". That is false for exactly one suite —
// rv32i_m/Zifencei is ABOUT self-modifying code. Stores through the data port must become visible
// to the fetch port, which is impossible with two arrays. Fencei.S failed for that reason and not
// because of the core.
//
// Reads on both ports are serviced in the same cycle from the shared array; a behavioural memory
// needs no arbitration, and adding one would only invent latency the real system does not have.
`timescale 1ns/1ps
module axil_mem2_bfm #(
  parameter int    WORDS    = 1 << 20,
  parameter [31:0] MEM_BASE = 32'h8000_0000
) (
  input  logic        clk, rst_n,
  // ---- port A: instruction fetch (read only) ----
  input  logic [31:0] a_araddr, input logic a_arvalid, output logic a_arready,
  output logic [31:0] a_rdata,  output logic [1:0] a_rresp,
  output logic        a_rvalid, input logic a_rready,
  input  logic [31:0] a_awaddr, input logic a_awvalid, output logic a_awready,
  input  logic [31:0] a_wdata,  input logic [3:0] a_wstrb, input logic a_wvalid,
  output logic        a_wready, output logic [1:0] a_bresp, output logic a_bvalid,
  input  logic        a_bready,
  // ---- port B: data (read/write) ----
  input  logic [31:0] b_araddr, input logic b_arvalid, output logic b_arready,
  output logic [31:0] b_rdata,  output logic [1:0] b_rresp,
  output logic        b_rvalid, input logic b_rready,
  input  logic [31:0] b_awaddr, input logic b_awvalid, output logic b_awready,
  input  logic [31:0] b_wdata,  input logic [3:0] b_wstrb, input logic b_wvalid,
  output logic        b_wready, output logic [1:0] b_bresp, output logic b_bvalid,
  input  logic        b_bready,
  // ---- observation + signature ----
  output logic        wr_seen, output logic [31:0] wr_addr, output logic [31:0] wr_data,
  input  logic        dump_req,
  input  logic [31:0] sig_begin, input logic [31:0] sig_end
);
  logic [31:0] mem [0:WORDS-1];

  initial begin
    automatic string pa_memfile;
    for (int i = 0; i < WORDS; i++) mem[i] = 32'h0;
    if ($value$plusargs("memfile=%s", pa_memfile)) $readmemh(pa_memfile, mem, 0);
  end

  function automatic logic in_range(input logic [31:0] a);
    in_range = (a >= MEM_BASE) && (((a - MEM_BASE) >> 2) < WORDS);
  endfunction

  // port A is read-only: never accept a write
  assign a_awready = 1'b0;
  assign a_wready  = 1'b0;
  assign a_bvalid  = 1'b0;
  assign a_bresp   = 2'b00;
  assign a_arready = !a_rvalid;
  assign a_rresp   = 2'b00;
  assign b_arready = !b_rvalid;
  assign b_rresp   = 2'b00;
  assign b_bresp   = 2'b00;

  logic [31:0] held_awaddr, held_wdata;
  logic [3:0]  held_wstrb;
  logic        have_aw, have_w;
  assign b_awready = !have_aw && !b_bvalid;
  assign b_wready  = !have_w  && !b_bvalid;

  wire [31:0] widx = (held_awaddr - MEM_BASE) >> 2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_rvalid <= 0; b_rvalid <= 0; b_bvalid <= 0;
      have_aw <= 0; have_w <= 0; wr_seen <= 0;
      a_rdata <= 0; b_rdata <= 0; wr_addr <= 0; wr_data <= 0;
    end else begin
      wr_seen <= 0;

      if (a_arvalid && a_arready) begin
        a_rdata  <= in_range(a_araddr) ? mem[(a_araddr - MEM_BASE) >> 2] : 32'hDEAD_BEEF;
        a_rvalid <= 1;
      end else if (a_rvalid && a_rready) a_rvalid <= 0;

      if (b_arvalid && b_arready) begin
        b_rdata  <= in_range(b_araddr) ? mem[(b_araddr - MEM_BASE) >> 2] : 32'hDEAD_BEEF;
        b_rvalid <= 1;
      end else if (b_rvalid && b_rready) b_rvalid <= 0;

      if (b_awvalid && b_awready) begin held_awaddr <= b_awaddr; have_aw <= 1; end
      if (b_wvalid  && b_wready)  begin held_wdata  <= b_wdata; held_wstrb <= b_wstrb; have_w <= 1; end

      if (have_aw && have_w && !b_bvalid) begin
        if (in_range(held_awaddr)) begin
          for (int i = 0; i < 4; i++)
            if (held_wstrb[i]) mem[widx][8*i +: 8] <= held_wdata[8*i +: 8];
        end
        wr_seen <= 1; wr_addr <= held_awaddr; wr_data <= held_wdata;
        have_aw <= 0; have_w <= 0; b_bvalid <= 1;
      end else if (b_bvalid && b_bready) b_bvalid <= 0;
    end
  end

  logic dumped = 0;
  always @(posedge clk) begin
    if (dump_req && !dumped) begin
      automatic string sigout;
      automatic int sfd;
      automatic logic [31:0] a;
      dumped <= 1;
      if (!$value$plusargs("sigout=%s", sigout)) sigout = "DUT-eclass.signature";
      sfd = $fopen(sigout, "w");
      if (sfd == 0) begin $display("BFM: FATAL cannot open %s", sigout); $finish; end
      for (a = sig_begin; a < sig_end; a = a + 4)
        $fdisplay(sfd, "%08x", in_range(a) ? mem[(a - MEM_BASE) >> 2] : 32'hdeadbeef);
      $fclose(sfd);
      $display("BFM: signature written to %s (0x%08x..0x%08x)", sigout, sig_begin, sig_end);
    end
  end
endmodule
