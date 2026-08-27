#!/usr/bin/env bash
# LVS step 2 — compare magic's extraction against the schematic with NETGEN.
#
# Use the DOCUMENTED invocation form below. Sourcing gf180mcuC_setup.tcl bare from a script aborts
# with a Tcl error ("invoked from within \"eval \$argv\"") after reading the netlists, leaving no
# report and no error line -- it looks like a hang, not a failure.
#
# Do NOT feed netgen a KLayout extraction. netgen's gf180 setup tunes property/permute/tolerance for
# MAGIC's output conventions; the mismatched pair does not converge (measured: 60+ min, 307,139 vs
# 317,364 devices). See docs/LVS_FLOW.md.
set -u
LAYOUT="${1:?usage: run_netgen.sh <layout.spice> <schematic.spice> <topcell> <outdir>}"
SCHEM="${2:?}"; TOP="${3:?}"; OUT="${4:?}"
: "${PDK_ROOT:?set PDK_ROOT to the directory CONTAINING gf180mcuC}"
PDK="$PDK_ROOT/gf180mcuC"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"

cat > "$OUT/setup.tcl" <<TCL
source $PDK/libs.tech/netgen/gf180mcuC_setup.tcl
source $HERE/netgen_setup.tcl
TCL

netgen-lvs -batch lvs "$LAYOUT $TOP" "$SCHEM $TOP" "$OUT/setup.tcl" "$OUT/lvs.report" \
  > "$OUT/netgen.log" 2>&1
echo "netgen rc=$?"
[ -s "$OUT/lvs.report" ] || { echo "FAIL: no report"; tail -12 "$OUT/netgen.log"; exit 1; }
echo "--- verdict ---"
grep -iE "Circuits match|do not match|Netlists match" "$OUT/lvs.report" | tail -4
echo "--- non-vacuity: counts must be NON-ZERO and EQUAL ---"
grep -E "Number of (devices|nets)" "$OUT/lvs.report" | tail -2
echo "--- unmatched (must be 0) ---"
echo "  nets:    $(grep -c 'no matching net' "$OUT/lvs.report")"
echo "  devices: $(grep -c 'no matching device' "$OUT/lvs.report")"
