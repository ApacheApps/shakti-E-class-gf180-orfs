# eclass_gf180 — M3 SIGNOFF DOSSIER

**SHAKTI E-class RV32IMAC core, hardened to gf180mcu, multi-corner signed off.**
Date 2026-08-24 · run 3 · artifacts in `designs/eclass_gf180/signoff/` (SHA256SUMS included).

## Verdict: SIGNOFF CLEAN

| gate | result | criterion |
|---|---|---|
| **Setup** | **+1.577 ns**, TNS 0.000, **0 violators** | worst across c1ss/c2tt/c3ff, post-route SPEF, propagated clocks |
| **Hold** | **+0.277 ns**, TNS 0.000, **0 violators** | same |
| **Route DRC** | **0** | `5_route_drc.rpt` empty |
| **Antenna** | **0 net / 0 pin** | `ANT-0001`/`ANT-0002`, no diode waivers needed |
| **PDN** | **VDD/VSS all shapes connected**, PSM-0069 = **0** | `PSM-0040` |
| **Max slew (DRV)** | **0 vs the 2.80 ns library limit** (worst 2.73) | see "the two slew numbers" below |
| **CTS sanity** | 1 clock domain, 617 buffers, tree level 6, setup skew 0.94 ns | a real tree, not the gf180 "SDC-only clock" pathology |

## The closed operating point

**25.0 MHz (40 ns) closed with +1.577 ns of margin.** Achievable `period_min = 38.42 ns`
→ **fmax 26.03 MHz** in this configuration.

**Conditions — these travel with the number (gate M3-G4):**
worst corner **ss_125C_4v50** of {c1ss, c2tt, c3ff} · rail **5.0 V** ·
cells **gf180mcu_fd_sc_mcu9t5v0** (9-track) · metal **5LM_1TM** · post-route **SPEF** extraction ·
propagated clocks · `DONT_USE_CELLS = *_1` — **⚠️ CORRECTED 2026-08-24: this is NOT enforced for
adder cells.** The signed-off netlist contains 1,041 `addh_1` + 243 `addf_1` = **1,284 drive-1
instances**, which reach the netlist through the platform's `ADDER_MAP_FILE` techmap, bypassing the
`dont_use` list. The timing above is unaffected (these are legal characterized cells and were in
place for every measurement), but the claim of enforcement was wrong. See
`reports/SIGNOFF_CLOSURE.md` §4.

| quantity | value |
|---|---|
| design area | 1,484,582 µm² = **1.485 mm²** at 51% utilization |
| core area (floorplan) | 2,924,918 µm² = 2.925 mm² |
| total power @ SS | **293 mW** (clock 44.6%, combinational 33.3%, sequential 22.1%) |
| **AREA_CEILING_UM2: 1484582** | measured, not invented — set from this run per the spec's "measure first" rule |

## The two slew numbers, stated plainly

The SDC carries `set_max_transition 1.6`, which is **tighter than the library requires**. That
margin exists solely to drive `repair_design` hard enough that the *routed* result lands inside the
library limit. Reporting therefore gives two counts:

- **812** pins sit between 1.6 ns and 2.8 ns → flagged against our optimization target.
- **0** pins exceed **2.80 ns**, the gf180 cells' own `max_transition` attribute → **the signoff
  criterion, and it is clean.** Worst measured 2.73 ns.

This is not moving goalposts: 2.80 ns is the limit that physically binds, and we optimized against
a deliberately tighter one to get there with margin.

## How it got here — three runs, each fixing a measured defect

| run | change | setup | hold | slew > 2.80 | DRC |
|---|---|---|---|---|---|
| 1 | no DRV constraints; one clock uncertainty for setup AND hold | +0.049 | **−0.075** | **1303 flagged, worst 9.12** | 0 |
| 2 | split uncertainty (−setup 0.5 / −hold 0.1); `set_max_transition 2.0` | +0.600 | **+0.228** | **28** (worst 2.91) | 0 |
| 3 | `set_max_transition 1.6` | **+1.577** | **+0.277** | **0** (worst 2.73) | 0 |

**Run 1's hold failure was a constraint bug, not silicon.** A single `set_clock_uncertainty 0.5`
applied to hold as well as setup demands 0.5 ns of hold margin on every path in the design. Setup
uncertainty budgets jitter + margin; hold uncertainty budgets skew estimation error, for which
0.5 ns is wildly pessimistic. The measured shortfall was 0.075 ns against that 0.5 ns demand. Fixed
by budgeting them separately (`-hold 0.1`, still a real margin) — and `constraint.sdc.bak_run1`
preserves the original so the change is auditable.

