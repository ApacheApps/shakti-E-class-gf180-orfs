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

Other open items — EBREAK `mtval` deviation, JTAG disabled, weak formal equivalence, PMP, LVS
status — are listed there too. **Nothing is hidden in this repository.**

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
docs/              upstream provenance
```

Large binaries (GDS, SPEF, DEF) are attached as **release assets**, not committed.

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

[SHAKTI](https://shakti.org.in/) / IIT Madras (E-class core) · [OpenROAD & ORFS](https://theopenroadproject.org/) ·
[Yosys](https://github.com/YosysHQ/yosys) · [OpenSTA](https://github.com/parallaxsw/OpenSTA) ·
[KLayout](https://www.klayout.de/) · [GlobalFoundries GF180MCU PDK](https://gf180mcu-pdk.readthedocs.io/) ·
[Bluespec Compiler](https://github.com/B-Lang-org/bsc) · [RISCOF](https://github.com/riscv-software-src/riscof) ·
[Spike](https://github.com/riscv-software-src/riscv-isa-sim)
