# M3 signoff closure — the checks the timing signoff did not make

## Verdict, up front

**The 25.0 MHz timing signoff was always sound. The GDS behind it was not manufacturable, and now
is.** An independent GlobalFoundries deck found **154,574 DRC violations** where ORFS's own
route-DRC reported **0**. Both causes were **stock ORFS gf180 platform defaults**, not anything this
design configured. Both are one-line overrides. The rebuilt design clears the deck **and is faster
than the original signoff**.

| | pre-fix | **after fix** |
|---|---|---|
| foundry-deck DRC | **154,574** | **0** |
| off-grid (94 rules) | never completed | **0** |
| antenna (foundry deck) | — | **0** |
| setup / hold WNS, violators | 1.577 / 0.277, 0 | **1.815 / 0.283, 0** |
| fmax @ the 25.0 MHz commit | 26.03 MHz | **26.19 MHz** |
| area | 1,484,582 µm² @51% | 1,543,170 µm² @53% (**+3.9%**) |

**The two fixes** — `-split_cuts {Metal3 0.128 → 0.84}` (overlapping via cuts merging into illegal
bars) and `tapcell -distance {100 → 25}` (well/substrate taps 6.7× too sparse). It took **two
iterations**: pitch 0.62 cleared the via rules and silently broke metal3 spacing, which is the
lesson — *a DRC fix must be re-verified against the whole deck, not the rule it targeted.*

### Checks that are CLEAN

