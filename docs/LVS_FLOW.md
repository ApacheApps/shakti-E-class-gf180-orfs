# gf180mcu LVS: the working recipe (magic extract → netgen compare)

> **Confidence:** Verified end-to-end (2026-08-26) · **Source:** eclass_gf180 M3.5 — E-class RV32IMAC,
> 28,825 logic instances + 78,423 physical-only, on gf180mcu 9-track 5LM_1TM.
> **Result: `Circuits match uniquely`** — 28,838 = 28,838 devices, 30,322 = 30,322 nets,
> 0 unmatched nets, 0 unmatched devices, ~2 minutes.
> See the tool-agnostic principles in [`lvs-extractor-comparator-pairing.md`](lvs-extractor-comparator-pairing.md).

## What gf180 ships (and the trap)

gf180mcu ships collateral for **two** LVS flows:

| flow | extract | compare | location |
|---|---|---|---|
| A | KLayout | KLayout | `libs.tech/klayout/lvs/` (`gf180mcu.lvs`, `run_lvs.py`) |
| **B (use this)** | **magic** | **netgen** | `libs.tech/magic/gf180mcuC.tech` + `libs.tech/netgen/gf180mcuC_setup.tcl` |

**Flow A is blocked for a standard-cell digital design in hierarchical mode.** KLayout builds a
circuit for every cell it finds in the layout, and its **SPICE reader cannot create a circuit for a
device-free subcircuit**. gf180's `fill_*`, `filltie` and `endcap` have empty `.SUBCKT` bodies in the
PDK SPICE, so they can never match: the run returns `Mismatch 10, NoMatch 91` on exactly
`ANTENNA ENDCAP FILLTIE FILL_1/2/4/8/16/32/64`, and the gf180 KLayout deck ships **no
flatten/ignore/blank_circuit lever** to work around it. Adding all 80,080 physical cells to the
schematic produces a byte-identical failure — the SPICE reader still cannot represent them.
(`--run_mode=flat` does avoid this, since flat extraction has no per-cell circuits — but then you are
holding a flat netlist that netgen's gf180 setup was not written for. See the pairing playbook.)

## PREREQUISITE: magic ≥ 8.3.411 — distro packages are too old

The gf180 techfile refuses older magic:

    Error: Magic version 8.3.411 is required by this techfile, but this version of magic is 8.3.105.

Ubuntu noble ships **8.3.105** (Dec 2021). It loads the techfile with 14 errors and then
**SEGFAULTS (rc=139)** — after writing a plausible-looking 105-byte netlist and, in one case,
exiting 0. Build from source instead (≈3 min):

```bash
git clone --depth 1 https://github.com/RTimothyEdwards/magic.git
cd magic && ./configure --prefix=$HOME/.local --without-opengl --without-cairo && make -j8 && make install
```

**Silent-failure guard:** a missing/incompatible techfile makes magic fall back to its default
`minimum` technology, report *"Nothing in cifinput section of tech file"*, be unable to read GDS at
all — and still exit 0. Always assert the tech loaded and the output is non-trivial:

```tcl
if {[tech name] != "gf180mcuC"} { puts stderr "FATAL: tech is '[tech name]'"; quit -noprompt }
```

## Scripts in this repository

| script | step |
|---|---|
| `scripts/signoff/lvs/run_magic_extract.sh` | 1 — magic extraction |
| `scripts/signoff/lvs/netgen_setup.tcl` | 2a — cell policy + the 5V/6V equate |
| `scripts/signoff/lvs/run_netgen.sh` | 2 — netgen comparison, with non-vacuity output |

⚠️ `scripts/signoff/run_lvs.sh` is the **KLayout** path and does **not** work for this design; it is
kept only as documented evidence and is banner-marked as such.

Pre-extracted netlists are in `collateral/lvs/`, so the comparison can be re-run in seconds:
```bash
gunzip -k collateral/lvs/*.gz
PDK_ROOT=<dir containing gf180mcuC> \
  scripts/signoff/lvs/run_netgen.sh collateral/lvs/layout_magic_extracted.spice \
                                    collateral/lvs/schematic.spice eclass_top /tmp/lvs
```

## Recipe

```bash
export PDK_ROOT=<dir containing gf180mcuC>      # the magicrc reads $env(PDK_ROOT)
```

**1. Extract (magic, hierarchical):**
```tcl
drc off
crashbackups stop
gds readonly true
gds rescale false
gds read <design>.gds
load <topcell>
select top cell
extract no all
extract do local
extract all
ext2spice lvs
ext2spice -o layout.spice
```
Expect a **hierarchical** result — for this design 93 `.subckt` defs / 30,858 `X` calls — with devices
emitted subcircuit-style (`X0 Z net VSS VSUBS nfet_05v0 w=1.32u l=0.6u`). Magic emits **no circuits at
all** for the device-free fill/tap/endcap cells, which is why the cell population already agrees.

**2. Build the schematic netlist:** post-route Verilog → SPICE, **plus the antenna diodes** taken from
the layout database (they are physical-only, so a Verilog-derived netlist has none). Tie the cell
`VNW`→`VDD` and `VPW`→`VSS` in the instance pin order `(… VDD VNW VPW VSS)`.

**3. Compare (netgen), wrapping the PDK setup:**
```tcl
source $PDK/libs.tech/netgen/gf180mcuC_setup.tcl
# device-free physical-only cells, ignored symmetrically and guarded (sky130's pattern)
foreach c {..__filltie ..__endcap ..__fill_1 ..__fill_2 ..__fill_4 ..__fill_8 ..__fill_16 ..__fill_32 ..__fill_64} {
    if {[lsearch $cells1 $c] >= 0} { ignore class "-circuit1 $c" }
    if {[lsearch $cells2 $c] >= 0} { ignore class "-circuit2 $c" }
}
# NOT ignored: __antenna — 2 real diodes per instance, on SIGNAL nets
catch {equate classes "-circuit1 nfet_05v0" "-circuit2 nfet_06v0"}
catch {equate classes "-circuit1 pfet_05v0" "-circuit2 pfet_06v0"}
```
```bash
netgen-lvs -batch lvs "layout.spice <top>" "schematic.spice <top>" setup.tcl lvs.report
```

**⚠️ The 5V/6V equate is mandatory.** The `mcu9t5v0` (5 V) standard cells are built from **6V-rated**
devices: the PDK cell SPICE says `nfet_06v0`/`pfet_06v0` while magic classifies the same geometry as
`nfet_05v0`/`pfet_05v0`. `gf180mcuC_setup.tcl` configures both as **separate** device classes and
never equates them, so without this every transistor mismatches on class alone.

**⚠️ Invocation form.** Use the documented `netgen -batch lvs "<net1> <cell1>" "<net2> <cell2>"
<setup> <out>`. Sourcing `gf180mcuC_setup.tcl` bare from a script aborts with a Tcl error
(`invoked from within "eval $argv"`) after reading the netlists, leaving no report and no error line.

## Physical-only cell census (this design, for reference)

| cell | instances | devices | treatment |
|---|---|---|---|
| `__antenna` | 27 | **2 diodes each** — all on SIGNAL nets | **INCLUDE in schematic** |
| `__filltie` (tap) | 11,492 | none | ignore (magic emits no circuit) |
| `__endcap` | 672 | none | ignore |
| `__fill_1/2/4/8/16/32/64` | 66,232 | none | ignore |

## Run it on the UNFILLED database

The gf180 LVS deck defines `metal1 = metal1_drawn + metal1_dummy` and derives connectivity from it,
so metal fill extracts as phantom floating nets. LVS the block before fill; fill is a
chip-integration step verified by *density*, not by LVS.

## Benign residue on a clean run

- `Cell pin lists ... altered to match` — GDS labels are bit-blasted (`bus[0]`, `bus[1]`, …) while the
  Verilog uses vectors. Does not prevent a unique match.
- `VSUBS | VPW **Mismatch**`, `w_<n>_<n># | VNW **Mismatch**` — well/substrate **net-name**
  differences (magic's substrate name and generated well nodes vs the cell pin names). Electrically
  the same node; report them rather than hide them.
