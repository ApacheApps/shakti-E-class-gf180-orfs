# Reproducing this work

Everything here was built with open tools. The only thing not redistributed is the PDK, which you
fetch from upstream.

## Prerequisites

| tool | version used | notes |
|---|---|---|
| OpenROAD-flow-scripts (ORFS) | OpenROAD 26Q2 | container image built natively for your architecture |
| Bluespec Compiler (bsc) | **2026.01**, build `9bd39e6f3` | only needed to regenerate RTL from BSV |
| KLayout | 0.30.7 | physical verification |
| Netgen | 1.5.133 | LVS comparison |
| Verilator | from the ORFS sim image | testbenches |
| GF180MCU PDK | open_pdks build `c6d73a35f524070e85faff4a6a9eef49553ebc2b`, **variant C** | `volare enable --pdk gf180mcu c6d73a35…` |

**PDK variant matters.** Variant C = metal_top 9K / mim_option B / 5LM, which is what this design's
stack (5LM_1TM, KVALUE 9K) requires. Running another variant checks the wrong metal rules and
produces a meaningless clean or dirty result.

**Architecture note.** Build the ORFS image natively for your machine. On Apple Silicon an amd64
image under emulation SIGILLs during CTS.

## Path convention

The ORFS configs use `/work/...` paths. `/work` is the **container mount point** for the repository
root — it is a fixed convention, identical for everyone, and reveals nothing about the build host.
Mount this repository at `/work` when invoking the flow:

```bash
docker run --rm -v "$PWD:/work" -w /OpenROAD-flow-scripts/flow <orfs-image> bash -lc '
  source /OpenROAD-flow-scripts/env.sh
  make DESIGN_CONFIG=/work/config/config_mc_rstsync.mk WORK_HOME=/work
'
```

## 1. Regenerate the RTL from BSV (optional)

`rtl/generated/` is already in this repository, byte-verified by `MANIFEST.sha256`. To rebuild it:

```bash
# vendors the seven upstream repos at the pinned SHAs in PROVENANCE.md section 1
./scripts/vendor.sh
./scripts/gen.sh                       # bsc 2026.01, config/eclass_asic32.inc
shasum -a 256 -c rtl/generated/MANIFEST.sha256
```

The wrapper is generated, not hand-written:

```bash
python3 scripts/gen_wrapper.py         # emits rtl/wrapper/eclass_top.sv   (57 ports)
```

## 2. Harden

```bash
# unfilled build (LVS database)
make DESIGN_CONFIG=/work/config/config_mc_rstsync.mk  WORK_HOME=/work
# stock-fill build (physical-verification / tapeout candidate)
make DESIGN_CONFIG=/work/config/config_mc_rstsyncf.mk WORK_HOME=/work
```

Runtime is roughly 15 minutes for the flow on 8 cores.

## 3. Multi-corner sign-off STA

```bash
openroad -exit scripts/signoff/mc_signoff.tcl        # SIGNOFF_NICK=<nickname>
openroad -exit scripts/signoff/signoff_audit5.tcl    # removal/recovery enumeration
```

`signoff_audit5.tcl` is the one that matters for this release: it asserts the emitted false path
covers **exactly 3 pins** and aborts otherwise, then enumerates every recovery and removal check
across three corners rather than trusting a report's line count.

## 4. Physical verification

```bash
TOPCELL=eclass_top RUN_MODE=flat ./scripts/signoff/run_drc.sh <gds> <outdir>                 # 53 tables
TOPCELL=eclass_top RUN_MODE=flat ./scripts/signoff/run_drc.sh <gds> <outdir> --table=geom     # off-grid
TOPCELL=eclass_top RUN_MODE=flat ./scripts/signoff/run_drc.sh <gds> <outdir> --antenna_only   # antenna
TOPCELL=eclass_top RUN_MODE=flat ./scripts/signoff/run_drc.sh <gds> <outdir> --density_only   # density
```

**Use `RUN_MODE=flat`.** The deck's `--split_deep` mitigation is a **no-op** in `deep` mode
(`run_drc.py:344`), and the deck ships `*_split.drc` variants precisely so that flat mode can pin its
few pathological rules to deep. Deep-everywhere ran 14–20 h without completing; flat + split_deep
completes in ~34 minutes.

**`TOPCELL=eclass_top` is mandatory.** `mkeclass_axi4lite` still exists as a subcell inside the GDS,
so the wrong value silently checks the core subcell and reports a clean that excludes the wrapper.

## 5. LVS

LVS runs on the **unfilled** build. The gf180 LVS deck defines `metal1 = metal1_drawn + metal1_dummy`
and derives connectivity from it, so metal fill would extract as tens of thousands of phantom
floating nets. This matches how the reference open-silicon flows sequence it: LVS before fill.

```bash
python3 scripts/signoff/v2spice.py <netlist.v> <cell.spice> <out.spice> eclass_top
openroad -exit scripts/signoff/emit_phys_cells.tcl   # physical-only cell connectivity from the ODB
python3 scripts/signoff/add_phys_cells.py <out.spice> <physcells> <cell.spice>
# KLayout flat extraction -> netgen compare (see reports/LVS_CELL_POLICY.md for the cell policy)
```

The cell policy is not incidental — read `reports/LVS_CELL_POLICY.md`. In short: device-free
physical-only cells (`fill_*`, `filltie`, `endcap`) are ignored symmetrically on both netlists, while
`__antenna` is **included**, because it contains two real diodes per instance sitting on real signal
nets and excluding it would hide 54 devices.

## 6. Functional tests

```bash
./sim/run_smoke.sh                      # core
DUT_TOP=eclass_top ./sim/run_smoke.sh   # through the wrapper (+3 cycles = the 3 sync stages)
./sim/run_reset_sync.sh                 # 64 randomized reset-release phases
./sim/run_riscof.sh                     # RISCOF compliance vs Spike
```

## 7. Before publishing anything derived from this

```bash
./scripts/release/prerelease_scan.sh    # host paths + credentials/PII gate
```
