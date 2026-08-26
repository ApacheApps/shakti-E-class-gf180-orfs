#!/usr/bin/env bash
# ip/cores/eclass/sim/run_reset_sync.sh -- G3a.
# Runs the reset-synchronizer unit TB in the base sim image. Deliberately does NOT depend on the
# riscof container: this gate must be runnable on its own, in seconds.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROOT="$(cd "$HERE/../../../.." && pwd)"
mkdir -p "$HERE/RESULTS"

IMAGE="${SMOKE_IMAGE:-orfs-sim-arm64:local}"

docker run --rm --cpus=4 -v "$PROOT:/work" -w /work/ip/cores/eclass/sim \
  "$IMAGE" bash -lc '
    set -euo pipefail
    # -j 1 deliberately: with -j > 1 this Verilator build aborts on exit with
    #   "Internal Error: attempted to destroy locked Thread Pool"
    # AFTER successfully linking the binary. That is a teardown bug in verilator_bin, not a problem
    # with the design, but under `set -e` it would kill the script before the test ever ran. This TB
    # is a few hundred lines, so serial elaboration costs nothing.
    verilator --binary --timing -Wno-fatal -j 1 \
      --top-module tb_reset_sync \
      -I. tb_reset_sync.sv ../rtl/eclass_reset_sync.sv \
      -o Vtb_reset_sync --Mdir obj_reset_sync || true
    # Build and run are separated so a teardown crash cannot masquerade as a test result, and a
    # MISSING binary is reported as such rather than as a silent pass.
    test -x ./obj_reset_sync/Vtb_reset_sync || { echo "RESET_SYNC_FAIL: build produced no binary"; exit 1; }
    ./obj_reset_sync/Vtb_reset_sync
  ' 2>&1 | tee "$HERE/RESULTS/reset_sync.log"
