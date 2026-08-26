#!/usr/bin/env bash
# Usage: run_riscof.sh [--suite <rv32i_m/I|rv32i_m/M|...>] [extra riscof args]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROOT="$(cd "$HERE/../../../.." && pwd)"
mkdir -p "$HERE/RESULTS"

SUITE_FILTER=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --suite) SUITE_FILTER="$2"; shift 2;;
    *) ARGS+=("$1"); shift;;
  esac
done

RUNLOG="$HERE/RESULTS/riscof_$(echo "${SUITE_FILTER:-all}" | tr '/' '_').log"
docker run --rm --cpus=8 -v "$PROOT:/work" -w /work/ip/cores/eclass/sim/riscof \
  eclass-riscof-arm64:local bash -lc "
    set -euo pipefail
    [ -d riscv-arch-test ] || riscof --verbose info arch-test --clone
    SUITE=riscv-arch-test/riscv-test-suite/${SUITE_FILTER:-}
    riscof run --config=config.ini \
      --suite=\$SUITE \
      --env=riscv-arch-test/riscv-test-suite/env \
      --no-browser ${ARGS[*]:-}
  " 2>&1 | tee "$RUNLOG"
# RISCOF rewrites riscof_work per invocation, so MERGE each suite's rows into the running matrix
# instead of overwriting it — otherwise the last suite silently erases every earlier one.
python3 "$HERE/parse_riscof.py" "$RUNLOG" > "$HERE/RESULTS/_last.json"
python3 - "$HERE/RESULTS" <<'PYMERGE'
import json, pathlib, sys
d = pathlib.Path(sys.argv[1])
cur = json.loads((d / "compliance.json").read_text()) if (d / "compliance.json").is_file() and (d / "compliance.json").read_text().strip() else []
new = json.loads((d / "_last.json").read_text())
by_key = {(r["suite"], r["test"]): r for r in cur}
for r in new:
    by_key[(r["suite"], r["test"])] = r
rows = sorted(by_key.values(), key=lambda r: (r["suite"], r["test"]))
(d / "compliance.json").write_text(json.dumps(rows, indent=2))
print(f"matrix now holds {len(rows)} tests across {len({r['suite'] for r in rows})} suites")
PYMERGE
echo "--- summary ---"
python3 - <<'PY'
import json, pathlib, collections
p = pathlib.Path("ip/cores/eclass/sim/RESULTS/compliance.json")
if not p.is_file() or not p.read_text().strip():
    print("no compliance.json produced"); raise SystemExit
rows = json.loads(p.read_text())
c = collections.Counter((r["suite"], r["result"]) for r in rows)
for (s, res), n in sorted(c.items()):
    print(f"{s:24s} {res:5s} {n}")
PY
