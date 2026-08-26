#!/usr/bin/env bash
# Vendor the six SHAKTI repos at PINNED SHAs. Do NOT use upstream manager.sh:
#  (a) it floats common_bsv / common_verilog / benchmarks at master, and
#  (b) `update_deps` gates on dtc 1.4.7 before it will clone anything.
set -euo pipefail
BSV="$(cd "$(dirname "$0")/.." && pwd)/bsv"
mkdir -p "$BSV"

clone() {  # clone <name> <url> <sha>
  local name=$1 url=$2 sha=$3 d="$BSV/$1"
  if [ ! -d "$d/.git" ]; then git clone --quiet "$url" "$d"; fi
  git -C "$d" fetch --quiet --all
  git -C "$d" checkout --quiet --detach "$sha"
  printf '%-16s %s\n' "$name" "$(git -C "$d" rev-parse HEAD)"
}

clone e-class        https://gitlab.com/shaktiproject/cores/e-class.git     e8a0dfd2d1c4907c74fb58432e379016871fdd3a
clone fabrics        https://gitlab.com/shaktiproject/uncore/fabrics.git    c3d6da4c515886ebe0462995aa0624090dbef85d
clone common_bsv     https://gitlab.com/shaktiproject/common_bsv.git        89f04a53b4d8db659ed9aade9b3490df70aecaab
clone common_verilog https://gitlab.com/shaktiproject/common_verilog.git    029a15059798d5400d0821934f2f36e192b92d01
clone devices        https://gitlab.com/shaktiproject/uncore/devices.git    c622ad128b81fc74f7a2365241d51488f7b9dd72
# Authoritative URLs/refs come from e-class/base-sim/manager.sh (repo_list + branch_list).
# NOTE the subgroup: verification lives under verification_environment/, not the top level.
clone verification   https://gitlab.com/shaktiproject/verification_environment/verification.git 3.2.6
# benchmarks FLOATS at master upstream and is not needed for M0-M3 (Verilog generation or RISCOF);
# pinned here anyway so the dependency set is fully reproducible.
clone benchmarks     https://gitlab.com/shaktiproject/cores/benchmarks.git   654ef7f128e2505c366e9be821f566e3a046cdd7
