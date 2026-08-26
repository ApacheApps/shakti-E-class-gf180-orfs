# Provenance — where this RTL came from, and every modification we made

This document exists so that anyone can trace the design in this repository back to its upstream
sources and reproduce every step in between. It is deliberately exhaustive.

---

## 1. Upstream sources

The core is **SHAKTI E-class**, an open-source RV32IMAC processor from the SHAKTI project at
**IIT Madras**. It is written in **Bluespec SystemVerilog (BSV)**, not Verilog — the Verilog in this
repository is *generated* from that BSV (see §3).

All upstream repositories were vendored at explicit commit SHAs:

| repository | URL | commit | license | date |
|---|---|---|---|---|
| e-class | https://gitlab.com/shaktiproject/cores/e-class.git | `e8a0dfd2d1c4907c74fb58432e379016871fdd3a` | BSD-3-Clause (IIT Madras 2018) | 2019-12-17 |
| fabrics | https://gitlab.com/shaktiproject/uncore/fabrics.git | `c3d6da4c515886ebe0462995aa0624090dbef85d` | BSD-3-Clause | 2019-11-19 |
| common_bsv | https://gitlab.com/shaktiproject/common_bsv.git | `89f04a53b4d8db659ed9aade9b3490df70aecaab` | BSD-3-Clause (`LICENSE.iitm`) | 2025-11-25 |
| common_verilog | https://gitlab.com/shaktiproject/common_verilog.git | `029a15059798d5400d0821934f2f36e192b92d01` | MIT (per-file headers; **no repo LICENSE file**) | 2025-05-02 |
| devices | https://gitlab.com/shaktiproject/uncore/devices.git | `c622ad128b81fc74f7a2365241d51488f7b9dd72` | BSD-3-Clause | 2019-11-11 |
| verification | https://gitlab.com/shaktiproject/verification_environment/verification.git | `4e72ce93b774217ab73db3ffd2fd04054e5b959b` | BSD-3-Clause | 2019-11-19 |
| benchmarks | https://gitlab.com/shaktiproject/cores/benchmarks.git | `654ef7f128e2505c366e9be821f566e3a046cdd7` | BSD-3-Clause (`LICENSE.iitm`) | 2025-08-14 |

**We pin all seven.** Upstream's own dependency manager (`e-class/base-sim/manager.sh`) pins only
three and leaves `common_bsv`, `common_verilog` and `benchmarks` floating on `master`. Left floating,
the generated RTL would change silently between runs — `common_verilog`'s newest commit is literally
"new regfile variant". We do not use `manager.sh` (it gates on `dtc 1.4.7` before cloning and would
reintroduce the floating refs).

**The e-class RTL is frozen upstream at 2019-12-17** (tag `1.10.2`). The later branch
`89-fix-compilation` (2025-05-19) touches only build infrastructure — `.gitlab-ci.yml`,
`base-sim/Makefile`, `manager.sh`, `bootcode/`, `soc_config.inc` — and **zero `src/` files**, so it is
not merged here.

## 2. What E-class actually is (measured, and it surprised us)

Documented as an MCU-class core, E-class is in fact a **bare core**:

- **No caches, no TCM, no MMU, no SRAM, no ROM.** The generated RTL instantiates only `FIFO2` ×15,
  `FIFOL1` ×8, `FIFO1` ×1, and one `RegFile` (a 32×32 flop array). "Cache support" is upstream issue
  #68, open since 2019 with no notes.
- **No AHB anywhere** (clean zero-hit grep over `fabrics/`, `devices/`, `e-class/src/`).
- **One** external interrupt input. CLINT and PLIC live outside the core.
- Two AXI4-Lite master ports: `master_i` (fetch) and `master_d` (data).
- `resetpc` is a 32-bit **runtime input port** — the boot vector is strappable at SoC level.
- **No FPU, no supervisor mode, no branch predictor.** The Makefile ISA parser emits only
  RV32/RV64/M/A/C; the `spfpu`/`supervisor`/`bpu` ifdefs are unreachable. **Upstream documentation
  claiming I/M/A/F/D/C is wrong for this configuration.**

## 3. How the Verilog in `rtl/generated/` was produced

BSV → Verilog via the **Bluespec Compiler (bsc) 2026.01**, build `9bd39e6f3`.

