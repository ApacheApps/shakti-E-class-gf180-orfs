#!/usr/bin/env bash
# Copy the four BSV primitives the generated netlist instantiates, from the GENERIC
# ${BLUESPECDIR}/Verilog/ set — never Verilog.Vivado/ (that RegFile.v is annotated
# (* RAM_STYLE = "DISTRIBUTED" *), i.e. Xilinx distributed RAM).
#
# Alternative recorded for M2, NOT used here: bsv/common_verilog/RegFile.v is a larger
# IIT-Madras 2025 reimplementation (MIT per-file header). It is a candidate area/timing lever,
# measured in the M2 sweep — adopting it is a decision, not a default.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC=/opt/homebrew/Cellar/bsc/2026.01/libexec/lib/Verilog
mkdir -p "$HERE/gen/prims"
for f in FIFO1 FIFO2 FIFOL1 RegFile; do
  cp "$SRC/$f.v" "$HERE/gen/prims/$f.v"
done
ls "$HERE/gen/prims"
