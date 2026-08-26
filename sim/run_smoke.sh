#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROOT="$(cd "$HERE/../../../.." && pwd)"
mkdir -p "$HERE/RESULTS"

# The smoke test needs only riscv32-unknown-elf-gcc + verilator, both already in the BASE sim image.
# It deliberately does NOT depend on eclass-riscof-arm64 (spike/riscof are a Task 8 concern), so
# this gate can run before, and independently of, the compliance container.
IMAGE="${SMOKE_IMAGE:-orfs-sim-arm64:local}"

# Which module to instantiate, and where to log. Defaults keep the historical core-direct behaviour
# byte-for-byte so the baseline log is not silently overwritten by a wrapper run.
DUT_TOP="${DUT_TOP:-mkeclass_axi4lite}"
if [ "$DUT_TOP" = "mkeclass_axi4lite" ]; then LOGNAME=smoke; else LOGNAME=smoke_wrapper; fi

# Binding is generated on the HOST, not in the container: the sim image's python3 is older and
# cannot parse gen_binding.py. The container only needs to compile, so keep the moving part out of it.
python3 "$HERE/gen_binding.py" > "$HERE/dut_binding.svh"

docker run --rm --cpus=4 -v "$PROOT:/work" -e DUT_TOP="$DUT_TOP" -e LOGNAME="$LOGNAME" \
  -w /work/ip/cores/eclass/sim \
  "$IMAGE" bash -lc '
    set -euo pipefail
    riscv32-unknown-elf-gcc -march=rv32imac_zicsr -mabi=ilp32 -nostdlib \
      -T bootrom/link.ld -o bootrom/smoke.elf bootrom/smoke.S
    riscv32-unknown-elf-objcopy -O binary bootrom/smoke.elf bootrom/smoke.bin
    python3 bin2hex.py bootrom/smoke.bin > bootrom/smoke.hex
    echo "program words: $(wc -l < bootrom/smoke.hex)"
    EXTRA=""
    if [ "$DUT_TOP" != "mkeclass_axi4lite" ]; then EXTRA="../rtl/eclass_top.sv ../rtl/eclass_reset_sync.sv"; fi
    verilator --binary --timing -Wno-fatal -j 8 \
      -DBSV_ASSIGNMENT_DELAY= \
      --top-module tb_eclass_smoke \
      -I. \
      tb_eclass_smoke.sv axil_mem_bfm.sv $EXTRA \
      $(ls ../gen/vlog/*.v | grep -v mkTb) ../gen/prims/*.v \
      -o Vtb_smoke --Mdir obj_smoke
    ./obj_smoke/Vtb_smoke +log=RESULTS/$LOGNAME.log
  '
echo "--- RESULTS/$LOGNAME.log ---"
cat "$HERE/RESULTS/$LOGNAME.log"
