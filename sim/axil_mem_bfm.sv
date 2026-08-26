// ip/cores/eclass/sim/axil_mem_bfm.sv
// Single-cycle AXI4-Lite slave with backing memory. Instantiated once per E-class master port.
// SHAKTI's AXI4-Lite is a DIALECT — it carries non-spec awsize/arsize[1:0] (confirmed present in
// the generated top). The DUT drives them; this BFM ignores them: every access here is a full
// 32-bit word.
`timescale 1ns/1ps
module axil_mem_bfm #(
  parameter int    WORDS      = 1<<16,
  parameter bit    READ_ONLY  = 0,
  parameter string MEMFILE    = "",      // one 32-bit hex word per line (see bin2hex.py)
  parameter int    LOAD_WORD  = 0,       // word index the file's first word lands on
  parameter [31:0] MEM_BASE   = 32'h0,    // bus address that maps to word index 0
  parameter bit    CAN_DUMP   = 0         // only the data-side BFM writes the signature
) (
  input  logic        clk, rst_n,
  input  logic [31:0] awaddr,  input  logic awvalid, output logic awready,
  input  logic [31:0] wdata,   input  logic [3:0] wstrb, input logic wvalid, output logic wready,
  output logic [1:0]  bresp,   output logic bvalid,  input  logic bready,
  input  logic [31:0] araddr,  input  logic arvalid, output logic arready,
  output logic [31:0] rdata,   output logic [1:0] rresp, output logic rvalid, input logic rready,
  output logic        wr_seen, output logic [31:0] wr_addr, output logic [31:0] wr_data,
  // signature dump (RISCOF): pulse dump_req after halt; addresses come from the ELF symbol table
  input  logic        dump_req,
  input  logic [31:0] sig_begin, input logic [31:0] sig_end
);
  logic [31:0] mem [0:WORDS-1];

  // Load inside the BFM rather than via a hierarchical reference from the TB: Verilator can
  // optimize away cross-module refs, and a silently-empty instruction memory looks exactly like
  // a core that will not fetch.
  initial begin
    automatic string pa_memfile;
    for (int i = 0; i < WORDS; i++) mem[i] = 32'h0;
    if (MEMFILE != "") begin
      $readmemh(MEMFILE, mem, LOAD_WORD);
    end else if ($value$plusargs("memfile=%s", pa_memfile)) begin
      // Loading via plusarg INSIDE the module, never by a hierarchical $readmemh from the TB:
      // cross-module refs can be optimized away by the simulator, and an empty instruction
      // memory is indistinguishable from a core that will not fetch.
      // (NB: a comment whose first word is the simulator's name is parsed as a pragma.)
      $readmemh(pa_memfile, mem, LOAD_WORD);
    end
  end

  logic [31:0] held_awaddr, held_wdata;
  logic [3:0]  held_wstrb;
  logic        have_aw, have_w;

  assign awready = !have_aw && !bvalid && !READ_ONLY;
  assign wready  = !have_w  && !bvalid && !READ_ONLY;
  assign arready = !rvalid;
  assign bresp   = 2'b00;
  assign rresp   = 2'b00;

  // Bus address -> word index. Out-of-range accesses are NOT stored but ARE reported via wr_seen,
  // which is how the TB observes the RVMODEL_HALT store to an MMIO address outside memory.
  wire [31:0] widx = (held_awaddr - MEM_BASE) >> 2;
  wire [31:0] ridx = (araddr      - MEM_BASE) >> 2;
  wire        w_in_range = (held_awaddr >= MEM_BASE) && (widx < WORDS);
  wire        r_in_range = (araddr      >= MEM_BASE) && (ridx < WORDS);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      have_aw <= 0; have_w <= 0; bvalid <= 0; rvalid <= 0; wr_seen <= 0;
      wr_addr <= 0; wr_data <= 0; rdata <= 0;
    end else begin
      wr_seen <= 0;

      // read channel
      if (arvalid && arready) begin
        rdata  <= r_in_range ? mem[ridx] : 32'hDEAD_BEEF;
        rvalid <= 1;
      end else if (rvalid && rready) begin
        rvalid <= 0;
      end

      // write channel: latch aw and w independently, commit when both are in
      if (awvalid && awready) begin held_awaddr <= awaddr; have_aw <= 1; end
      if (wvalid  && wready)  begin held_wdata  <= wdata; held_wstrb <= wstrb; have_w <= 1; end

      if (have_aw && have_w && !bvalid) begin
        if (w_in_range) begin
          for (int b = 0; b < 4; b++)
            if (held_wstrb[b]) mem[widx][8*b +: 8] <= held_wdata[8*b +: 8];
        end
        wr_seen <= 1; wr_addr <= held_awaddr; wr_data <= held_wdata;
        have_aw <= 0; have_w <= 0; bvalid <= 1;
      end else if (bvalid && bready) begin
        bvalid <= 0;
      end
    end
  end

  // Signature dump lives INSIDE the BFM on purpose: Verilator can optimize away cross-module
  // hierarchical references, and a silently-empty signature file would read as a DUT mismatch
  // rather than as a broken testbench.
  logic dumped = 0;
  always @(posedge clk) begin
    if (CAN_DUMP && dump_req && !dumped) begin
      automatic string sigout;
      automatic int    sfd;
      automatic logic [31:0] a, idx;
      dumped <= 1;
      if (!$value$plusargs("sigout=%s", sigout)) sigout = "DUT-eclass.signature";
      sfd = $fopen(sigout, "w");
      if (sfd == 0) begin
        $display("BFM: FATAL could not open signature file %s", sigout);
        $finish;
      end
      for (a = sig_begin; a < sig_end; a = a + 4) begin
        idx = (a - MEM_BASE) >> 2;
        $fdisplay(sfd, "%08x", (a >= MEM_BASE && idx < WORDS) ? mem[idx] : 32'hdeadbeef);
      end
      $fclose(sfd);
      $display("BFM: signature written to %s (0x%08x..0x%08x)", sigout, sig_begin, sig_end);
    end
  end
endmodule
