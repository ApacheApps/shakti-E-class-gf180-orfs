"""Emit the mkeclass_axi4lite instantiation for tb_eclass_smoke.sv from golden/ports.txt.

A mis-bound AXI4-Lite handshake presents as a fetch hang, which is indistinguishable from a broken
core — it would burn the milestone chasing the wrong thing. So the binding is DERIVED, not typed.

bsc names slave->master inputs after the method that produces them, e.g.
    master_d_m_rvalid_rdata   -> the BFM's rdata
    master_d_m_arready_arready-> the BFM's arready
Master->slave outputs keep plain AXI names (master_d_araddr -> araddr).

Anything the rules do not recognise is reported as UNBOUND and must be resolved deliberately.
"""
import os, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
GOLDEN = HERE.parent / "golden" / "ports.txt"

# bsc method-name suffix -> the BFM port it corresponds to
INPUT_MAP = {
    "m_arready_arready": "arready",
    "m_awready_awready": "awready",
    "m_wready_wready":   "wready",
    "m_bvalid_bvalid":   "bvalid",
    "m_bvalid_bresp":    "bresp",
    "m_rvalid_rvalid":   "rvalid",
    "m_rvalid_rdata":    "rdata",
    "m_rvalid_rresp":    "rresp",
}
# master->slave signals the BFM consumes
OUTPUT_KEEP = {"araddr", "arvalid", "awaddr", "awvalid",
               "wdata", "wstrb", "wvalid", "bready", "rready"}
# dialect sidebands the BFM deliberately ignores (all accesses here are 32-bit)
OUTPUT_IGNORE = {"arprot", "arsize", "awprot", "awsize"}

# resetpc is a runtime input port on the core. The smoke TB ties it to the .inc's 4096; the
# arch-test TB drives it from a plusarg (entry point differs per test image). Both declare a
# `resetpc_i` net, so the generated binding is shared.
RESETPC = "resetpc_i"

# Which module the TB instantiates. The wrapper (eclass_top) has an IDENTICAL port list to the core
# by construction (tests/test_top_ports.py::test_wrapper_ports_are_identical_to_the_core), so the
# same derived binding is valid for both and only the module name changes.
TOP = os.environ.get("DUT_TOP", "mkeclass_axi4lite")


def main():
    lines, unbound = [], []
    for raw in GOLDEN.read_text().split("\n"):
        if not raw.strip():
            continue
        name, width, direction = raw.split()
        w = int(width)

        if name in ("CLK", "RST_N"):
            lines.append(f"    .{name}({name})")
        elif m := re.fullmatch(r"master_([id])_(.*)", name):
            idx = 0 if m.group(1) == "i" else 1
            sig = m.group(2)
            if sig in INPUT_MAP:
                lines.append(f"    .{name}(bfm{idx}_{INPUT_MAP[sig]})")
            elif sig in OUTPUT_KEEP:
                lines.append(f"    .{name}(bfm{idx}_{sig})")
            elif sig in OUTPUT_IGNORE:
                lines.append(f"    .{name}()")
            else:
                unbound.append(name)
        elif name == "resetpc":
            lines.append(f"    .{name}({RESETPC})")
        elif name.startswith("RDY_"):
            lines.append(f"    .{name}()")
        elif name.startswith("EN_") or name.startswith("sb_"):
            lines.append(f"    .{name}({w}'b0)" if direction == "input" else f"    .{name}()")
        elif name.startswith("debug_server"):
            # M0-M3 does not exercise debug; drive requests inactive, leave observations open.
            lines.append(f"    .{name}({w}'b0)" if direction == "input" else f"    .{name}()")
        else:
            unbound.append(name)

    if unbound:
        sys.exit("UNBOUND ports (resolve deliberately, do not guess): " + ", ".join(unbound))
    print(f"  {TOP} dut (\n" + ",\n".join(lines) + "\n  );")


if __name__ == "__main__":
    main()
