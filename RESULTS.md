# Measured results

Every number here is measured, and every number carries the conditions under which it was measured.
Where something was **not** measured, that is stated rather than omitted.

**Conditions (apply to all timing/power figures):** corner `ss_125C_4v50` (worst of c1ss/c2tt/c3ff),
rail 5.0 V, cell tier `gf180mcu_fd_sc_mcu9t5v0` (9-track), metal stack 5LM_1TM, post-route SPEF,
propagated clocks.

## Timing

| metric | value |
|---|---|
| Closed period / frequency | 40.0 ns / **25.0 MHz** (commit target) |
| `period_min` → fmax | 37.76 ns → **26.48 MHz** |
| Setup WNS / TNS / violators | **+2.24 ns** / 0.0 / **0** |
| Hold WNS / TNS / violators | **+0.209 ns** / 0.0 / **0** |
| Recovery violators | **0** of 1,450 timed async pins |
| Removal violators | **0** of 1,450 timed async pins |
| DRV vs 2.80 ns library limit | **0** |
| DRV vs the 1.6 ns optimisation target | 488 (target is deliberately below the library limit) |

### The recovery/removal number is the point of this release

Stated precisely: **recovery and removal enumerated across 3 corners — 0 negative of 1,450 timed
async pins, with a 3-pin false path scoped to the synchronizer itself.**

The previous sign-off's "no violators" was **vacuous** — a blanket `set_false_path -from RST_N`
disabled both checks. Lifting it measured **41 removal endpoints below zero, worst −0.622 ns**.
See `PROVENANCE.md` §4.2 and `reports/removal_recovery_audit.log`.

The check population is itself verified non-vacuous: **1,453 async pins seen = the 1,450 predicted
from the flop census (1384 `dffrnq_1` + 66 `dffsnq_1`) plus the 3 new synchronizer flops.**

## Physical

| metric | value |
|---|---|
| Die | 1703.2 × 1703.2 µm = 2,900,805 µm² |
| Design area | 1,519,823 µm² @ **53%** utilisation |
| Instances | 107,248 (28,825 logic + 78,423 physical-only) |
| Flops | 3,678 (3,675 core + 3 synchronizer) |
| Nets | 29,861 |
| Power | **0.255 W** — default activity, **no VCD/SAIF annotation** |

## Physical verification — real GlobalFoundries KLayout deck

Deck: GF180MCU **variant C** (metal_top 9K / mim_option B / 5LM), from the open_pdks build
(`volare enable --pdk gf180mcu c6d73a35…`). Top cell `eclass_top`.

| check | scope | result |
|---|---|---|
| **Foundry DRC** | **53 tables, run to completion** | **0 violations** |
| ├ `dnwell` / `nwell` / `lvpwell` | previously unmeasurable | **0 / 0 / 0** |
| ├ `comp` / `via2` / `via3` / `metal3` | the tables that once held 154,574 | **0** |
| **Off-grid** | **95** `*_OFFGRID` rules (verified enabled) | **0** |
| **Antenna** | 21 ANT categories, run twice on two machines | **0** |
| Route DRC (ORFS internal) | — | 0 |
| PSM (IR/EM) | — | clean, 0 |
| **Density M4 / M5 / MetalTop** | filled build | **closed** (rule not emitted) |
| **Density M1 / M2 / M3** | filled build | ❌ **NOT met** — 28.6% / 17.2% / 17.8% vs >30% |

All physical-verification rows above are measured on the **stock-fill build** — the tapeout
candidate — except LVS, which by necessity runs on the unfilled build (see §LVS).

**A measurement caveat we are not hiding:** density coverage is **mode-dependent**. The same GDS
measured `--run_mode=deep` gives M1 **17.9%** / M2 16.5% / M3 17.8%, and `--run_mode=flat` gives
M1 **28.6%** / M2 17.2% / M3 17.8% — a 10-point difference on Metal1 for identical geometry. We do
not know which mode is correct and have not resolved it. What is robust either way: **all three
layers fail under both modes**, so the conclusion is unaffected; only the precise figure is
uncertain. The numbers quoted above are flat mode, the mode used for the 53-table DRC signoff.

**On the DRC number:** the earlier campaign could only claim *"0 across 34 of 40 tables, three well
tables unmeasured"*, because the deck was run in `--run_mode=deep`, which silently disables its own
`--split_deep` mitigation; it ran 14–20 h without completing. In `--run_mode=flat --split_deep` it
completes in **34 minutes across 53 tables**. `nwell_split` alone finished in **99.9 seconds** —
a table that had been unmeasurable for 20 hours.

**On density:** see `DISCLAIMERS.md`. It is a chip-integration obligation, and the deck's density
rule is in any case a *global-average simplification* of a windowed (200 µm × 200 µm at 100 µm step)
rule, so deck-derived density numbers are not compliance evidence either way.

## Functional verification

| check | result |
|---|---|
| RISCOF compliance vs Spike (pinned by commit) | see `reports/` — **with documented EBREAK deviation** |
| Verilator smoke (core direct) | `SMOKE_PASS data=0x000007ab cycles=57` |
| Verilator smoke (through wrapper) | `SMOKE_PASS data=0x000007ab cycles=60` |
| Reset synchronizer unit TB | `RESET_SYNC_PASS`, 64 randomized release phases |

The wrapper run is **+3 cycles** — exactly the three synchronizer stages, observed end-to-end. The
test asserts that delta is *exactly* 3, so a chain collapsed to 1 stage or extended to 4 would fail.

## What was NOT measured

- **Timing impact of metal fill.** OpenRCX has no `dbFill` handling; filled and unfilled SPEF are
  byte-identical apart from the timestamp. Any "fill costs nothing" claim would be the tool being
  blind, not a measurement.
- **Power under real activity.** No VCD/SAIF; the 0.255 W figure is default-activity.
- **Silicon.** Nothing here has been fabricated.
- **LVS** — status is recorded in `DISCLAIMERS.md` §4 from the actual run, not assumed.
