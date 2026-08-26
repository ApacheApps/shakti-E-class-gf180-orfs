#!/usr/bin/env bash
# designs/eclass_gf180/scripts/run_drc.sh — real gf180mcu KLayout signoff DRC.
#
# The ORFS image ships only KLayout LAYER-PROPERTY files for gf180 (.lyp/.lyt), no rule decks, and
# the upstream rules repo (efabless/globalfoundries-pdk-libs-gf180mcu_fd_pr) no longer carries a
# runnable deck -- its rules/klayout/drc/ directory is gone and main.drc there is a license stub.
# The decks DO exist in the open_pdks build fetched by volare, which is what this script uses.
#
# variant=C is chosen because it is the ONLY variant matching this design's stack:
#   C = metal_top 9K / mim_option B / metal_level 5LM, and the design is 5LM_1TM with KVALUE=9K.
# Getting this wrong would run the wrong metal rules and produce a meaningless clean or dirty.
set -euo pipefail
PROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PDK="${GF180_PDK:-$HOME/.volare/volare/gf180mcu/versions/c6d73a35f524070e85faff4a6a9eef49553ebc2b}"
# The hardened top changed at M3.5: eclass_top wraps the core with the reset synchronizer. Getting
# this wrong checks the wrong cell and reports a meaningless clean, exactly like picking the wrong
# deck variant would. The default preserves behaviour for every pre-M3.5 GDS.
TOPCELL="${TOPCELL:-mkeclass_axi4lite}"
# run_mode: FLAT + --split_deep is dramatically faster and, unlike deep, actually COMPLETES.
# run_drc.py:344 makes --split_deep a no-op in deep mode, disabling the deck's own mitigation for
# its long-running rules. Measured: deep = 20 h and never finished (34/40 tables); flat+split_deep
# = 34 min, 53 tables, complete. Default stays "deep" so historical runs reproduce exactly.
RUN_MODE="${RUN_MODE:-deep}"
SPLIT_DEEP=""
[ "$RUN_MODE" = "flat" ] && SPLIT_DEEP="--split_deep"
GDS="${1:-/work/designs/eclass_gf180/signoff/eclass_gf180_signoff_25mhz.gds}"
OUT="${2:-/work/designs/eclass_gf180/pv/drc}"
shift $(( $# > 2 ? 2 : $# )) || true
EXTRA="${*:-}"

[ -d "$PDK" ] || { echo "gf180mcu PDK not found at $PDK — run: volare enable --pdk gf180mcu <sha>"; exit 1; }
if docker ps --format '{{.Names}}' | grep -q '^eclass-drc$'; then
  echo "an eclass DRC run is already active — refusing to start a second"; exit 1
fi

docker run --rm --cpus=7 --memory=20g --name eclass-drc \
  -v "$PROOT:/work" -v "$PDK:/pdk:ro" -w /work orfs-arm64:local bash -lc "
    set -e
    # docopt + the klayout python bindings are not in the ORFS image; both are pure-wheel installs.
    pip install --quiet docopt klayout
    python3 /pdk/gf180mcuC/libs.tech/klayout/drc/run_drc.py \
      --path=$GDS --variant=C --topcell=$TOPCELL \
      --run_mode=$RUN_MODE $SPLIT_DEEP --mp=6 --run_dir=$OUT $EXTRA
  "
