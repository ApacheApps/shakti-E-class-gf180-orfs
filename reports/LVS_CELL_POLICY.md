# LVS cell inclusion/exclusion policy — eclass_gf180 (M3.5, `eclass_top`)

**Date:** 2026-08-26 · **Layout:** `signoff_rstsync/eclass_gf180_rstsync_25mhz.gds` · **Top:** `eclass_top`

Every decision below is derived from **measured cell contents**, not from convention. The governing
principle: *a cell is excluded from LVS only when excluding it cannot hide a real electrical
difference.* Excluding a cell to make a mismatch disappear is not a waiver, it is concealment.

## The census

91 logic cell types appear in both the Verilog netlist and the layout. **Ten cell types are
physical-only** — present in the layout, absent from the netlist, because the floorplanner and
router insert them after synthesis:

| cell | instances | devices in PDK SPICE | decision |
|---|---|---|---|
| `__antenna` | **27** | **YES — 2 diodes each** (`D0 diode_nd2ps_06v0`, `D1 diode_pd2nw_06v0`) | **INCLUDE in schematic** |
| `__filltie` | 11,492 | none (empty `.SUBCKT`) | flatten in layout |
| `__endcap` | 672 | none (empty `.SUBCKT`) | flatten in layout |
| `__fill_1/2/4/8/16/32/64` | 66,232 | none (empty `.SUBCKT`) | flatten in layout |
| | **78,423 total** | | |

## The two decisions that matter, and why

### 1. `__antenna` must be INCLUDED — excluding it would hide 54 real diodes

Measured, not assumed:
- Its PDK `.SUBCKT` contains **two real diodes**, so the extractor WILL produce devices from it.
- The DEF carries **54 `ANTENNA_*` references = 27 placements + 27 net connections**, i.e. every
  instance's `I` pin is tied to a **real signal net**, not left floating.
- Confirmed independently by parsing the DEF `NETS` section directly: **27 diode cells on 26
  distinct SIGNAL nets, 0 on power nets** (`net7190` carries two; also `net7202`, `net7203`,
  `net7204`, `net7207`, …). Derived a second way, from a second source, on purpose — the whole
  policy turns on this fact.

So these are real devices on real nets. A schematic without them means LVS compares a layout
containing 54 diodes against a schematic containing none. Dropping the cell from the comparison to
clear that mismatch would suppress a genuine discrepancy — the exact failure mode this policy exists
to prevent. They are therefore **added to the schematic**, with connectivity taken from the ODB
(`emit_phys_cells.tcl`) and pin ORDER taken from the PDK `.SUBCKT` (`add_phys_cells.py`), because
SPICE subcircuit calls are positional and LEF MTerm order is not guaranteed to match.

### 2. `__filltie` must be FLATTENED, never deleted — it carries the bulk connections

`filltie` is device-free, which makes it look droppable. It is not. It is the **well/substrate tap**:
it ties `VDD`→nwell and `VSS`→substrate. Black-boxing or deleting it would strip the body connection
from every transistor in the design and produce thousands of **false** mismatches on bulk terminals —
which someone would then be tempted to waive, hiding whatever real errors sat underneath.

Flattening dissolves the subcircuit while preserving its connectivity: its nets merge into the
parent's `VDD`/`VSS`, which the schematic also has. Same treatment for `__endcap` and `__fill_*`,
which are likewise device-free and connect only to power.

## Why the earlier attempts failed, and why this is not the same attempt

The prior campaign concluded **"LVS is blocked at the TOOLING level"** after three attempts, all
using **KLayout LVS**, always returning `Mismatch 10, NoMatch 91` on exactly these ten cells.

That diagnosis was correct *for KLayout* and correctly root-caused: KLayout builds a circuit for
every cell it finds in the layout, devices or not, and its **SPICE reader cannot create a circuit for
a device-free subcircuit**, so fill/tap/endcap can never match. Attempt 3 added all 80,080 physical
cells to the schematic and produced a byte-identical result, which is the proof.

**But "KLayout LVS is blocked" is not "LVS is blocked."** gf180mcu also ships:
- `libs.tech/netgen/gf180mcuC_setup.tcl` — a netgen LVS setup (the sky130-style flow), and
- `libs.tech/magic/gf180mcuC.tech` — magic tech for extraction.

netgen is a netlist comparator and reads empty `.SUBCKT`/`.ENDS` pairs without complaint, so the
specific limitation that blocked KLayout does not apply to it. netgen also provides `flatten class`,
the lever the gf180 KLayout deck lacks entirely.

**Claim discipline:** until a netgen run actually completes, the honest statement remains *"LVS is
unproven; KLayout LVS is blocked by a documented tool limitation, and a netgen path exists but has
not yet returned a result."* Neither "LVS clean" nor "LVS impossible" is supportable today.

## Status

- Schematic netlist built: `eclass_rstsync.spice` — **28,825 logic instances, 57 top ports**.
- Physical cells: pending (`emit_phys_cells.tcl` needs the ODB; deferred while a PV job holds the Mac).
- netgen 1.5.133 and magic 8.3.105 installed on the physical-verification host.
