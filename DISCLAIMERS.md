# eclass_gf180 — MANDATORY release disclaimers, known limitations and open issues

**Status:** REQUIRED CONTENT for any public release (GitHub or otherwise) of this design.
**Mandated by:** user, 2026-08-26. **Do not publish without a Disclaimers section and a Known
Limitations section carrying everything below.** Nothing here may be softened, summarised away, or
moved to a footnote. If a limitation is fixed later, replace it with the measurement that fixed it —
do not simply delete it.

---

## 1. What this design IS

An E-class (SHAKTI) RV32IMAC core hardened on **gf180mcu**, 9-track, 5LM_1TM, closed at **25.0 MHz**
with a 3-corner (ss/tt/ff) SPEF-annotated static timing signoff, an async-assert/sync-deassert reset
synchronizer, and a full-deck GlobalFoundries KLayout DRC pass.

It is an **open-EDA demonstrator**. It has **not been fabricated**, and no silicon has validated any
claim in this repository.

## 2. Disclaimers — read before trusting any number here

### 2.1 The open KLayout deck is NOT the foundry sign-off deck
Two measured proofs from this project, both of which produced a *clean* result that was wrong:

- **Router-internal DRC missed 154,574 real violations.** ORFS's own route-DRC reported **0** while
  the GlobalFoundries KLayout deck found **154,574** on the same GDS — caused by two *stock ORFS
  gf180 platform defaults*, not by this design's configuration. ⇒ **`RESULT.json "drc": 0` is
  ROUTER-INTERNAL DRC and is never signoff DRC.**
- **The KLayout deck implements NO `DM.*` dummy-metal rules.** A metal-fill configuration that
  violates **DM.1** (min dummy shape 2.0 µm), **DM.2a** (1.2 µm dummy-to-dummy) and **DM.3** (2.0 µm
  dummy-to-circuit-metal) by up to 4× passed **52 DRC tables with 0 violations** before being caught
  by reading the GF180 Design Rule Manual §13.3. ⇒ **A layout can clear the entire open deck and
  still be un-tapeoutable.** The deck is necessary, not sufficient.

### 2.2 The deck's density rule is a simplification of the real rule
The deck computes `metal_layer.area / CHIP.area` — a **single global average over the whole die**.
The real GF180 rule is **windowed: ≥30% measured in 200 µm × 200 µm areas at a 100 µm step**. A
global average can pass while individual windows fail. **No density claim derived from this deck
should be read as compliance with the real rule.**

### 2.3 Timing does not model metal fill, at all
Timing is computed from SPEF extracted by **OpenRCX** from the post-route database. **OpenRCX
contains no `dbFill` handling whatsoever** (verified at source level), so metal fill contributes
**exactly zero** parasitics. Proof: the SPEF from the filled and unfilled builds is **byte-identical
except for the `*DATE` timestamp**.

⇒ **Any statement that "fill costs nothing in timing" in this project is NOT a measurement.** It is
the extractor being blind to fill. The mitigation relied upon is that stock ORFS fill is
DRM-compliant and keeps fill **2.0 µm** from circuit metal (DM.3), which bounds the unmodelled
coupling — it does not eliminate it.

### 2.4 No fabrication, no silicon correlation
No wafer, no measured silicon, no correlation of the RC models against hardware. `gf180mcu` is a
real production process, but nothing here has been through it.

## 3. Known limitations and open issues