**Run 1's slew failure was a missing constraint.** The gf180 liberty carries no
`default_max_transition` in its header (the 2.80 limit is a per-pin attribute) and the platform's
`MAX_FANOUT = 20` binds **synthesis only**, so the resizer was free to leave a placement-inserted
`buf_16` driving 193 sinks (`net1489`) — 9.12 ns slew once real parasitics were extracted.
Measured aside: `set_max_fanout` is **not** the effective lever on gf180 (a fanout-97 net drew zero
fanout violations); `set_max_transition` is what actually drives `repair_design`.

The resizer effort scaled with the constraint: 636 buffers / 188 nets (run 1) → 1,895 / 599 (run 2)
→ 2,694 / 939 (run 3). Run 3 also cost routing effort — DRT peaked at 2,817 violations mid-route
before converging to 0.

## Honest scope of this claim

**What this is:** the E-class *core*, hardened and multi-corner signed off, with no memory macros
and no IO pads.

**What it is NOT, and must not be represented as:**
- **No memory.** M4 adds the TCM from gf180 SRAM macros. Those macros' 36 signal pins sit on the
  bottom edge only — the `capacity:0` mode that killed `pqc_sky130`. Nothing here has met it.
- **No IO pads.** ORFS's gf180 platform ships 48 LEF entries, zero io/pad, and no IO liberty at
  all. Chip assembly needs a two-tool split (ORFS hardens a core macro; a librelane/shuttle
  template does the pad ring). **This GDS is a core macro, not a chip.**
- **No debug interface.** DEBUG is disabled because enabling it makes EBREAK non-compliant
  (spec AMENDMENT 2). Restoring JTAG is an M5 item carrying that known defect.
- **Not fully RISC-V compliant.** RV32I base ISA passes 38/38 (plus M, A, Zifencei) against Spike
  under RISCOF, but `ebreak`/`cebreak` fail on a **genuine `mtval = pc+1` spec violation** that is
  root-caused with a verified one-line fix **deliberately not applied** (vendored RTL stays
  unmodified), and PMP fails 55/55 with the root cause open. See
  `ip/cores/eclass/sim/RESULTS/COMPLIANCE.md`.
- **No published prior art was found** for SHAKTI on an open PDK — stated as "none found", never
  "first ever".
- **Never compare 26.03 MHz to Moushik's 75–100 MHz** without stating that SCL 180nm is 1.8 V
  thin-oxide and gf180mcu ships only 5 V thick-oxide MCU cells. That gap is largely device class.
- The gf180 SRAM `min_period` caps any *full-MCU* claim at 84.1 MHz; it does not bind here because
  there are no macros yet.

## Reproduce

```bash
bash ip/cores/eclass/scripts/gen.sh && bash ip/cores/eclass/scripts/collect_prims.sh
bash designs/eclass_gf180/scripts/run_m3.sh floorplan     # cheap gate first
bash designs/eclass_gf180/scripts/run_m3.sh               # full multi-corner flow
docker run --rm -v "$PWD:/work" -w /work orfs-arm64:local bash -lc \
  'source /OpenROAD-flow-scripts/env.sh && openroad -exit /work/designs/eclass_gf180/scripts/mc_signoff.tcl'
python3 designs/eclass_gf180/scripts/check_cts.py
python3 designs/eclass_gf180/scripts/collect_m3.py
```

## What was tried against the fmax ceiling (labelled experiment — NOT part of this signoff)

The worst setup path here ends in `riscv.stage3.csr.csrfile.mhpmcounter_0[62]`, a hardware
performance-monitor counter, through an `addh_1` ripple half-adder. HPM counters are optional in
RISC-V, so removing them is an architectural dial rather than a knob-turn. It was run through the
identical multi-corner signoff and is written up in **`signoff_nocounters/EXPERIMENT.md`**:

**28.57 MHz closed / fmax 29.63 MHz (+13.8%), area −10.5%, all the same gates clean — but total
power went UP 27.3% (+11.3% frequency-normalized), and only part of that is explained.**

That experiment does **not** change this signoff. The configuration of record remains
`config_mc.mk` at 25.0 MHz, and adopting counters-off would be a product decision (it removes a
real debug/profiling feature), not a QoR one.

**⚠️ AMENDED 2026-08-24 — the "40 MHz needs architectural work" conclusion is SUSPENDED, not
withdrawn.** It assumed the configuration space was exhausted. It was not: `DONT_USE_CELLS = *_1`
turns out never to have applied to adder cells, so ~97% of this design's half-adders sit at minimum
drive — **and the worst setup path runs through an `addh_1`.** Forcing adders to drive 2/4 at
synthesis is a cheap, direct, and so far UNATTEMPTED lever. Under the project's lever-coverage
mandate no ceiling claim may rest on an untried lever, so the honest statement is: counters-off
closed about a third of the gap, and at least one configuration lever remains untested before any
architectural verdict is earned.