The recipe is `scripts/gen.sh`; the configuration is `config/eclass_asic32.inc`. We call `bsc`
directly rather than using upstream's Makefile, because the default build path silently emits Xilinx
primitives (`MUL=fpga` pulls in a `mult_gen_0` BVI import). Only the `synth32.inc` template family
sets `MUL=asic`/`SYNTH=ASIC`, and that path has not run in upstream CI since 2019.

**Configuration actually used** (`config/eclass_asic32.inc`):

```
ISA = RV32IMAC     MUL = asic       SYNTH = ASIC     COREFABRIC = AXI4Lite
SYNTHTOP = mkeclass_axi4lite        PADDR = 32       RESETPC = 4096
PMP = enable       PMPSIZE = 4      TRIGGERS = enable    TRIGGER_NUM = 2
COUNTERS = 4       USER = enable    USERTRAPS = enable
DEBUG = disable    <-- see below
MULSTAGES = 4      DIVSTAGES = 32   CAUSESIZE = 6    DTVEC_BASE = 0   VERBOSITY = 0
```

`MULSTAGES` note: on ASIC the unroll rule hardcodes `rg_count[1] != 4`, so **MULSTAGES 4 and 8 are
identical hardware**. Only 0 (combinational) vs non-zero changes structure.

**`DEBUG = disable` is a deliberate, measured decision.** With `DEBUG=enable`, `EBREAK` reports
`mcause=2` (illegal instruction) instead of `mcause=3` (breakpoint) — non-compliant. A debug-off
rebuild of identical source removed the mismatch. We therefore characterise and sign off the
**compliant** configuration. Restoring JTAG debug is future work and inherits that defect.

Reproducibility is enforced: `rtl/generated/MANIFEST.sha256` is a byte-reproducibility manifest of the
generated Verilog, and the port list is frozen in `rtl/generated/golden_ports.txt`
(**57 ports / 421 bits**).

## 4. Modifications we made — the complete list

### 4.1 To the vendored/generated RTL: **NONE**

The generated Verilog is **byte-identical** to what `scripts/gen.sh` produces and is verified by
`MANIFEST.sha256`. We did not patch the core. Two known defects were deliberately left unpatched and
are documented instead (`DISCLAIMERS.md` §3): the `EBREAK`/`C.EBREAK` `mtval` off-by-one, and PMP.

### 4.2 Added: a reset synchronizer and a top-level wrapper

Two new files, in `rtl/wrapper/`:

| file | purpose |
|---|---|
| `eclass_reset_sync.sv` | 3-stage async-assert / sync-deassert reset synchronizer |
| `eclass_top.sv` | **generated** structural wrapper: `mkeclass_axi4lite` + the synchronizer |

**Why this was necessary, with numbers.** `mkeclass_axi4lite` is bsc output, and bsc expects the
*parent* to supply a synchronized reset — it does not synchronize `RST_N` itself. `RST_N` was a raw
top-level port feeding **1,450 async pins** (1384 `dffrnq_1` reset pins + 66 `dffsnq_1` set pins).
The signoff SDC carried a blanket `set_false_path -from [get_ports RST_N]`, which disables recovery
*and* removal entirely — so "no violators" was not evidence of anything.

With that false path lifted, 3-corner STA measured **41 removal endpoints below zero, worst
−0.622 ns**: the reset tree (0.684 ns) delivered deassertion ~3.5 ns *before* the clock (4.223 ns
insertion delay) arrived. Those flops could go metastable on reset release, and **no input-delay
assumption can fix it** — an asynchronous release is unconstrained by definition.

After the fix, `RST_N` drives **only the 3 synchronizer flops**; every other async pin sees
`rst_n_sync`, which is launched by a flop on `CLK`. Launch and capture then share the clock insertion
delay, and common-path cancellation removes the imbalance. **Measured after: removal 0, recovery 0,
of 1,450 timed async pins**, with the false path scoped to exactly 3 pins.

`eclass_top.sv` is *generated* by `scripts/gen_wrapper.py` from the core's own Verilog rather than
hand-written: the core has 57 ports / 421 bits, and one swapped bus direction would present as a
fetch hang, indistinguishable from a broken core. Port declarations are copied verbatim (including
exact `[msb:lsb]` text) so a reversed range cannot be introduced.

### 4.3 Changed: the SDC reset constraint

