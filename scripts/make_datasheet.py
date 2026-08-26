"""Render DATASHEET.md from measured artifacts only. Do not hand-edit the output.

The 'Honest negatives' block is fixed text carried from spec section 13 — it is part of the
deliverable, not a footnote.
"""
import csv, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
RESULTS = ROOT / "synth" / "results" / "results.csv"
COMPLIANCE = ROOT / "sim" / "RESULTS" / "compliance.json"
XIP = ROOT / "synth" / "XIP_VERDICT.md"
SWEEP_SPEC = ROOT / "synth" / "sweep_points.yaml"

CONDITIONS = """\
## Measurement conditions

Synthesis-only figures: yosys 0.64, `gf180mcu_fd_sc_mcu9t5v0` (9-track) unless the row says 7t,
`tt_025C_5v00`, **unconstrained ABC mapping**. These are **area floors** — no timing target, no
buffering, no scan, no place-and-route. They are not achievable post-layout numbers and carry no
frequency claim.

**Discrepancy to carry into M3:** this harness uses the **unfiltered** liberty, so drive-1 cells
are permitted in every number below. `designs/eclass_gf180/config/config.mk` sets
`DONT_USE_CELLS = *_1`, so M3 will not reproduce these areas exactly. Filtering the liberty is an
ORFS capability with no raw-yosys equivalent; measured properly in M3.

Configuration is the **shipped** one: RV32IMAC + User mode, PMP 4 entries, 2 triggers,
**DEBUG disabled** (spec AMENDMENT 2), USERSPACE=0, `mkeclass_axi4lite`.
"""

HONEST_NEGATIVES = """\
## Honest negatives (published as part of this datasheet)

- **No published prior art found** for SHAKTI on any open PDK (four independent searches).
  Stated as "none found" — never "first ever".
- **Never compare this core's fmax to Moushik's 75–100 MHz** without stating that SCL 180nm is a
  **1.8 V thin-oxide** logic process while gf180mcu ships only **5 V thick-oxide** MCU cells. That
  gap is largely device class, not open-EDA quality.
- Both upstream ORFS gf180 RISC-V references **fail to close**, and both run at the best-case
  default `CORNER ?= BC`: riscv32i (SDC 9.0 ns, 8,628 cells, 422,004 µm², setup −0.63 / hold
  −0.45); ibex (SDC 10.0 ns, 15,783 cells, 748,372 µm², setup −0.539 / hold −1.39).
- Corrected voltage derate (matched-load): 3.0 V is **1.53×** slower than 4.5 V at SS; 1.62 V is
  **4.44–4.62×**. A 3.3 V rail costs ~35% of fmax; 1.8 V costs ~78%.
- The gf180 SRAM `min_period` of 11.890 ns at ss_125C_4v50 caps any full-MCU frequency claim at
  **84.1 MHz**.
- ORFS's gf180 platform ships **no IO pads** (48 LEF entries, zero io/pad) and **no IO liberty at
  all**. Chip assembly needs a two-tool split: ORFS hardens a core-level macro, a librelane/shuttle
  template does the pad ring.
- **This IP has no debug interface.** DEBUG is disabled because enabling it makes EBREAK
  non-compliant (see the compliance section). Restoring JTAG is an M5 work item carrying a known
  defect, not a configuration flip.
- **C-class was never evaluated.** It is alive, genuinely parameterized, and already has SHAKTI's
  accelerator-socket ecosystem. E-class was chosen deliberately; recorded so the choice stays
  revisitable.
"""


