#!/usr/bin/env bash
# prerelease_scan.sh — MUST pass before this repository is published or updated.
#
# Two jobs:
#   1. no host-identifying absolute paths leak into the release
#   2. no credentials, keys, tokens or personal data leak into the release
#
# Exit non-zero on any finding. Run from the repository root.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
say(){ printf '%s\n' "$*"; }

say "=== 1. host-identifying paths ==="
# /work/ is the ORFS CONTAINER mount and is deliberately allowed: it is a documented convention
# (see REPRODUCE.md), identical for every user, and reveals nothing about the build host.
for pat in '/Users/' '/home/' 'Desktop/projects' 'orfs1' 'asia-south1' 'pqc-full-scope'; do
  hits=$(grep -rlI --exclude-dir=.git --exclude=prerelease_scan.sh -- "$pat" "$ROOT" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$hits" != "0" ]; then
    say "  FAIL  '$pat' found in $hits file(s):"
    grep -rlI --exclude-dir=.git --exclude=prerelease_scan.sh -- "$pat" "$ROOT" 2>/dev/null | sed "s#$ROOT/#    #" | head -10
    fail=1
  else
    say "  ok    '$pat' absent"
  fi
done

say ""
say "=== 2. credentials / keys / personal data ==="
python3 - "$ROOT" <<'PYEOF'
import pathlib, re, sys, gzip

R = pathlib.Path(sys.argv[1])

# HIGH-SIGNAL patterns: literal enough that a match in ANY content -- text or binary -- is real.
STRICT = {
 "AWS access key":    r"AKIA[0-9A-Z]{16}",
 "GitHub token":      r"gh[pousr]_[A-Za-z0-9]{16,}",
 "Anthropic key":     r"sk-ant-[A-Za-z0-9_\-]{10,}",
 "OpenAI key":        r"sk-[A-Za-z0-9]{32,}",
 "Google API key":    r"AIza[0-9A-Za-z_\-]{35}",
 "Slack token":       r"xox[baprs]-[A-Za-z0-9\-]{10,}",
 "private key block": r"-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY",
 "host path":         r"/Users/[A-Za-z0-9._-]+",
}
# LOOSE patterns: meaningful in TEXT only. Applied to binary they match random byte noise --
# gzip streams alone produced dozens of fake "emails" like 'C@u.Uy'. Never apply these to binary.
LOOSE = {
 "password assign": r"(?i)\b(password|passwd|pwd)\s*[:=]\s*['\"][^'\"]{3,}",
 "token assign":    r"(?i)\b(api[_-]?key|secret|token|credential)\s*[:=]\s*['\"][^'\"]{8,}",
 "bearer header":   r"(?i)authorization:\s*bearer\s+\S+",
 "email address":   r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}",
 "IPv4 address":    r"\b(?:\d{1,3}\.){3}\d{1,3}\b",
 "ssh key path":    r"(?i)(id_rsa|id_ed25519|\.ssh/)",
}

def content_of(f):
    """Return (bytes, note). .gz is DECOMPRESSED so we scan what it actually carries."""
    try:
        if f.suffix == ".gz":
            with gzip.open(f, "rb") as fh:
                return fh.read(64 * 1024 * 1024), " (decompressed)"
        return f.read_bytes(), ""
    except Exception:
        return b"", " (unreadable)"

def is_text(b):
    return b"\x00" not in b[:8192]

bad = 0
for f in sorted(R.rglob("*")):
    if not f.is_file() or "/.git/" in str(f): continue
    if f.name == "prerelease_scan.sh": continue   # holds the patterns by definition
    raw, note = content_of(f)
    if not raw: continue
    txt = raw.decode("utf-8", errors="ignore")
    text_like = is_text(raw)
    pats = dict(STRICT)
    if text_like: pats.update(LOOSE)
    for name, pat in pats.items():
        m = re.search(pat, txt)
        if m:
            kind = "text" if text_like else "BINARY"
            print(f"  FAIL  [{name}] {f.relative_to(R)}{note} ({kind}): {m.group(0)[:60]!r}")
            bad = 1
print("  ok    no credential/PII pattern matched" if not bad else "")
sys.exit(bad)
PYEOF
[ $? -ne 0 ] && fail=1

say ""
if [ "$fail" = "0" ]; then say "PRE-RELEASE SCAN: PASS"; else say "PRE-RELEASE SCAN: FAIL — do not publish"; fi
exit $fail
