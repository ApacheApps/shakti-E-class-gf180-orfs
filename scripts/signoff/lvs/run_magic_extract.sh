#!/usr/bin/env bash
# LVS step 1 — extract the layout netlist with MAGIC.
#
# gf180mcu ships collateral for TWO self-consistent LVS flows:
#   A) KLayout extract + KLayout compare   (libs.tech/klayout/lvs/)
#   B) magic  extract + netgen  compare    (libs.tech/magic/*.tech + libs.tech/netgen/*_setup.tcl)
# THIS IS FLOW B, and it is the one that works for a standard-cell digital design. See docs/LVS_FLOW.md.
#
# REQUIRES magic >= 8.3.411 (the gf180 techfile refuses older). Ubuntu noble ships 8.3.105, which
# loads the techfile with 14 errors and SEGFAULTS. Build from source:
#   git clone --depth 1 https://github.com/RTimothyEdwards/magic.git
#   cd magic && ./configure --prefix=$HOME/.local --without-opengl --without-cairo && make -j8 && make install
set -u
GDS="${1:?usage: run_magic_extract.sh <layout.gds> <topcell> <outdir>}"
TOP="${2:?}"; OUT="${3:?}"
: "${PDK_ROOT:?set PDK_ROOT to the directory CONTAINING gf180mcuC}"
MAGIC="${MAGIC_CMD:-magic}"
PDK="$PDK_ROOT/gf180mcuC"
mkdir -p "$OUT"

cat > "$OUT/extract.tcl" <<TCL
# Guard: a missing/incompatible techfile makes magic fall back to its DEFAULT "minimum" technology,
# report "Nothing in cifinput section of tech file", be unable to read GDS at all -- and still exit 0.
if {[tech name] != "gf180mcuC"} {
    puts stderr "FATAL: technology is '[tech name]', expected gf180mcuC -- refusing to extract"
    quit -noprompt
}
puts stdout "TECH OK: [tech name]"
drc off
crashbackups stop
gds readonly true
gds rescale false
gds read $GDS
load $TOP
select top cell
extract no all
extract do local
extract all
ext2spice lvs
ext2spice -o $OUT/layout.spice
TCL

"$MAGIC" -dnull -noconsole -rcfile "$PDK/libs.tech/magic/gf180mcuC.magicrc" "$OUT/extract.tcl" \
  > "$OUT/magic_extract.log" 2>&1
rc=$?
[ -f "$OUT/layout.spice" ] || { echo "FAIL: no layout.spice (rc=$rc)"; exit 1; }
# Assign first; never chain `|| echo` onto grep -c -- grep -c prints 0 AND exits 1, which yields a
# two-line value, breaks the integer test, and can announce success on a segfaulted run.
dev=$(grep -cE '^[[:space:]]*[MDQX]' "$OUT/layout.spice"); dev=${dev:-0}
echo "layout.spice: $(wc -c < "$OUT/layout.spice") bytes, $dev device/subckt lines"
if [ "$dev" -lt 1000 ] 2>/dev/null; then
  echo "FAIL: only $dev devices extracted"; grep -iE 'error|fatal|Nothing in' "$OUT/magic_extract.log" | head -5; exit 1
fi
echo "MAGIC EXTRACTION OK"