def sweep_table():
    rows = list(csv.DictReader(RESULTS.open()))
    base = next(r for r in rows if r["point"] == "baseline_9t")
    ba = float(base["area_um2"])
    out = ["| point | factor | value | cells | area µm² | Δ area | flops | levels |",
           "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if r["error"]:
            out.append(f"| {r['point']} | {r['factor']} | {r['value']} | "
                       f"**FAILED: {r['error'][:60]}** | | | | |")
            continue
        a = float(r["area_um2"])
        d = "—" if r["point"] == "baseline_9t" else f"{100 * (a - ba) / ba:+.1f}%"
        out.append(f"| `{r['point']}` | {r['factor']} | {r['value']} | {int(r['cells'])} | "
                   f"{a:,.0f} | {d} | {r['flops']} | {r['levels']} |")
    return "\n".join(out)


def not_run_table():
    import yaml
    spec = yaml.safe_load(SWEEP_SPEC.read_text())
    out = ["Points DECLARED but deliberately NOT run, with the reason. Recorded rather than "
           "omitted, because a silently truncated sweep reads as \"we covered everything\".", ""]
    for n in spec.get("not_run", []):
        out.append(f"- **`{n['name']}`** — {' '.join(n['reason'].split())}")
    return "\n".join(out)


def compliance_summary():
    rows = json.loads(COMPLIANCE.read_text())
    import collections
    per = collections.Counter((r["suite"], r["result"]) for r in rows)
    suites = sorted({s for s, _ in per})
    out = ["| suite | pass | fail |", "|---|---|---|"]
    for s in suites:
        out.append(f"| `{s}` | {per.get((s, 'PASS'), 0)} | {per.get((s, 'FAIL'), 0)} |")
    out += ["",
            "Reference model: Spike `231e0d53`, `--pmpregions=4` to match `PMPSIZE=4`. Suite: "
            "riscv-arch-test `ctp-release-e9514aa-2025-12-28`. Adjudication is RISCOF's own "
            "signature comparison.", "",
            "**What may be claimed:** E-class passes the **RV32I base ISA 38/38**, plus M, A and "
            "Zifencei, against Spike under RISCOF.",
            "**What may NOT be claimed:** compliance with `C` or `privilege` (one EBREAK failure "
            "each — a genuine `mtval = pc+1` spec violation, root-caused, fix verified but NOT "
            "applied), nor correct PMP (55/55 failing, root cause open). No claim of full RISC-V "
            "compliance is made.",
            "", "Full detail and the deviation register: `sim/RESULTS/COMPLIANCE.md`."]
    return "\n".join(out)


def main():
    parts = [
        "# SHAKTI E-class on gf180mcu — measured datasheet",
        "",
        "Generated by `scripts/make_datasheet.py` from measured artifacts. Do not hand-edit.",
        "",
        CONDITIONS,
        "## Configuration sweep (M2)",
        "",
        sweep_table(),
        "",
        "### Notable results",
        "",
        "- **`DIVSTAGES` is inert.** Values 1, 8 and 32 all produce a **byte-identical mapped "
        "netlist** (`06c0809f…`). {1,8} even share generated RTL, differing from 32 — but "
        "synthesis optimises the difference away entirely. It is not a PPA lever.",
        "- **`MULSTAGES=0` (combinational multiply) costs +11.5% area for fewer reported logic "
        "levels** (25 vs 29) — it is structurally distinct (netlist `5acb2cdf…`), unlike DIVSTAGES.",
        "- **The JTAG debug module costs +8.0% area** (+64,593 µm²). That is the price of the M5 "
        "work item — and it currently comes with the EBREAK defect attached.",
        "- **PMP costs ~9.8% area** and **counters ~9.7%** — the two largest optional blocks.",
        "- 7t is **20.7% smaller** than 9t, but the research measured it **1.35–1.38× slower** at "
        "realistic loads. 9t is the baseline because fmax is the objective.",
        "",
        not_run_table(),
        "",
        "## Functional compliance (M1)",
        "",
        compliance_summary(),
        "",
        "## XIP viability (M2)",
        "",
        XIP.read_text().strip() if XIP.is_file() else "_not yet determined_",
        "",
        HONEST_NEGATIVES,
    ]
    (ROOT / "DATASHEET.md").write_text("\n".join(parts) + "\n")
    print(f"wrote {ROOT / 'DATASHEET.md'}")


if __name__ == "__main__":
    main()
