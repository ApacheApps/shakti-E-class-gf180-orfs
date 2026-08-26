# E-class on GF180MCU — an open, multi-corner signed-off RISC-V core

**SHAKTI E-class (RV32IMAC) hardened on the open GlobalFoundries GF180MCU PDK with OpenROAD/ORFS,
closed at 25.0 MHz across three corners, verified against the real GlobalFoundries KLayout sign-off
deck.**

> ### This is one more milestone in a series of AI-assisted physical-design work
>
> The physical design in this repository — floorplanning, constraint development, debugging, the
> sign-off campaign and the analysis that produced every number below — was carried out with
> **Claude (Anthropic)** as an active engineering participant, not as an autocomplete.
>
> This is the latest in an ongoing series of such projects. The previous one is
> [**pqc-asap7-orfs**](https://github.com/ApacheApps/pqc-asap7-orfs) — post-quantum crypto
> (ML-DSA-87 + ML-KEM-1024) hardened on ASAP7.
>
> We state this plainly and up front because we think it matters both ways: it is the interesting
> part of the work, **and** it is a caveat a reader is entitled to weigh. Everything here is reported
> with its measurement and its limitations attached, including the results that came out badly and
> the mistakes made along the way (see [`DISCLAIMERS.md`](DISCLAIMERS.md)).

---

## The processor: SHAKTI E-class

**E-class** is the embedded-class core of the [**SHAKTI**](https://shakti.org.in/) processor family
from **IIT Madras** — an open RISC-V program developed entirely in **Bluespec SystemVerilog (BSV)**.

> *"This is the embedded class processor, built around a 3-stage in-order core. It is aimed at
> low-power and low compute applications and is capable of running basic RTOSs like FreeRTOS and
> Zephyr. Typical market segments include: smart-cards, IoT sensors, motor-controls and robotic
> platforms."* — [upstream README](https://gitlab.com/shaktiproject/cores/e-class)

### Source

| what | where |
|---|---|
| **E-class core (upstream)** | **https://gitlab.com/shaktiproject/cores/e-class** |
| SHAKTI project | https://shakti.org.in/ · https://gitlab.com/shaktiproject |
| fabrics (AXI4-Lite interconnect) | https://gitlab.com/shaktiproject/uncore/fabrics |
| common_bsv | https://gitlab.com/shaktiproject/common_bsv |
| common_verilog | https://gitlab.com/shaktiproject/common_verilog |
| devices | https://gitlab.com/shaktiproject/uncore/devices |
| verification environment | https://gitlab.com/shaktiproject/verification_environment/verification |
| benchmarks | https://gitlab.com/shaktiproject/cores/benchmarks |

Exact pinned commit SHAs, licenses and dates for all seven are in
[`PROVENANCE.md` §1](PROVENANCE.md). The BSV is **BSD-3-Clause** (IIT Madras, 2018); the Verilog in
`rtl/generated/` is generated from it and is therefore a derivative work — see
[`NOTICE`](NOTICE).

### Configuration hardened here

| | |
|---|---|
| ISA | **RV32IMAC** (32-bit, integer + multiply/divide + atomics + compressed) |
| Pipeline | **3-stage, in-order** — fetch/decode · execute · memory/writeback |
| Privilege | Machine + **User** mode, with user-level traps |
| Memory protection | **PMP**, 4 regions |
| Debug triggers | 2 |
| Performance counters | 4 |
| Bus | **two AXI4-Lite masters** — `master_i` (fetch) and `master_d` (data), 32-bit |
| Multiplier / divider | sequential (`MUL=asic`), 32 divide stages |
| Boot vector | `resetpc`, a **32-bit runtime input port** — strappable at SoC level |
| Reset | `RST_N`, asynchronous, **any phase** (synchronized internally — see below) |
| Top module | `eclass_top` (our wrapper) around `mkeclass_axi4lite` |
| Ports | 57 ports / 421 bits |

### What E-class is *not* — measured, and it surprised us

Upstream documentation is optimistic in places. Verified against the generated RTL:

- **No caches, no TCM, no MMU, no on-chip SRAM or ROM.** The generated RTL instantiates only
  `FIFO2` ×15, `FIFOL1` ×8, `FIFO1` ×1 and one `RegFile` (a 32×32 flop array). Upstream cache
  support is issue #68, open since 2019. **A usable SoC must supply memory externally.**
- **No AHB anywhere** — a clean zero-hit grep across `fabrics/`, `devices/` and `e-class/src/`.
- **One** external interrupt input. CLINT and PLIC live outside the core.
- **No FPU, no supervisor mode, no branch predictor.** The Makefile ISA parser emits only
  RV32/RV64/M/A/C, so the `spfpu`/`supervisor`/`bpu` ifdefs are unreachable. **Upstream text claiming
  I/M/A/F/D/C does not apply to this configuration.**
- **Debug is disabled here**, deliberately: `DEBUG=enable` makes `EBREAK` report `mcause=2` instead
  of `3`. We sign off the *compliant* configuration. See [`DISCLAIMERS.md`](DISCLAIMERS.md).

The upstream core is **frozen at 2019-12-17** (tag `1.10.2`); the later `89-fix-compilation` branch
touches only build infrastructure, no `src/` files.


## Results

| metric | value | conditions |
|---|---|---|
| **Closed frequency** | **25.0 MHz** (40 ns) | commit target |
| fmax (`period_min` 37.76 ns) | 26.48 MHz | same conditions |
| Setup WNS / violators | **+2.24 ns / 0** | 3-corner SPEF STA |
| Hold WNS / violators | **+0.209 ns / 0** | 3-corner SPEF STA |
| **Recovery / removal violators** | **0 / 0** of 1,450 timed async pins | see below — this one has a story |
| Foundry DRC (GF KLayout deck) | **0 violations across 53 tables**, run to completion | variant C, 5LM_1TM |
| Off-grid (95 `*_OFFGRID` rules) | **0** | |
| Antenna (foundry deck) | **0** | cross-checked on two machines |
| Route DRC · PSM · DRV vs 2.80 ns library limit | 0 · clean · 0 | |
| **LVS** | **`Circuits match uniquely`** — 28,838 devices / 30,322 nets both sides, 0 unmatched | magic + netgen, unfilled build |
| Area | 1,519,823 µm² @ 53% utilisation | die 1703.2 × 1703.2 µm |
| Power | 0.255 W | default activity, **no VCD/SAIF** |

**Conditions travel with the number:** `ss_125C_4v50` (worst of ss/tt/ff), 5.0 V,
`gf180mcu_fd_sc_mcu9t5v0` 9-track, 5LM_1TM metal stack, post-route SPEF, propagated clocks.

### What is NOT met

**Minimum metal density on Metal1/Metal2/Metal3 is not satisfied at block level** (28.6% / 17.2% / 17.8%
against a >30% rule; see RESULTS.md for a mode-dependence caveat). Metal4, Metal5 and MetalTop close with fill. This is a
**chip-integration obligation, not a defect**: the rule is written "over the entire die", and the
reference open-silicon flow generates fill at chip assembly rather than in the block. Attempting to
close it inside the block produced geometry that violates the foundry's dummy-metal rules. The full
reasoning is in [`DISCLAIMERS.md`](DISCLAIMERS.md).

Other open items — EBREAK `mtval` deviation, JTAG disabled, weak formal equivalence, PMP — are
listed there too. **Nothing is hidden in this repository.**

## The reset finding — why this milestone exists

The previous sign-off reported "no recovery/removal violators". That statement was **vacuous**: the
SDC carried a blanket `set_false_path -from [get_ports RST_N]`, which disables those checks entirely
on all 1,450 asynchronous pins.

With the false path lifted, three-corner STA measured **41 removal endpoints below zero, worst
−0.622 ns**. Root cause was architectural and in the IP: bsc output expects the *parent* to
synchronize reset, and no parent existed, so reset deassertion arrived ~3.5 ns before the clock edge.

The fix adds a 3-stage async-assert/sync-deassert synchronizer, so the raw port drives **3 flops
instead of 1,450**, and the false path shrinks to exactly those 3 pins. Everything else becomes a
real, timed check — **measured: removal 0, recovery 0**.

This is **containment plus a timing measurement, not a metastability proof.** No MTBF figure is
quoted anywhere in this repository, because no measured metastability window (τ, T0) is published for
these cells and inventing one would be fabrication.

## Repository contents

```
rtl/generated/     Verilog generated from upstream BSV (byte-reproducible, MANIFEST.sha256)
rtl/wrapper/       our additions: eclass_top.sv + eclass_reset_sync.sv
rtl/*_netlist.v    the post-route sign-off netlist
config/            ORFS configs, SDC constraints, the two platform DRC fixes
scripts/           RTL generation, sign-off STA, DRC/LVS, audit scripts
sim/               Verilator testbenches (smoke, RISCOF arch test, reset synchronizer)
reports/           sign-off reports, PV summaries, cell policy, closure dossier
docs/              upstream provenance, LVS flow
collateral/        SIGN-OFF COLLATERAL, in-repo:
  gds/               filled (tapeout) + unfilled (LVS) GDS, gzipped
  def/  spef/        routed DEF and post-route parasitics, gzipped
  views/             abstract LEF + per-corner Liberty (ss/tt/ff) for hard-macro integration
```

**Everything is in the repository** — a single `git clone` gets the RTL, the configs, the scripts and
the sign-off collateral. Large artifacts are gzipped (217 MB raw → ~34 MB), and `collateral/SHA256SUMS`
covers them. See [`collateral/README.md`](collateral/README.md) for which GDS to use when.

## Start here

- [`PROVENANCE.md`](PROVENANCE.md) — where the RTL came from and **every modification we made**
- [`DISCLAIMERS.md`](DISCLAIMERS.md) — disclaimers, known limitations, open issues
- [`RESULTS.md`](RESULTS.md) — full measured results
- [`REPRODUCE.md`](REPRODUCE.md) — how to rebuild this

## License

Our contributions: **Apache-2.0** ([`LICENSE`](LICENSE)). The generated Verilog derives from
BSD-3-Clause BSV from IIT Madras; upstream license texts are in [`LICENSES/`](LICENSES/) and
attribution is in [`NOTICE`](NOTICE). See [`PROVENANCE.md`](PROVENANCE.md) §6 — that section is our
reading of the license chain, **not legal advice**.

## Acknowledgements

[SHAKTI](https://shakti.org.in/) / IIT Madras — [**E-class core**](https://gitlab.com/shaktiproject/cores/e-class) · [OpenROAD & ORFS](https://theopenroadproject.org/) ·
[Yosys](https://github.com/YosysHQ/yosys) · [OpenSTA](https://github.com/parallaxsw/OpenSTA) ·
[KLayout](https://www.klayout.de/) · [GlobalFoundries GF180MCU PDK](https://gf180mcu-pdk.readthedocs.io/) ·
[Bluespec Compiler](https://github.com/B-Lang-org/bsc) · [RISCOF](https://github.com/riscv-software-src/riscof) ·
[Spike](https://github.com/riscv-software-src/riscv-isa-sim)
