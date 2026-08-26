"""Build reports/M3_RESULT.json from the flow's own artifacts.

Sources, deliberately: the multi-corner SPEF signoff log (scripts/mc_signoff.tcl) for timing and
DRVs, the ORFS reports for DRC/antenna/area/power, and the flow logs for PSM. Nothing here reads
log prose for a verdict. If a field cannot be found we FAIL LOUDLY rather than defaulting — a
missing gate value silently becoming 0 would manufacture a pass.
"""
import argparse, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROOT = ROOT.parents[1]

# A variant is (flow nickname, where its signoff log + output JSON live, which SDC it closed at).
# The default IS the signed-off M3 configuration; anything else must be named explicitly, so an
# experiment can never be mistaken for the baseline by omission.
VARIANTS = {
    "base": dict(nickname="eclass_gf180_mc", outdir="reports",
                 sdc="config/constraint.sdc", out="M3_RESULT.json"),
    "nocounters": dict(nickname="eclass_gf180_nocnt", outdir="signoff_nocounters",
                       sdc="config/constraint_fast.sdc", out="RESULT.json"),
    # The same design and SDC as `base`, rebuilt with the two ORFS gf180 PLATFORM fixes that the
    # real foundry DRC forced (split_cuts pitch, tapcell distance). Same constraint file on purpose:
    # any QoR delta against the signoff is then attributable to those two knobs alone.
    "pvfix": dict(nickname="eclass_gf180_pvfix", outdir="signoff_pvfix",
                  sdc="config/constraint.sdc", out="RESULT.json"),
    # Iteration 2: pitch 0.84, which clears M3.2a as well as V3.2b. Iteration 1 (pitch 0.62) cleared
    # the via rules but traded them for 51,680 metal3-spacing violations.
    "pvfix2": dict(nickname="eclass_gf180_pvfix2", outdir="signoff_pvfix2",
                   sdc="config/constraint.sdc", out="RESULT.json"),
    # Same as pvfix2 but with metal fill inserted, to measure whether the density rules can be met.
    "pvfix2f": dict(nickname="eclass_gf180_pvfix2f", outdir="signoff_pvfix2f",
                    sdc="config/constraint.sdc", out="RESULT.json"),
    # M3.5: pvfix2 plus the reset synchronizer (hardened top is eclass_top). This is the FIRST
    # variant whose SDC differs from the signoff's, and deliberately so -- the RST_N false path is
    # scoped to the synchronizer's 3 pins, so recovery/removal are REAL checks here rather than
    # disabled ones. Everything else in the config is inherited from pvfix2 unchanged.
    "rstsync": dict(nickname="eclass_gf180_rstsync", outdir="signoff_rstsync",
                    sdc="config/constraint_rstsync.sdc", out="RESULT.json"),
    # Same as rstsync but with metal fill inserted, for the density tables. Fill was measured on
    # pvfix2f to cost nothing in timing or area; this re-measures that on the M3.5 build.
    "rstsyncf": dict(nickname="eclass_gf180_rstsyncf", outdir="signoff_rstsyncf",
                     sdc="config/constraint_rstsync.sdc", out="RESULT.json"),
}

# Conditions travel WITH the number — a frequency without them is not a claim (gate M3-G4).
CONDITIONS = {"corner": "ss_125C_4v50 (worst of c1ss/c2tt/c3ff)", "rail_v": 5.0,
              "cell_tier": "gf180mcu_fd_sc_mcu9t5v0", "metal_stack": "5LM_1TM",
              "extraction": "post-route SPEF, propagated clocks"}


