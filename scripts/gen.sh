#!/usr/bin/env bash
# Generate E-class Verilog by calling bsc DIRECTLY.
#
# WHY NOT upstream `make generate_verilog` (spec AMENDMENT 1):
#  1. It copies RegFile.v / BRAM2*.v from ${BLUESPECDIR}/Verilog.Vivado/ — the Xilinx-flavoured set.
#     Verilog.Vivado/RegFile.v carries `(* RAM_STYLE = "DISTRIBUTED" *)`. Silently contaminated.
#  2. The ASIC path (synth32.inc) has not run in upstream CI since 2019.
#  3. Direct invocation is byte-reproducible and has no hidden state.
# Primitives are collected separately by scripts/collect_prims.sh from ${BLUESPECDIR}/Verilog/.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export BLUESPECDIR=/opt/homebrew/Cellar/bsc/2026.01/libexec/lib
B="$HERE/bsv"

rm -rf "$HERE/gen/vlog" "$HERE/gen/bdir"
mkdir -p "$HERE/gen/vlog" "$HERE/gen/bdir"

INC=".:%/Prelude:%/Libraries:%/Libraries/BlueNoC"
INC="$INC:$B/e-class/src/core:$B/e-class/src/core/m_ext"
INC="$INC:$B/fabrics/axi4:$B/fabrics/axi4lite"
INC="$INC:$B/common_bsv:$B/devices/riscvDebug013"

cd "$B/e-class/base-sim"
bsc -u -verilog -elab \
  -vdir "$HERE/gen/vlog" -bdir "$HERE/gen/bdir" -info-dir "$HERE/gen/bdir" \
  -D RV32=True -D asic=True -D muldiv=True -D atomic=True -D compressed=True \
  -D usertraps=True -D user=True -D pmp=True -D VERBOSITY=0 -D CORE_AXI4Lite=True \
  -D MULSTAGES=4 -D DIVSTAGES=32 -D Counters=4 -D perfmonitors=True -D counters=4 \
  -D paddr=32 -D vaddr=32 -D PMPSIZE=4 -D resetpc=4096 -D causesize=6 -D DTVEC_BASE=0 \
  -D triggers=True -D trigger_num=2 -D mcontext=0 -D scontext=0 \
  +RTS -K4000M -RTS -check-assert -keep-fires -opt-undetermined-vals \
  -remove-false-rules -remove-empty-rules -remove-starved-rules -remove-dollar \
  -p "$INC" -g mkeclass_axi4lite "$B/e-class/src/core/eclass.bsv"

# bsc stamps a wall-clock line into every generated file's header:
#   // On Sun Aug 23 12:17:28 IST 2026
# That single line is the ONLY thing that differs between two runs of an otherwise identical
# generation (verified by diffing consecutive runs: all 17 files, that line only). Normalizing it
# is what makes the byte-identical gate meaningful rather than always-red -- the gate still catches
# what it exists to catch (a moved dependency, or a different bsc build), because every other byte
# of the output remains under comparison. Line count is preserved so diffs stay aligned.
sed -i '' -E 's|^// On .*$|// On <normalized by gen.sh: bsc emits a wall-clock stamp here>|' \
  "$HERE/gen/vlog"/*.v

# bdir holds intermediate .bo/.ba only; it is not part of the reproducibility surface.
echo "generated: $(ls "$HERE/gen/vlog"/*.v | wc -l | tr -d ' ') files"