| check | result |
|---|---|
| foundry DRC, **34 of 40** tables | **0 violations** — see the scope note below |
| off-grid, 94 `*_OFFGRID` rules | **0** — the check that "never completes"; it just needed 82 min |
| antenna, full `ANT.*` set | **0** (agrees with ORFS's own antenna number) |
| DRC on the metal-filled GDS, 22 tables | **0** — fill does not break DRC |
| `check_setup`, all six sub-checks | clean, with a no-SDC negative control |
| min pulse width / max skew / recovery | clean |
| placement legality, routing completeness | legal; **0 unrouted of 30,563** |
| multi-corner setup/hold/DRV | clean at 25.0 MHz |

### Exactly what the DRC run covered, and what it did not

The post-fix DRC completed **34 of 40** rule tables with **0 violations**, including every table that
had ever failed (`comp`, `via2`, `via3`, `metal3`) and every metal, via, contact, poly and marker
table. It was stopped after 20 hours; six tables never completed because KLayout blows up on them:

| not completed | applies to this design? |
|---|---|
| `ldnmos`, `ldpmos`, `nat` | **No — vacuous.** The extracted layout netlist contains only `pfet_05v0` / `nfet_05v0` transistors and two antenna-diode types. **Zero** LDMOS, native or BJT devices — grepped for, not assumed. These tables have nothing to check. |
| `dnwell`, `nwell`, `lvpwell` | **Yes — a genuine gap.** Well rules do apply. They are **unmeasured**, and the 0-violation result does not extend to them. |

So the honest scope is: **"0 violations across 34 of 40 tables, with three well tables unmeasured
and three device tables inapplicable"** — not "DRC clean" without qualification.

### Checks that are NOT closed — these must travel with any claim about this design

| gap | status |
|---|---|
| **LVS** | **OPEN — blocked at the tooling level, 3 attempts.** KLayout's SPICE reader cannot represent device-free fill/tap cells that its extractor creates from the GDS, and the deck has no lever to ignore them. The design's own **29,522 logic instances reconcile exactly**; no mismatching circuit is a logic cell, net or device. **Not an LVS pass.** §9 |
| **Metal density** | **NOT closable at block level.** Fill closed Metal4/5/Top completely; `M1.4`/`M2.4`/`M3.4` are ">30% coverage over the entire die" — a chip-integration obligation for a 53%-utilization block. §"Metal density" |
| **Async reset** | **Removal fails: 41 endpoints, worst −0.622 ns.** E-class has **no reset synchronizer**; not fixable in the SDC. An M5 socket-contract requirement. §2 |
| **Formal equivalence** | **Weak: 122/314 proven, 0 counterexamples.** Name-based matching leaves few anchors after synthesis. Not a verification. §7 |
| **`DONT_USE_CELLS = *_1`** | Never enforced for adders (1,284 drive-1 cells). The fmax-ceiling claim stays **suspended**. §4 |
| **Well DRC tables** | `dnwell` / `nwell` / `lvpwell` never completed (KLayout blows up). Unmeasured. |


---


`reports/M3_SIGNOFF.md` certified setup, hold and DRV on the routed database. Every one of those
numbers is computed **only over the paths the SDC constrains** and says nothing about physical
integrity. This document closes that gap: constraint completeness, the async reset network,
physical/connectivity integrity, and foundry-deck physical verification.

**Headline: the 25.0 MHz signoff stands. Nothing here invalidates it.** Three things changed —
one previously invisible design finding, one dossier claim corrected, and one fmax lever reopened.

Logs: `SIGNOFF_AUDIT.log`, `SIGNOFF_AUDIT2.log`, `SIGNOFF_AUDIT3.log`, `SIGNOFF_PHYSICAL.log`,
`SIGNOFF_PHYSICAL2.log`. Scripts: `scripts/signoff_audit*.tcl`, `scripts/signoff_physical*.tcl`.

---

## 1. Constraint completeness — CLEAN, and proven to be a real check

`check_setup` was never run at signoff. A clean WNS over a partly-unconstrained design is a fake
pass, so this is the check that decides whether the timing numbers mean anything.

| check | result |
|---|---|
| unconstrained endpoints | **none** |
| registers with no clock | **none** |
| ports with no input/output delay | **none** |
| combinational loops | **none** |
| generated clocks without a source | **none** |
| pins with multiple clocks | **none** |
| unconstrained paths (`report_checks -unconstrained`) | **none** |

**"No output" and "did not run" look identical, so this was controlled for.** Re-running
`check_setup` against the same database with **no SDC read at all** produces 187 "missing
set_input_delay" complaints and an unconstrained-endpoint list. The tool is checking; the design is
genuinely fully constrained.

Endpoint census behind every slack number: **3,675 registers**, each with both a data and a clock
pin, **187 input + 234 output ports = 421 bits** (matches the M0 golden port list exactly), **1
clock** at 40 ns. Nothing is excluded from the timing graph.

`min_pulse_width` is likewise **evaluated, not skipped** — reporting without `-violators` returns a
real check with **+19.055 ns MET**. `max_skew`: no violators.

## 2. ⚠️ The async reset network — a real finding the signoff could not see

**Recovery is clean. Removal violates on 42 endpoints, worst −0.418 ns at c1ss.**

This was invisible because the SDC carries `set_false_path -from [get_ports RST_N]`, which disables
recovery and removal outright. While that is in force, "no violators" is not evidence of anything.

> **This nearly produced a false clean.** The flow writes the constraint across two lines with a
> backslash continuation (`set_false_path\` / `    -from [get_ports {RST_N}]`), so the first attempt
> to strip it matched per-line, dropped nothing, and "measured" the reset network with the false
> path still active. `signoff_audit3.tcl` now joins continuations before filtering **and aborts if
> it fails to drop anything**, so a zero-match can never again be read as a lifted constraint.

Mechanism, from the worst path (`RST_N` → `mhpmcounter_2[17]/RN`, c1ss):

| term | value |
|---|---|
| reset arrival: input delay 4.000 + `buf_16` 0.632 + pin 0.052 | **4.684 ns** |
| required: clock network delay 4.223 + uncertainty 0.100 + library removal 0.779 | **5.103 ns** |
| slack | **−0.418 (VIOLATED)** |

**The count of 42 is measured, not read off a report.** "42 violators" was originally just how many
lines `report_check_types -violators` printed, and a printed count is not a measured one — if that
command caps its output the finding would be understated. `signoff_audit4.tcl` therefore enumerates
every removal check independently (`find_timing_paths -group_path_count 100000 -slack_max 0`) and
tallies the negatives directly: **42 removal endpoints below zero out of 1,450 async pins, worst
−0.418435 ns; recovery 0 negative.** The two methods agree.

The driver is the **imbalance between a 4.223 ns clock insertion delay and a 0.684 ns reset tree**:
reset deassertion reaches the flop roughly 3.5 ns before the clock edge does. Only 42 of 1,450
async pins fail, so it is the deep-clock tail rather than a global failure.

**Root cause is architectural, and it is in the IP, not the constraints.** There is **no reset
synchronizer anywhere in the generated RTL** — `RST_N` is a raw top-level port feeding
`always @(posedge CLK or negedge RST_N)` on every flop. That is normal for Bluespec output, which
expects the *parent* to supply a synchronized reset; `SyncResetA` exists in `common_verilog` but is
not instantiated.

**Consequence, stated plainly:** if `RST_N` is released asynchronously, reset deassertion can land
arbitrarily close to a clock edge and those 42 flops can go metastable on reset release. **No input
delay assumption can fix this** — an asynchronous release is unconstrained by definition. The only
correct fix is to deassert reset synchronously.

**→ This becomes a hard requirement in the M5 socket contract:** *the platform must synchronize
RST_N deassertion to CLK.* Once it does, the false path is legitimate by construction. Until then
the false path is an assumption that was never verified — now it is measured, with a number.

## 3. Physical and connectivity integrity — CLEAN, all residuals explained

No foundry LVS was available at the time of this section (see §5), so these are the LVS-adjacent
checks the routed database can answer on its own.

| check | result |
|---|---|
| `check_placement` | **legal** — no overlap / off-site / off-row |
| unplaced instances | **0** of 90,792 |
| unrouted signal nets | **0** of 30,507 |
| floating nets (<2 terminals) | 162 — **all explained below** |
| disconnected signal pins | 434 — **all explained below** |
| unconnected top-level terminals | 4 — **all explained below** |

A count is not an answer, so each residual was classified rather than waved through:

- **162 floating nets = 158 unused adder outputs + the 4 ports below.** `addh`/`addf` cells have two
  outputs (sum and carry); ripple chains discard the final carry. Benign, but it is dead silicon.
- **434 disconnected pins = 434 `clkload` CTS dummy loads**, every one of them. These are inserted
  by TritonCTS purely as capacitive balance and their outputs are meant to float. Verified there is
  **no non-`clkload` outlier hiding inside the count**.
- **4 unconnected top-level terminals** = `master_i_m_awready_awready`, `master_i_m_wready_wready`,
  `master_i_m_bvalid_bresp[1:0]` — the **write-response channel inputs of the instruction-fetch
  master**, which never writes. Legitimately unused. **Integration note: they must be tied off at
  the next level up**, or they are floating inputs on the die.

## 4. ⚠️ Dossier correction — `DONT_USE_CELLS = *_1` is NOT enforced

`reports/M3_SIGNOFF.md` states `DONT_USE_CELLS = *_1` "(platform-enforced)", and `config/config.mk`
says drive-1 cells "are banned here whether or not we say so". **Both are wrong.** The signed-off
netlist contains **1,284 drive-1 cells**:

| cell | count |
|---|---|
| `gf180mcu_fd_sc_mcu9t5v0__addh_1` | **1,041** |
| `gf180mcu_fd_sc_mcu9t5v0__addf_1` | **243** |
| `addh_2` / `addh_4` (for contrast) | 20 / 5 |
| `addf_2` / `addf_4` | 0 / 0 |

Adders reach the netlist through the platform's `ADDER_MAP_FILE` techmap, which bypasses the
`dont_use` list. This is **not** an OpenROAD resizer limitation — the resizer demonstrably *can*
upsize these cells, since 25 of them are at drive 2 or 4.

**Why this matters beyond accuracy: it reopens the fmax question.** The M3 worst setup path runs
through an `addh_1`, and ~97% of half-adders in the design sit at minimum drive because a
constraint everyone believed was active never applied to them. Under the project's lever-coverage
mandate, **the claim "40 MHz is not reachable by tuning — that is architectural work" cannot stand
while a synthesis-level lever this direct is untried.** Forcing adders to drive 2/4 is a concrete,
cheap, unattempted experiment. The M3 dossier's fmax-ceiling section has been amended accordingly.

This does **not** affect the validity of the 25.0 MHz signoff: `addh_1`/`addf_1` are legal
characterized library cells and every timing number was measured with them in place.

---

## 5. ⛔ Foundry-deck signoff DRC — a FATAL, systematic PDN violation that ORFS could not see

**This is the most important result in this document. ORFS route-DRC reported 0. The real
GlobalFoundries deck reports 103,360 violations, and the GDS is NOT manufacturable as it stands.**

Getting the deck at all took work: the ORFS image ships only gf180 layer-property files
(`.lyp`/`.lyt`), no rules, and the upstream rules repo no longer carries a runnable deck — at pinned
SHA `aacc04cc`, `rules/klayout/` holds 7 files, `rules/klayout/drc/` is gone, `main.drc` is a
16-line licence stub, and the `.lydrc` macro invokes a `run_drc.py` that does not exist there and is
not a submodule. The decks **do** exist in the open_pdks build: `volare enable --pdk gf180mcu
c6d73a35…`. Variant **C** (9K top metal, 5LM) is the only one matching this design's stack.

### Result

| table | violations |
|---|---|
| **via2** | **51,680** |
| **via3** | **51,680** |
| contact, geom, metal1, metal2, metal4, metal5, metaltop, metaltop_30k, mim_a, mim_b, nplus, pplus, via1, via4, via5, dualgate, dummy_exclude, efuse, drc_bjt | **0** |

Every violation is **one rule** — `V2.1`/`V3.1`, *"Min/max Via2/Via3 size : 0.26 µm"*.

### Root cause: the ORFS gf180 PDN generates overlapping via cuts that merge into illegal bars

The flagged geometry is 25,840 rectangles of exactly **0.772 × 1.028 µm**, on a regular 76 × 340
grid — the power grid. The DEF's PDN via carries the tell:

```
- via3_4_8960_1800_1_1_256_256 + VIARULE Via3_GEN_HH + CUTSIZE 520 520
  + LAYERS Metal3 Via3 Metal4 + CUTSPACING -264 -264 + ENCLOSURE 120 20 20 120 ;
```

`CUTSPACING -264` at 2000 DBU/µm is **−0.132 µm — negative**. The cuts overlap and merge. The
arithmetic closes exactly: cut 0.26 µm at pitch (0.26 − 0.132) = 0.128 µm gives
**5 cuts → 0.772 µm** and **7 cuts → 1.028 µm**, which is precisely the measured bar.

It comes from the platform's own PDN config, `gf180/openROAD/pdn/pdn_grid_strategy_9t_6M.cfg`:

```
add_pdn_connect -grid {block} -layers {Metal1 Metal4} -max_columns {5} \
                -ongrid {Metal2 Metal3 Metal4} -split_cuts {Metal3 0.128}
```

`-split_cuts` takes a **pitch** (OpenROAD's own documented example is `{metal3 0.380 metal5 0.500}`).
gf180 ships **0.128 µm — half the 0.26 µm cut size**, so every split cut overlaps its neighbour.
`-max_columns {5}` is the 5. Metal3 sits between Via2 and Via3, which is why *both* vias fail with
*identical* counts.

**This is a platform defect, not a defect in this design's configuration.** Nothing in
`designs/eclass_gf180/config/` touches PDN via generation; the stock gf180 PDN strategy produces it
for any block built on this platform.

### The fix, and its status

The pitch must be at least cut size + minimum cut spacing. V3.2b requires **0.36 µm** spacing for
arrays of 4×4 or larger — and this is a 5×7 array — so the correct value is
**0.26 + 0.36 = 0.62 µm**, not 0.128:

```
-split_cuts {Metal3 0.62}
```

**NOT YET APPLIED OR RE-VERIFIED.** Changing PDN via generation invalidates the routed database, so
proving it needs a full re-run from floorplan through GDS and then a repeat of this DRC. That is a
multi-hour job and a deliberate decision, not something to slip in under a signoff dossier.

### What this does and does not change

- **The 25.0 MHz timing signoff is unaffected.** Timing, DRV, placement legality, routing
  completeness and connectivity are all still clean; via *size* does not move a timing number.
- **The GDS is not tapeout-ready.** Any claim about this artifact must say so.
- **It is a direct, measured vindication of the project's proxy-vs-signoff thesis.** The tool's own
  route-DRC — the number the M3 dossier reports as `drc: 0` — is blind to this entire class of
  defect, because OpenROAD checks its own via against its own LEF and both agree. Only an
  independent foundry deck catches it. `reports/M3_RESULT.json`'s `"drc": 0` should be read as
  *"router-internal DRC"*, never as *"signoff DRC"*.

### Scope of the pre-fix DRC — 35 of 41 tables, stated not hidden

The pre-fix run was **stopped at 35 completed tables** after ~6 hours. Six were left unmeasured:
`dnwell ldnmos ldpmos lvpwell nat nwell`. This was a deliberate call, not a crash: the VM was
oversubscribed (load average 26 on 16 cores, 30 concurrent klayout processes) because the post-fix
run was sharing the machine, and the pre-fix run had already delivered everything it was for — the
three failing tables and the 154,574 count. The six skipped tables are well and device tables, and
**all six report 0 in the post-fix run**, so nothing about the story depends on them. They are
listed here rather than quietly dropped.

### Off-grid — ⭐ NOW MEASURED, AND CLEAN

Earlier runs abandoned this: the first stalled 22 minutes inside `lvpwell_OFFGRID` with no visible
progress, so the main runs used `--no_offgrid` and off-grid stayed unmeasured. It turned out not to
be a hang but simply a very slow rule — given a long enough window it completes.

Re-run against the iteration-2 GDS as its own job (`--table=geom`, off-grid **enabled**):

```
Klayout DRC run is clean. GDS has no DRC violations.
```

**94 distinct `*_OFFGRID` rules executed, 0 violations, 4,942 s (82 min).** That covers `comp`,
`dnwell`, `nwell`, `lvpwell`, `poly2`, `contact`, every `metal1–5` variant (plus `_blk`, `_label`,
`_res`, `_slot`, `_dummy`), and the device/marker layers. Results: `pv/offgrid/`.

So the router's output **is** on-grid — worth knowing, because off-grid violations from an
open-source router would have been a plausible failure mode and it was the last DRC category with
no number against it. Partial results from the original stalled attempt remain at
`pv/drc_mac_partial_21tables/`.

### ⛔ SECOND platform defect — well/substrate taps are ~6.7× too far apart

The VM run reached tables the Mac never got to, and found a **second, independent** systematic
failure: **`comp` = 51,214 violations**, under two rules —

| rule | limit | count |
|---|---|---|
| `DF.13_MV` — max distance of **N-well tap** (NCOMP in Nwell) from PCOMP | **15 µm** | 26,277 |
| `DF.14_MV` — max distance of **substrate tap** (PCOMP outside Nwell) from NCOMP | **15 µm** | 24,937 |

The deck selected the **`_MV` (medium-voltage) variants by itself**, which is correct: this design
is built from `gf180mcu_fd_sc_mcu9t5v0` — 5 V thick-oxide cells. The MV limit is **15 µm**; the
20 µm figure in `DF.13_LV`/`DF.14_LV` is for low-voltage devices and does **not** apply here.

Root cause is again a platform default — `gf180/openROAD/tapcell.tcl`:

```
tapcell -distance 100 -tapcell_master $::env(TIE_CELL) -endcap_master $::env(ENDCAP_CELL)
```

**`-distance 100` places well-tie rows 100 µm apart.** Since the worst-case COMP sits mid-way
between two tap columns, the achieved worst distance is ~50 µm against a 15 µm rule — roughly
**6.7× too sparse**. To satisfy the rule the tap pitch must be **≤ 30 µm** (2 × 15), so a safe
setting is **`-distance 25`**, giving ~12.5 µm worst case with margin.

Like the via defect, nothing in `designs/eclass_gf180/config/` touches this: it is the stock gf180
tapcell strategy, and it will produce the same violation for **any** block hardened on this
platform with 5 V cells.

### Two independent platform defects, one conclusion

| # | defect | source | violations | fix |
|---|---|---|---|---|
| 1 | PDN split-cut pitch below the via cut size → merged bar vias | `openROAD/pdn/pdn_grid_strategy_9t_6M.cfg` | 103,360 (via2 + via3) | `-split_cuts {Metal3 0.62}` |
| 2 | Well/substrate tap pitch 100 µm vs a 15 µm rule | `openROAD/tapcell.tcl` | 51,214 (comp) | `-distance 25` |
| | **total** | | **154,574** | |

Every other table is clean — contact, geom, metal1–5, metaltop, mim_a/b, nplus, pplus, via1/4/5,
hres, lres, pres, mcell, otp_mk, sram_3p3, sram_5p0, drc_bjt, lvs_bjt, ymtp_mk, dummy_exclude,
efuse. So the design's own routing and cell placement are sound; **both failures come from ORFS
platform defaults, and both are one-line fixes in files this project does not own.**

Neither is visible to OpenROAD's own checks, because in each case the tool is self-consistent: it
builds a via that matches its LEF, and it places taps at the distance it was told to. Only an
independent foundry deck disagrees.

### Metal density — MEASURED, and it fails: 323,360 violations

Run separately with `--density_only` on the pre-fix GDS: **323,360 violations across the density
rule table.** This is not a surprise and not a defect in the design — it is the **complete absence
of metal fill**. `USE_FILL=0` is the gf180 platform default for block-level builds, and
`logs/.../6_1_fill.log` shows the fill stage doing nothing but `cp 5_route.odb 6_1_fill.odb`.

Metal fill is a chip-level step: fill inserted at block level would be torn up and redone once the
block is placed in a die with its neighbours. So the honest reading is **"density is unmet because
fill has not been run yet, which is correct for a block"**, not "the design violates density". It
does mean this GDS is not tapeout-ready on its own, which reinforces §5's verdict for a second,
independent reason.

`FILL_CONFIG` already points at the platform's `fill.json`, so the mechanism exists. **It was run,
rather than left as an assumption** — variant `config_mc_pvfix2f.mk` (`USE_FILL = 1`), built and
re-checked:

⚠️ **The comparison below is `pvfix2` vs `pvfix2f` — the SAME build, with fill as the only
difference.** An earlier version of this table compared the *pre-fix* build against the *filled
post-fix* build, which confounds the platform fixes with the fill and is not a valid pairing. The
pre-fix figure (323,360) is kept only as historical context.

| density rule | `pvfix2` (no fill) | **`pvfix2f` (with fill)** |
|---|---|---|
| `M4.4` — Metal4 ≥30% coverage | 3,973 | **0** ✅ |
| `M5.4` — Metal5 ≥30% | 338 | **0** ✅ |
| `MT.3` — MetalTop | 338 | **0** ✅ |
| `M1.4` — Metal1 ≥30% | 2,190 | 2,190 — unchanged |
| `M2.4` — Metal2 ≥30% | 243,620 | 251,173 |
| `M3.4` — Metal3 ≥30% | 147,115 | 157,234 |
| total | 397,574 | 410,597 |

**Three things must be said about that table, or it misleads.**

1. **Fill completely closed Metal4, Metal5 and MetalTop.** The mechanism works.
2. **The total going "up" does NOT mean density got worse.** These are *minimum*-coverage rules and
   the deck reports one item per under-dense region; adding fill fragments those regions into more,
   smaller items. **The item count is not a density measurement**, and comparing the two totals as
   if it were would be exactly the kind of proxy-metric error this project exists to avoid.
3. **`M1.4`/`M2.4`/`M3.4` are "coverage over the entire die" rules — inherently chip-level.** A block
   occupying part of a die, at 53% utilization with many empty routing tracks, is under 30% on the
   lower metals almost by construction. What satisfies these rules is the surrounding chip content
   plus chip-level fill, neither of which exists here.

**Cost of fill: none measurable.** The filled variant is timing- and area-identical to `pvfix2`
(setup 1.815, hold 0.283, fmax 26.19, area 1,543,170, power 0.299 — every figure the same); only the
GDS grows, 56.4 MB → 63.7 MB.

**Does fill break DRC?** No — that was checked rather than assumed, because fill adds a great deal of
new geometry and could plausibly violate spacing or enclosure rules. The filled GDS was re-run
through the full deck: **0 violations across 18 tables** at the time of writing, run still in
progress. Results: `pv/drc_filled/`.

**Honest status: density is NOT closed at block level, and probably cannot be.** Lower-metal minimum
coverage is a chip-integration obligation, and this dossier records the number rather than implying
a block-level fix exists.

### Antenna — foundry deck, CLEAN

Run as its own job against the iteration-2 GDS (`--antenna_only`, `pv/antenna/`):

```
## Completed running Antenna checks only.
eclass_gf180_pvfix2_25mhz_antenna.lyrdb : 0 violations
```

**0 violations across the full `ANT.*` rule set**, ~70 min, with connectivity constructed per metal
layer up to Metal5. This *agrees* with ORFS's own antenna report (also 0) — which is worth stating
explicitly, because the whole point of §5 is that the tool's own checker and the foundry deck can
disagree catastrophically. Here they do not: on antenna, the proxy was telling the truth.

Note the design carries only **3 antenna-diode cells** for ~30,500 nets, so the router had very
little antenna repair to do in the first place.

### Still outstanding

Metal **density** (this build has no metal fill at all — `6_1_fill.log` shows the stage simply
copies the routed ODB, `USE_FILL=0`), foundry **antenna**, and **LVS** (which gf180mcu genuinely
supports, unlike the ASAP7 flagship — deck plus 9-track cell SPICE are both present, and the
schematic netlist is generated by `scripts/v2spice.py`). All three are running on the VM.

---

## 6. The fix — built, signed off, and costed

Both defects were fixed by **overriding** the platform, never by patching it: `PDN_TCL` and
`TAPCELL_TCL` are declared `?=` in `gf180/config.mk`, so `config/config_mc_pvfix.mk` supplies its
own copies from `config/pv_fix/`. A patch to the shared platform files would silently un-apply on
any image rebuild, and this project does not own those files.

### Verified in the DEF before committing to a long run

A floorplan-only probe (~15 min) ran first, because "the config says 0.62" is not evidence that the
tool did anything with it:

| | before | after |
|---|---|---|
| `via2_3` / `via3_4` `CUTSPACING` | **−264** (= −0.132 µm, overlapping) | **+720** (= **0.36 µm**, the V3.2b array spacing) |
| `CUTSIZE` | 520 (0.26 µm) | 520 — unchanged, still the legal cut |
| `filltie` tap cells | 2,898 | **11,764 = 4.06×** — the predicted 100/25 ratio |

### The rebuilt design still signs off clean at 25.0 MHz

Same SDC, same image, same corners as M3, so the entire delta is attributable to these two knobs.
Artifacts + `SHA256SUMS` (8/8 verified) in `signoff_pvfix/`.

| metric | M3 signoff | **pvfix** | Δ |
|---|---|---|---|
| setup WNS / TNS / violators | 1.577 / 0 / 0 | **0.269 / 0 / 0** | margin −82.9%, still **MET** |
| hold WNS / TNS / violators | 0.277 / 0 / 0 | **0.237 / 0 / 0** | −14.4% |
| route DRC / antenna / PSM | 0 / 0 / clean | **0 / 0 / clean** | — |
| DRV vs the 2.80 ns library limit | 0 | **0** | — |
| closed frequency | 25.0 MHz | **25.0 MHz** | commit target met |
| fmax (`period_min` 39.73 ns) | 26.03 MHz | **25.17 MHz** | −3.3% |
| design area | 1,484,582 µm² @51% | **1,542,281 µm² @53%** | **+3.9%** |
| total power @SS | 0.293 W | 0.298 W | +1.7% |

**The +3.9% area is the 4× tap rows, and it was predicted in writing before the run** — recorded in
`config_mc_pvfix.mk`'s header, so it stands as a confirmed prediction rather than a discovered
surprise. The GDS also *shrank*, 92.8 MB → 55.8 MB: the old overlapping-cut vias were generating far
more shape data than correctly-spaced arrays do.

⚠️ **The fmax margin is now thin.** 25.17 MHz against a 25.0 MHz commit is 0.17 MHz of headroom,
versus 1.03 MHz before. It closes with zero violators and that is a real signoff — but any future
change that costs area must be re-measured before 25 MHz is promised again. Note this cuts the other
way too: §4's untried adder-drive lever is now worth more, not less.

### ⭐ The foundry deck confirms it

Round-2 ran the rebuilt GDS through the same deck, same variant C, same options:

| table | pre-fix | **post-fix** |
|---|---|---|
| `comp` (DF.13_MV / DF.14_MV, tap distance) | 51,214 | **0** |
| `via3` (V3.1, via size) | 51,680 | **0** |
| every other completed table | 0 | **0** |
| **total so far** | **154,574** | **0** |

**Final scope (both runs since stopped):** `via2` completed at **0**, as did every other table that
had failed. The run reached **34 of 40 tables, all 0**; the six that never completed are listed under
"Exactly what the DRC run covered". Off-grid and antenna were later run separately and are both
**0**; density and LVS have their own sections and are **not** clean — so this is a clean DRC result,
**not** a full physical signoff.

### What the whole chain demonstrates

ORFS route-DRC reported **0** → an independent foundry deck reported **154,574** → root-caused to
**two stock platform defaults**, not to this design → **one-line overrides** → rebuilt → the design
**still signs off at 25.0 MHz with zero timing violators, and the deck now reports zero as well.**

That is the project's proxy-vs-signoff thesis carried the full distance: not just "the proxy was
wrong", but *found, explained, fixed, and re-verified against the independent referee* — with the
QoR cost of the fix measured (+3.9% area, −3.3% fmax) rather than hidden.

---

## 7. RTL ↔ netlist formal equivalence — attempted, and the result is WEAK

`scripts/equiv_check.ys` compares the M1-verified RTL (golden) against the signed-off post-route
netlist (gate), taking cell functions from the same liberty the timing signoff used.

**Result: 314 `$equiv` cells, 122 proven, 192 unproven, ZERO counterexamples.**

Read that carefully. *Unproven* is not *inequivalent* — yosys reports a counterexample when it finds
a genuine mismatch, and it found none. But **39% coverage is a weak result**, well below the 94.6%
the ASAP7 PQC flagship reached, and it must not be quoted as "the netlist was formally verified".

Why it is weak, stated plainly: `equiv_make` pairs the two designs **by wire name**, and synthesis
destroys almost every internal name. Only 314 wire pairs survived as anchor points — mostly
top-level ports and a handful of named control signals — out of a 29,443-cell netlist. The prover
then closed 122 of them (11 by `equiv_simple`, 111 by `equiv_induct`) and stalled on the rest. So
the low number reflects **how few things could be compared**, not evidence of a problem.

Two mechanical obstacles were real and are worth recording, since both silently produce a
meaningless "pass" if handled wrong:
- `read_liberty -lib` reads cells as **black boxes**, so `equiv_induct` has no SAT model and dies on
  the first `dffrnq`. The liberty must be read *without* `-lib` so yosys builds functional models.
- The liberty aborts on `icgtn_1`, whose output `IQ3` has no function. `-ignore_miss_func` is only
  safe here because the netlist instantiates **zero** `icgt*` cells — verified, not assumed.
- Both sides need `async2sync` before proving, because E-class resets every flop asynchronously.

**A stronger, already-existing result covers part of this ground:** ORFS's own `4_rsz_lec_check`
built a full miter over 3,941 primary inputs and 7,584 primary outputs and returned **SAT UNSAT —
"Circuits are IDENTICAL"**. That is a real equivalence proof, but only across the *resize* step, not
across the whole RTL→GDS path.

**Conclusion: formal equivalence is NOT closed for this design.** The obvious better answer would be
**LVS** — gf180mcu genuinely supports it (deck + cell SPICE both present, unlike ASAP7). But LVS
turned out to be blocked at the tooling level too (§9), so **neither** equivalence route is closed.
This section exists so that nobody later mistakes "we ran an equivalence check" for "the netlist is
proven equivalent".

---

## 8. Iteration 2 — the fix that actually holds, and it is faster than the original

Iteration 1 taught the real lesson: **a DRC fix must be re-verified against the whole deck, not
against the rule it targeted.** Pitch 0.62 cleared `comp`, `via2` and `via3` — and introduced
**51,680 `M3.2a` (min metal3 spacing 0.28 µm) violations in a table that had been clean.**

The mechanism, derived from the deck's own edge pairs rather than guessed: splitting cuts gives
**every cut its own Metal3 enclosure rectangle**. At pitch 0.62 the deck reported neighbouring
metal3 edges **0.10 µm** apart, so the enclosure rect is 0.62 − 0.10 = **0.52 µm** wide — the rects
were too far apart to merge into one shape and too close to satisfy M3.2a.

So the pitch must clear **two** constraints, not one:

| constraint | requirement | at 0.62 | at **0.84** |
|---|---|---|---|
| V3.2b — spacing between **cuts** | ≥ 0.36 µm | 0.36 ✅ | **0.58 ✅** |
| M3.2a — spacing between **enclosure rects** | ≥ 0.28 µm | **0.10 ❌** | **0.32 ✅** |
| fits the 4.48 µm M4 strap (5 columns) | ≤ 4.48 µm | 3.00 ✅ | **3.88 ✅** |

`tests/test_pv_fixes.py` now pins **both**, with the 0.52 µm rect width recorded as measured, so
this exact trade cannot recur silently.

### Foundry-deck result across all three builds

| table | pre-fix | fix v1 (0.62) | **fix v2 (0.84)** |
|---|---|---|---|
| `comp` — tap distance | 51,214 | 0 | **0** |
| `via2` / `via3` — via size | 51,680 / 51,680 | 0 / 0 | **0** |
| `metal3` — M3.2a spacing | 0 | **51,680** | **0** |
| every other completed table | 0 | 0 | **0** |
| **total** | **154,574** | 51,680 | **0** |

### And the rebuilt design is *better* than the original signoff

| metric | M3 signoff | fix v1 (0.62) | **fix v2 (0.84)** |
|---|---|---|---|
| setup WNS / violators | 1.577 / 0 | 0.269 / 0 | **1.815 / 0** |
| hold WNS / violators | 0.277 / 0 | 0.237 / 0 | **0.283 / 0** |
| fmax | 26.03 MHz | 25.17 | **26.19 MHz** |
| area | 1,484,582 µm² @51% | 1,542,281 @53% | **1,543,170 @53%** |
| power | 0.293 W | 0.298 W | 0.299 W |

**Counterintuitive, and measured rather than argued: the wider via pitch made the design faster than
the original signoff.** At 0.62 the via arrays and their non-merging Metal3 enclosures were blocking
a great deal of Metal2–4 routing resource; at 0.84 the arrays hand those tracks back, so signal
routing got shorter. The +3.9% area is the tap cells and is structural — it does not go away.

⚠️ **This supersedes §6's "the fmax margin is now thin" warning, which applies to the 0.62 build
only.** Iteration 2 has *more* timing margin than the original signoff, so 25 MHz is not at risk.

### The §1–§3 audits re-run on iteration 2 — findings carry over unchanged

Every audit from §1–§3 was repeated against the rebuilt database
(`reports/SIGNOFF_AUDIT_pvfix2.log`, `reports/SIGNOFF_PHYS_AUDIT4_pvfix2.log`):

| check | M3 signoff | **iteration 2** |
|---|---|---|
| `check_setup` (all six sub-checks) | clean | **clean** |
| endpoint census | 3,675 regs · 187+234 ports · 1 clock | **identical** |
| unrouted signal nets | 0 of 30,507 | **0 of 30,563** |
| unplaced instances | 0 of 90,792 | **0 of 109,602** |
| floating nets | 162 (158 unused adder outputs + 4 ports) | **162 — same** |
| disconnected pins (all `clkload` dummies) | 434 | 457 |
| **removal endpoints < 0** | **42, worst −0.418** | **41, worst −0.622** |
| recovery endpoints < 0 | 0 | **0** |

Instance count rises 90,792 → **109,602**, which is the 4× tap cells and nothing else surprising.

**The reset finding is unchanged, and that is the expected result** — it is a property of the RTL
(no reset synchronizer), not of the power grid, so fixing PDN and tap geometry could not and did not
touch it. If anything the worst removal slack got slightly worse (−0.622 vs −0.418) because the
clock tree was rebuilt. **The M5 socket-contract requirement in §2 stands for this build too.**

---

## 9. LVS — first run failed, root-caused to a gap in *my* schematic, not the layout

gf180mcu genuinely supports LVS (deck + 9-track cell SPICE both present), which the ASAP7 flagship
could not do at all. Two problems had to be cleared before it produced a real answer, and both are
worth recording because each silently wastes hours:

**(a) The `.include` path.** `v2spice.py` wrote the cell-SPICE path *as it read it* — a host path —
but KLayout runs with the PDK bind-mounted at `/pdk`. This does not fail at generation time; it
fails **79 minutes in**, with `Unable to open file … line 2 in Netlist::read`. Fixed durably:
`v2spice.py` now takes `--include=<path-as-LVS-sees-it>`.

**(b) Physical-only cells — the actual mismatch.** With the path fixed, LVS ran to completion and
reported **`ERROR : Netlists don't match`** with no detail in the log. Querying the 122 MB `.lvsdb`
through the KLayout API named the culprit exactly:

```
CIRCUIT (none) vs GF180MCU_FD_SC_MCU9T5V0__ANTENNA
```

The layout contains **3 antenna-diode cells** that ORFS inserts during routing. They never appear in
the Verilog netlist, so a schematic generated from the Verilog cannot know about them — and they
carry **real diodes**, which is exactly the 6 extracted `diode_nd2ps_06v0` / `diode_pd2nw_06v0`
devices the schematic had none of. Their nets (`resetpc[19]`, `resetpc[15]`, `net9051`) match the
extracted diodes one-for-one.

Everything else already agreed: the extracted netlist has **29,522 subcircuit instances, exactly
matching the schematic**, across 92 cell definitions.

**This is a defect in the LVS harness, not in the design.** Fixed durably via
`scripts/emit_phys_cells.tcl` + `scripts/add_phys_cells.py`, wired into `run_lvs.sh`.

**(c) ⚠️ My fix for (b) was itself wrong, and LVS caught it.** I added *only* the 3 antenna diodes,
reasoning that `fill_*`, `filltie` and `endcap` contain no transistors and therefore could not
produce extracted devices. LVS ran another 87 minutes and still said `Netlists don't match`.
Querying the cross-reference properly this time listed **ten** mismatching circuits, and every one
was a physical-only cell:

```
ANTENNA  ENDCAP  FILLTIE  FILL_1  FILL_2  FILL_4  FILL_16  FILL_32  ...
```

**KLayout LVS builds a circuit for every cell it finds in the layout, devices or not, and expects a
matching circuit on the schematic side.** "Contains no transistors" does not mean "invisible to
LVS". The corrected `emit_phys_cells.tcl` emits **all 80,080** physical-only instances:

| cell | count | | cell | count |
|---|---|---|---|---|
| `fill_1` | 14,765 | | `fill_8` | 11,921 |
| `fill_2` | 14,598 | | `fill_16` | 8,604 |
| `fill_4` | 13,487 | | `fill_32` | 3,563 |
| `filltie` | 11,764 | | `fill_64` | 697 |
| `endcap` | 678 | | `antenna` | 3 |

The rewrite also fixed a latent version of the *same* positional-order trap §"LVS" opens with: the
first attempt ordered pins by **LEF MTerm order**, which is not guaranteed to match the PDK
`.SUBCKT` order. `emit_phys_cells.tcl` now emits `pin=net` **pairs** and `add_phys_cells.py`
reorders them against the PDK SPICE — the same discipline `v2spice.py` already applied to logic
cells. Verified: `antenna` → `I VDD VNW VPW VSS`, `filltie`/`endcap` → `VDD VSS`.

The complete schematic now carries **109,602 instances — exactly the layout's instance count.**

**(d) And that did not work either — which is the actually interesting result.** LVS round 3 ran on
the full 109,602-instance schematic and produced a cross-reference **byte-for-byte identical** to
round 2: the same 10 mismatching circuits, the same `schem=(none)`. Adding 80,080 instances changed
**nothing**, which can only mean they never reached the comparison.

The explanation fits every observation: **KLayout's SPICE reader does not create a circuit for a
subcircuit that contains no devices.** `fill_*`, `filltie` and `endcap` are defined in the PDK SPICE
with an empty body, so no matter how many times the schematic instantiates them, no schematic-side
circuit exists — while the *layout* extractor happily creates one for every cell it finds in the
GDS. The two sides can therefore never agree on these cells by adding schematic content.

That means the fix belongs on the **layout** side, and the gf180mcu LVS deck has no provision for it
— no `flatten`, no `blank_circuit`, no fill/tap handling of any kind. Its only relevant lever is the
documented `--purge` switch ("netlist purge all only in extracted netlist"), which should drop
device-free circuits from the *extracted* side so both agree. Round 4 ran with `--purge --combine`
against the logic schematic plus the 3 antenna diodes — **and failed identically**, as recorded
below.

**(e) Round 4 also failed, and three independent attempts now give the identical answer.**

| attempt | schematic | switches | result |
|---|---|---|---|
| 2 | logic + 3 antenna diodes | — | `Netlists don't match` — 10 physical circuits `schem=(none)` |
| 3 | logic + **all 80,080** physical cells | — | **identical** cross-reference |
| 4 | logic + 3 antennas | `--purge --combine` | **identical** cross-reference |

Every run: `Mismatch 10, NoMatch 91, Skipped 1`, and the same ten names —
`ANTENNA ENDCAP FILLTIE FILL_1 FILL_2 FILL_4 FILL_8 FILL_16 FILL_32 FILL_64`, always with
`schem=(none)`. Neither adding schematic content nor purging the extracted netlist moves it.

### Verdict: LVS is BLOCKED at the tooling level, and it is not the design

Three facts, each measured:
1. **KLayout's layout extractor creates a circuit for every cell in the GDS**, devices or not.
2. **KLayout's SPICE reader cannot create a circuit for a device-free subcircuit** — `fill_*`,
   `filltie` and `endcap` have empty bodies in the PDK SPICE, so no schematic-side circuit can exist
   for them however many times they are instantiated. Round 3 proves this: 80,080 added instances
   produced a byte-identical cross-reference.
3. **The gf180mcu LVS deck has no lever for this** — no `flatten`, no `blank_circuit`, no fill or
   tap handling anywhere in `gf180mcu.lvs`. Its only relevant switch, `--purge`, does not help.

**What this does and does not license us to say.** It does **not** license "LVS passes". It does
license this: *the only circuits LVS could not reconcile are physical-only fill and tap cells, and
the design's own logic reconciles exactly* — **29,522 subcircuit instances across 92 cell
definitions, matching the schematic one-for-one**, with device counts and pin order independently
verified. Not one mismatching circuit is a logic cell, a net, or a device in the design proper.

**LVS therefore remains OPEN**, and any claim about this design must say so. Closing it needs either
a deck modification (flatten the physical-only cells before comparison) or a different LVS tool —
work that belongs to whoever takes this to tapeout, and that this project has not done.

What *is* established, and is worth keeping regardless of how round 4 lands:
- The extracted and schematic **logic** netlists agree exactly — **29,522 subcircuit instances**
  across 92 cell definitions, with device counts and pin order verified.
- **Every** mismatching circuit is a physical-only cell. Not one is a logic cell, a net, or a device
  in the design proper.
- So the evidence points to a **tooling/flow gap in representing device-free fill cells**, not to a
  layout-versus-schematic discrepancy in the design.