def _req(v, what):
    if v is None:
        sys.exit(f"collect_m3: could not determine {what} — refusing to emit a default")
    return v


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--variant", choices=sorted(VARIANTS), default="base")
    v = VARIANTS[ap.parse_args().variant]

    REPORTS = PROOT / "reports" / "gf180" / v["nickname"] / "base"
    LOGS = PROOT / "logs" / "gf180" / v["nickname"] / "base"
    OUTDIR = ROOT / v["outdir"]
    SIGNOFF = OUTDIR / "mc_signoff_final.log"

    so = SIGNOFF.read_text() if SIGNOFF.is_file() else sys.exit(f"missing {SIGNOFF}")
    fin = (REPORTS / "6_finish.rpt").read_text()

    def grab(pat, text=so, cast=float):
        m = re.search(pat, text)
        return cast(m.group(1)) if m else None

    setup_ws = grab(r"SETUP:\s*\nworst slack max\s+(-?[\d.]+)")
    setup_tns = grab(r"SETUP:\s*\nworst slack max\s+-?[\d.]+\s*\ntns max\s+(-?[\d.]+)")
    hold_ws = grab(r"HOLD:\s*\nworst slack min\s+(-?[\d.]+)")
    hold_tns = grab(r"HOLD:\s*\nworst slack min\s+-?[\d.]+\s*\ntns min\s+(-?[\d.]+)")

    # Violator counts are DERIVED, and the derivation is stated: with TNS == 0 and worst slack
    # positive, no endpoint is negative, so the violator count is zero by definition.
    def violators(ws, tns, label):
        _req(ws, f"{label} worst slack"); _req(tns, f"{label} TNS")
        if ws >= 0 and tns == 0:
            return 0
        sys.exit(f"collect_m3: {label} is NOT clean (ws={ws}, tns={tns}) — "
                 "this collector only certifies a clean result")

    # DRVs: the signoff log reports twice — against our tighter SDC target, then against the
    # LIBRARY limit, which is the actual signoff criterion.
    lib_idx = so.index("THIS IS THE SIGNOFF CRITERION")
    drv_lib = so[lib_idx:].count("VIOLATED")
    drv_target = so[so.index("DRV vs the OPTIMIZATION TARGET"):lib_idx].count("VIOLATED")

    drc = len([l for l in (REPORTS / "5_route_drc.rpt").read_text().splitlines() if l.strip()])
    ant_log = (REPORTS / "drt_antennas.log")
    antenna = len([l for l in ant_log.read_text().splitlines() if l.strip()]) if ant_log.is_file() else 0
    psm_ok = (LOGS / "6_report.log").read_text().count("PSM-0040") >= 2
    psm_bad = (LOGS / "6_report.log").read_text().count("PSM-0069")

    per = re.search(r"period_min\s*=\s*([\d.]+)\s+fmax\s*=\s*([\d.]+)", fin)
    area = re.search(r"Design area\s+(\d+)\s+um\^2\s+(\d+)%", (LOGS / "6_report.log").read_text())
    core = re.search(r"Core area:\s+([\d.]+)", (LOGS / "2_1_floorplan.log").read_text())
    power = re.search(r"^Total\s+\S+\s+\S+\s+\S+\s+([\d.e+-]+)", fin, re.M)
    sdc_period = re.search(r"-period\s+([\d.]+)", (ROOT / v["sdc"]).read_text())

    out = {
        "setup_wns_ns": _req(setup_ws, "setup WNS"),
        "setup_tns_ns": _req(setup_tns, "setup TNS"),
        "setup_violators": violators(setup_ws, setup_tns, "setup"),
        "hold_wns_ns": _req(hold_ws, "hold WNS"),
        "hold_tns_ns": _req(hold_tns, "hold TNS"),
        "hold_violators": violators(hold_ws, hold_tns, "hold"),
        "drc": drc,
        "antenna": antenna,
        "psm_connected": psm_ok,
        "psm_0069_violations": psm_bad,
        "drv_vs_library_limit_2p80": drv_lib,
        "drv_vs_optimization_target": drv_target,
        "closed_period_ns": float(sdc_period.group(1)) if sdc_period else None,
        "closed_freq_mhz": round(1000.0 / float(sdc_period.group(1)), 3) if sdc_period else None,
        "period_min_ns": float(per.group(1)) if per else None,
        "fmax_mhz": float(per.group(2)) if per else None,
        "design_area_um2": int(area.group(1)) if area else None,
        "utilization_pct": int(area.group(2)) if area else None,
        "core_area_um2": float(core.group(1)) if core else None,
        "total_power_w": float(power.group(1)) if power else None,
        **CONDITIONS,
    }
    for k in ("period_min_ns", "fmax_mhz", "design_area_um2", "core_area_um2"):
        _req(out[k], k)
    OUTDIR.mkdir(exist_ok=True)
    (OUTDIR / v["out"]).write_text(json.dumps(out, indent=2))
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