| # | Issue | Status |
|---|---|---|
| 1 | **Minimum metal density M1/M2/M3 is NOT met at block level** (M1 28.6%, M2 17.2%, M3 17.8% against a >30% rule, flat-mode measurement on the stock DRM-compliant-fill build; deep mode gives M1 17.9% / M2 16.5% / M3 17.8% on the SAME geometry — a mode dependence we have not resolved, though all three layers fail either way). M4/M5/MetalTop close. | **OPEN — by design.** This is a **chip-integration obligation**, not a block defect: the reference open-silicon flow (efabless) integrates the user block, **generates fill at chip level**, and only then checks density on the final layout. Block-level attempts to close it produced DRM-illegal geometry (see §2.1). |
| 2 | **Timing impact of metal fill is UNMEASURABLE** with this toolchain. | **OPEN.** See §2.3. Would require a fill-aware extractor, or grounding the fill so it becomes an extracted net. |
| 3 | **`dnwell`/`nwell`/`lvpwell` were unmeasured** in earlier releases of this work. | **CLOSED 2026-08-26** — all three now run and return **0**. Root cause of the earlier gap was our own `--run_mode=deep` flag disabling the deck's `--split_deep` mitigation, not a tool limit. |
| 4 | **EBREAK is non-compliant**: `mtval` carries a constant +1 offset for both `ebreak` and `c.ebreak`. | **OPEN, documented deviation.** Verified one-line fix exists and is deliberately NOT applied; vendored RTL is unmodified. Not reachable in this configuration (no debug module). |
| 5 | **JTAG / debug is DISABLED.** `DEBUG=enable` makes EBREAK report `mcause=2` instead of `3`. | **OPEN.** The compliant configuration is the one characterised and closed. |
| 6 | **Formal equivalence is weak**: 122/314 points proven, 0 counterexamples. | **OPEN.** Absence of counterexamples is not proof of equivalence. |
| 7 | **PMP failure** — blocks the secure-element use case. | **OPEN.** |
| 8 | **fmax-ceiling claim SUSPENDED** — `DONT_USE_CELLS = *_1` was never applied to the adders, so the "architectural ceiling" characterisation is not established. | **OPEN.** |
| 9 | **LVS** | See §4 — status must be filled in at release time from the actual result, never assumed. |

## 4. LVS — statement must match the evidence at release time

Three earlier attempts concluded *"LVS is blocked at the tooling level"*. That conclusion was
**correct for KLayout's hierarchical path and over-broad as stated**: in `--run_mode=deep` KLayout
builds a circuit for every cell it finds, and its SPICE reader cannot represent a **device-free**
subcircuit, so `fill`/`filltie`/`endcap` can never match. In **flat** extraction there are no
per-cell circuits at all and the problem does not arise.

### Status as of this release: **UNPROVEN**

A KLayout **flat** extraction of the unfilled build succeeded (**307,139 devices, 0 subcircuit
calls** — flat extraction has no per-cell circuits, so the device-free-subcircuit limitation that
blocked the hierarchical path does not arise). That netlist was compared against a schematic built
from the post-route Verilog plus the 27 antenna-diode instances, using netgen with the cell policy in
`reports/LVS_CELL_POLICY.md`.

netgen reports a mismatch that is **not yet resolved**:

```
Circuit 1 (layout)    : 307,139 devices   136,124 nets
Circuit 2 (schematic) : 317,364 devices   164,922 nets   *** MISMATCH ***
```

We do **not** know yet whether the residual difference is structural (netlist-construction or
device-reduction differences between the two tools) or a real connectivity discrepancy. **We are not
closing that gap by widening the exclusion list** — an LVS whose exclusions are tuned until it passes
is not a result. Until it is understood, this release states LVS as **unproven**.

What IS established, and is not a small thing: the design's own logic reconciles — an earlier
hierarchical run cross-referenced **29,522 subcircuit instances over 92 cell definitions** one-for-one
with pin order and device counts verified, and **not one mismatching circuit was a logic cell, net or
device**; every one was a device-free physical-only cell.

Permitted phrasings, choose by evidence:
- If netgen reports a clean match: *"LVS clean via KLayout flat extraction + netgen compare, with
  device-free physical-only cells ignored symmetrically and antenna diodes included."* State the
  cell policy explicitly (see `pv/rstsync/lvs/LVS_CELL_POLICY.md`).
- If it does not: *"LVS unproven; KLayout hierarchical LVS blocked by a documented tool limitation;
  netgen path attempted, result: <state it>."*
- **Never** *"LVS is impossible"* and **never** *"LVS clean"* without naming the cell policy — an LVS
  whose exclusion list is undisclosed is not a result.

## 5. Claim discipline (binding on all release text)

- DRC: **"0 violations across N tables, run to completion"** with N stated. Never an unqualified
  "DRC clean". Name what was not measured.
- Frequency: always with conditions — corner, voltage, cell tier, metal stack, extraction.
- Reset: **"recovery and removal enumerated across 3 corners: 0 negative of 1,450 timed async pins,
  with a 3-pin false path scoped to the synchronizer itself."** This is containment plus a timing
  measurement — **NOT a metastability proof.** No MTBF figure is computed anywhere, because no
  measured τ/T0 exists for these cells; inventing one would be fabrication.
- Density: never claim compliance from the deck's global average (§2.2).
