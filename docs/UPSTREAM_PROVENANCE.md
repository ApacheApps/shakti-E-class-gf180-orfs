# ip/cores/eclass — provenance

All upstream sources vendored at explicit SHAs by `scripts/vendor.sh`. Verified 2026-08-23.

| repo | url | sha | license | date |
|---|---|---|---|---|
| e-class | https://gitlab.com/shaktiproject/cores/e-class.git | e8a0dfd2d1c4907c74fb58432e379016871fdd3a | BSD-3-Clause (IIT Madras 2018) | 2019-12-17 |
| fabrics | https://gitlab.com/shaktiproject/uncore/fabrics.git | c3d6da4c515886ebe0462995aa0624090dbef85d | BSD-3-Clause | 2019-11-19 |
| common_bsv | https://gitlab.com/shaktiproject/common_bsv.git | 89f04a53b4d8db659ed9aade9b3490df70aecaab | BSD-3-Clause (LICENSE.iitm) | 2025-11-25 |
| common_verilog | https://gitlab.com/shaktiproject/common_verilog.git | 029a15059798d5400d0821934f2f36e192b92d01 | MIT (per-file headers; NO repo LICENSE file) | 2025-05-02 |
| devices | https://gitlab.com/shaktiproject/uncore/devices.git | c622ad128b81fc74f7a2365241d51488f7b9dd72 | BSD-3-Clause | 2019-11-11 |
| verification | https://gitlab.com/shaktiproject/verification_environment/verification.git | 4e72ce93b774217ab73db3ffd2fd04054e5b959b | BSD-3-Clause | 2019-11-19 |
| benchmarks | https://gitlab.com/shaktiproject/cores/benchmarks.git | 654ef7f128e2505c366e9be821f566e3a046cdd7 | BSD-3-Clause (LICENSE.iitm) | 2025-08-14 |

Toolchain: Bluespec Compiler **2026.01** (build **9bd39e6f3**),
`BLUESPECDIR=/opt/homebrew/Cellar/bsc/2026.01/libexec/lib`

## Verification toolchain (M1)

Image `eclass-riscof-arm64:local`, built from `sim/Dockerfile.riscof` on `orfs-sim-arm64:local`
(Ubuntu 24.04, arm64).

| tool | version / commit |
|---|---|
| RISCOF | 1.25.3 |
| Spike (reference model) | 1.1.1-dev @ `231e0d535d371eed4a7f5781d82ea0a8b96bdae2` |
| Verilator | from base image |
| riscv32-unknown-elf-gcc | from base image |

Spike is **pinned by commit** in the Dockerfile. A floating reference model would silently change
the golden signatures RISCOF compares against, which would turn a reference-model change into an
apparent DUT regression. The SHA is also baked into the image at `/opt/spike.sha` and asserted by
`sim/tests/test_toolchain_present.py`.

## Upstream pinning vs ours

`e-class/base-sim/manager.sh` is the authoritative dependency list. It pins only three of six:

| dep | upstream ref | our pin |
|---|---|---|
| devices | `5.0.2` | SHA above |
| fabrics | `1.2.0` | SHA above |
| verification | `3.2.6` | SHA above |
| common_bsv | **`master` (floats)** | SHA above |
| common_verilog | **`master` (floats)** | SHA above |
| benchmarks | **`master` (floats)** | SHA above |

We pin all seven. `common_verilog`'s newest commit is literally a "new regfile variant" — left
floating it would silently change our RTL between runs.

`manager.sh` is otherwise **not used**: its `update_deps` gates on `dtc 1.4.7` before it will clone
anything, and it would reintroduce the three floating refs.

## Notes

- e-class RTL is **FROZEN** at 2019-12-17 (= tag 1.10.2). Branch `89-fix-compilation` (2025-05-19)
  touches only build infrastructure (`.gitlab-ci.yml`, `base-sim/Makefile`, `manager.sh`,
  `bootcode/`, `soc_config.inc`) — zero `src/` files — and is **not** merged here, because we bypass
  that Makefile entirely (see spec AMENDMENT 1 and `scripts/gen.sh`).
- The GitHub mirror `anmolsahoo25/shakti-e-class` is **not used**: it sits at `13bf929d`
  (2019-09-25, tag 1.8.0) with zero occurrences of `DTVEC_BASE`, so cloning it silently loses a
  config knob.
- The prebuilt `verilog-artifacts.zip` is **not used**: HTTP 404 at every ref, and its own docs
  record it as GPL-v3.
- `benchmarks` is vendored for reproducibility but is **not required** for M0–M3 (neither Verilog
  generation nor RISCOF uses it).

## License position — read this before any tapeout

The BSV source is BSD-3-Clause. Our regenerated Verilog carries no injected license header because
we do not run upstream's non-public `insert_license.sh`. **This is our reading, not counsel.**
Obtain legal advice before any fabbed commercial derivative.