```tcl
# before — BLANKET: disables recovery AND removal on all 1,450 async pins
set_false_path -from [get_ports RST_N]

# after — SCOPED to the 3 synchronizer flops; everything else is a REAL, TIMED check
set rst_sync_pins [get_pins -of_objects [get_nets RST_N] -filter "direction == input"]
if { [llength $rst_sync_pins] != 3 } { ... exit 1 }     # abort, never warn
set_false_path -from [get_ports RST_N] -to $rst_sync_pins
```

Pins are matched **structurally** (from the `RST_N` net) rather than by instance-name wildcard,
because ORFS flattens hierarchy and the post-synthesis names are unpredictable — they turn out to be
`u_rst_sync/eclass_rstsync_q[0]$_DFF_PN0_`. A name pattern would have matched *nothing*, applied a
false path to nothing, and reported a false clean.

### 4.4 Changed: two ORFS **platform** defaults (not design settings)

An independent GlobalFoundries KLayout deck found **154,574 DRC violations** on a GDS where ORFS's own
route-DRC reported **0**. Both causes were stock ORFS gf180 *platform* defaults:

| fix | stock | ours | violations cleared |
|---|---|---|---|
| PDN via pitch | `-split_cuts {Metal3 0.128}` — a pitch **half** the 0.26 µm cut, so cuts overlap and merge into illegal bars | `-split_cuts {Metal3 0.84}` | 103,360 (via2+via3) |
| tap cell distance | `tapcell -distance 100` → worst COMP-to-tap ≈50 µm vs a **15 µm** rule (5 V MV cells) | `tapcell -distance 25` | 51,214 (comp) |

Both are overridden in `config/pv_fix/`, not by patching the shared platform (which would silently
un-apply on any image rebuild). **An intermediate value of 0.62 cleared the via rules and silently
broke `M3.2a` metal3 spacing with 51,680 new violations** — 0.84 clears both.

### 4.5 Constraint tuning (measured, not guessed)

- `set_clock_uncertainty` is **split**: `-setup 0.5` / `-hold 0.1`. A single 0.5 ns value applied to
  both demanded 0.5 ns of hold margin on every path; the resulting "hold violation" of −0.075 ns was
  a constraint bug, not silicon.
- `set_max_transition 1.6` — tuned in three measured steps (no constraint → 1303 violators, worst
  9.12 ns; 2.0 → 28 pins over the 2.80 ns library limit; 1.6 → clean). **`set_max_fanout` is NOT the
  binding lever on gf180**: a fanout-97 net drew zero fanout violations while its slew was the real
  problem.
- CTS defaults are pinned explicitly (`CTS_CLUSTER_SIZE`, `CTS_CLUSTER_DIAMETER`, `CTS_BUF_DISTANCE`)
  because ORFS stage TCLs only pass an argument when the environment variable exists — an unset knob
  falls through to internal behaviour, not the documented default.

## 5. The path from RTL to signoff

| stage | what was done |
|---|---|
| **M0** | Pin the toolchain; generate Verilog from BSV; freeze port list + byte manifest |
| **M1** | Functional verification: RISCOF compliance against Spike (pinned by commit), plus a Verilator smoke test |
| **M2** | Characterisation: synthesis sweeps, track/‌cell-tier selection (9-track chosen: 20.7% larger than 7t but 7t measured 1.35–1.38× slower at realistic loads) |
| **M3** | Full ORFS flow to GDS, 3-corner SPEF signoff at 25.0 MHz |
| **PV** | Independent GlobalFoundries KLayout deck → the 154,574-violation finding → §4.4 fixes → re-verified |
| **M3.5** | Reset synchronizer (§4.2), re-harden, removal/recovery converted from *disabled* to *measured zero* |

Every stage's scripts are in `scripts/`; `REPRODUCE.md` has the commands.

## 6. Licensing of the result

The generated Verilog is a **derivative of BSD-3-Clause BSV** (IIT Madras). It carries no injected
license header because upstream's public Makefile falls back to a plain filter. We therefore ship the
upstream BSD-3 license text (`LICENSES/`) and this provenance document, and license **our own**
contributions under Apache-2.0 (see `LICENSE` and `NOTICE`).

**This is our reading of the license chain, not legal advice.** Anyone producing a fabricated
commercial derivative should obtain their own counsel and, ideally, confirm with the SHAKTI team.
