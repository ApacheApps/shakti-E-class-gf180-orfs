# Sign-off collateral

Everything needed to inspect, integrate or re-verify this block, committed in-repo (compressed)
rather than attached as release downloads.

| path | contents | raw | in-repo |
|---|---|---|---|
| `gds/eclass_top_gf180_25mhz_filled.gds.gz` | **tapeout candidate** — stock DRM-compliant metal fill | 59.9 MB | 8.5 MB |
| `gds/eclass_top_gf180_25mhz_nofill.gds.gz` | unfilled build — **the LVS database** | 53.0 MB | 7.0 MB |
| `def/eclass_top_gf180_25mhz.def.gz` | routed DEF (filled build) | 61.9 MB | 6.5 MB |
| `spef/eclass_top_gf180_25mhz.spef.gz` | post-route parasitics used for sign-off STA | 42.2 MB | 12.2 MB |
| `views/eclass_top.lef` | **abstract LEF** — outline, 423 pins, obstructions | | 73 KB |
| `views/eclass_top_ss_125C_4v50.lib` | Liberty, **slow** corner | | 305 KB |
| `views/eclass_top_tt_025C_5v00.lib` | Liberty, **typical** corner | | 304 KB |
| `views/eclass_top_ff_n40C_5v50.lib` | Liberty, **fast** corner | | 304 KB |

| `lvs/layout_magic_extracted.spice.gz` | magic's extraction of the unfilled GDS — the LVS layout netlist | 6.3 MB | 639 KB |
| `lvs/schematic.spice.gz` | the LVS schematic netlist (logic + the 27 antenna diodes) | 3.2 MB | 367 KB |

`SHA256SUMS` covers every file here.

The two `lvs/` netlists are the exact inputs that produced `../reports/lvs_netgen.report`
(`Circuits match uniquely`), so the comparison can be re-run in seconds without redoing extraction:

```bash
gunzip -k lvs/*.gz
PDK_ROOT=<dir containing gf180mcuC> \
  ../scripts/signoff/lvs/run_netgen.sh lvs/layout_magic_extracted.spice lvs/schematic.spice eclass_top /tmp/lvs
```

```bash
shasum -a 256 -c SHA256SUMS      # verify
gunzip -k gds/eclass_top_gf180_25mhz_filled.gds.gz
```

## Which GDS to use

- **Integrating / manufacturing** → the **filled** one. Its fill is stock ORFS, which implements the
  GF180 DRM §13.3 dummy-metal rules (`space_to_non_fill` 2.0 µm = DM.3, min shape 2.0 µm = DM.1).
- **Running LVS** → the **unfilled** one. The gf180 LVS deck defines
  `metal1 = metal1_drawn + metal1_dummy` and derives connectivity from it, so metal fill extracts as
  tens of thousands of phantom floating nets. See `../docs/LVS_FLOW.md`.

## About the abstract views

`views/` lets the block be instantiated as a hard macro without the full netlist. The Liberty models
carry **519 timing arcs** with `CLK` correctly marked `clock : true`.

⚠️ **Caveat worth knowing if you regenerate these.** OpenSTA's `write_timing_model` **silently drops
every timing arc launched by an internally-generated clock** — no warning is issued (the check at
`MakeTimingModel.cc:230` is never called). A block with an internal divider or gated clock can emit a
Liberty that looks fine and reports false-clean in downstream STA. This design is immune because its
single clock arrives on a top-level port and no generated clocks exist — which is exactly why that
design rule was adopted. **If you adapt this flow to a block with internal clock generation, verify
the emitted Liberty contains arcs before trusting it.**

## Not included

Timing here does **not** model metal fill: OpenRCX has no `dbFill` handling, so the SPEF from the
filled and unfilled builds is byte-identical apart from its timestamp. See `../DISCLAIMERS.md` §2.3.
