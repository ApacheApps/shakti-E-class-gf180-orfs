"""Emit compliance rows from a RISCOF run log.

SOURCE CHOICE (deliberate): we parse RISCOF's own stdout verdict lines

    /path/to/rv32i_m/I/src/add-01.S : <commit> : Passed|Failed

and NOT report.html. The HTML lists each test more than once, in more than one markup shape, so a
regex over it double-counted (75 rows for 38 tests), dropped half into suite "unknown", and then
produced spurious "conflicting verdict" errors when a lazy match spanned into a neighbouring row.
The log line is one per test, carries the full path (hence the suite), and is RISCOF's own verdict
-- the deterministic referee this milestone depends on. Verified: 38 lines for 38 tests, no dupes.
"""
import json, pathlib, re, sys

VERDICT = re.compile(r"(?P<path>/\S+\.S)\s*:\s*\S+\s*:\s*(?P<verdict>Passed|Failed)")
SUITE = re.compile(r"rv\d+[a-z]*_m/[A-Za-z0-9_]+")


def parse(text):
    seen = {}
    for m in VERDICT.finditer(text):
        path = m.group("path")
        sm = SUITE.search(path)
        suite = sm.group(0) if sm else "unknown"
        name = pathlib.PurePosixPath(path).name
        key = (suite, name)
        result = "PASS" if m.group("verdict") == "Passed" else "FAIL"
        if key in seen and seen[key]["result"] != result:
            sys.exit(f"parse_riscof: conflicting verdicts for {suite}/{name}")
        seen[key] = {"suite": suite, "test": name, "result": result}
    return sorted(seen.values(), key=lambda r: (r["suite"], r["test"]))


def main(logfile):
    p = pathlib.Path(logfile)
    if not p.is_file():
        sys.exit(f"parse_riscof: no log at {p}")
    rows = parse(p.read_text(errors="replace"))
    if not rows:
        sys.exit(f"parse_riscof: no verdict lines in {p} — did the run abort before comparison?")
    unknown = [r["test"] for r in rows if r["suite"] == "unknown"]
    if unknown:
        sys.exit(f"parse_riscof: unresolved suite for {len(unknown)} tests (e.g. {unknown[:3]}) "
                 "— the per-suite gates would silently skip them")
    json.dump(rows, sys.stdout, indent=2)


if __name__ == "__main__":
    main(sys.argv[1])
