#!/usr/bin/env python3
"""Convert the signed-off gate-level Verilog netlist into a SPICE netlist for KLayout LVS.

WHY THIS EXISTS AND WHY IT IS NOT `yosys write_spice`:
The gf180mcu LVS deck reads the schematic with RBA::NetlistSpiceReader -- it needs SPICE, not
Verilog. The trap is PIN ORDER: a SPICE subcircuit call is POSITIONAL, so the order must match the
PDK's own `.SUBCKT` lines exactly. Any generator that orders pins by the liberty/Verilog port order
instead would emit a netlist that parses cleanly and then fails LVS with thousands of phantom
mismatches -- a false negative that looks like a real one. So pin order here is read from the PDK
SPICE file itself and from nowhere else.

Power handling: cells declare VDD VNW VPW VSS. The Verilog netlist has no power pins, so the
supplies are bound by convention -- VDD and VNW (n-well) to VDD; VSS and VPW (p-well) to VSS --
which is what the flow's PDN actually builds.

The emitted `.include` must name the cell SPICE **as the LVS tool will see it**, which is not
necessarily where this script read it from: KLayout runs inside a container with the PDK bind-mounted
elsewhere. A wrong path here does not fail loudly at generation time -- it fails hours later inside
LVS with "Unable to open file ... line 2 in Netlist::read", which is exactly what happened on the
first VM run. Hence the optional include-path override.

Usage: v2spice.py <netlist.v> <cells.spice> <out.spice> [top] [--include=<path-as-LVS-sees-it>]
"""
import re
import sys


def subckt_pin_order(spice_path):
    """Pin order for every cell, taken from the PDK SPICE .SUBCKT lines -- the authority."""
    order = {}
    with open(spice_path) as fh:
        for line in fh:
            m = re.match(r"\.SUBCKT\s+(\S+)\s*(.*)", line.strip(), re.I)
            if m:
                order[m.group(1)] = m.group(2).split()
    return order


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


# A Verilog signal is either an escaped identifier (backslash ... whitespace) or a plain one,
# optionally bit- or part-selected. Escaped names are how the flow encodes hierarchy (\riscv.x.y[3] ).
SIG = r"(?:\\\S+\s|[A-Za-z_][\w$]*(?:\s*\[[^\]]*\])?)"


def clean(sig):
    """Verilog signal -> SPICE node name. SPICE is whitespace-delimited, so the escape marker and
    its terminating space must go; the remaining characters ('.', '[', ']') are accepted by the
    KLayout reader and are kept so net names stay traceable back to the RTL."""
    sig = sig.strip()
    if sig.startswith("\\"):
        sig = sig[1:]
    return re.sub(r"\s+", "", sig)


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--include=")]
    inc = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--include=")), None)
    vpath, spath, opath = argv[0], argv[1], argv[2]
    top = argv[3] if len(argv) > 3 else "mkeclass_axi4lite"

    order = subckt_pin_order(spath)
    text = strip_comments(open(vpath).read())

    m = re.search(r"\bmodule\s+" + re.escape(top) + r"\s*\((.*?)\)\s*;", text, re.S)
    if not m:
        sys.exit(f"v2spice: top module {top} not found")
    ports = [clean(p) for p in m.group(1).split(",") if p.strip()]

    inst_re = re.compile(
        r"(gf180mcu_fd_sc_\w+)\s+(" + SIG + r")\s*\((.*?)\)\s*;", re.S)
    conn_re = re.compile(r"\.(\w+)\s*\(\s*(" + SIG + r")\s*\)")

    lines, n_inst, unknown = [], 0, set()
    for cell, iname, body in inst_re.findall(text):
        if cell not in order:
            unknown.add(cell)
            continue
        conns = {p: clean(s) for p, s in conn_re.findall(body)}
        pins = []
        for pin in order[cell]:
            if pin in ("VDD", "VNW"):
                pins.append("VDD")
            elif pin in ("VSS", "VPW"):
                pins.append("VSS")
            elif pin in conns:
                pins.append(conns[pin])
            else:
                # An unconnected cell pin is real (clkload outputs, unused adder carries). It gets
                # its own dangling node rather than being dropped, which would silently merge nets.
                pins.append(f"{clean(iname)}__{pin}__UNCONN")
        lines.append(f"X{clean(iname)} {' '.join(pins)} {cell}")
        n_inst += 1

    if unknown:
        sys.exit(f"v2spice: cells with no .SUBCKT in {spath}: {sorted(unknown)}")

    with open(opath, "w") as out:
        out.write(f"* Generated from {vpath} by v2spice.py -- pin order taken from {spath}\n")
        out.write(f".include \"{inc or spath}\"\n")
        out.write(f".SUBCKT {top} {' '.join(ports)} VDD VSS\n")
        out.write("\n".join(lines))
        out.write(f"\n.ENDS {top}\n")

    print(f"v2spice: {n_inst} instances, {len(ports)} top ports -> {opath}")
    if n_inst == 0:
        sys.exit("v2spice: parsed zero instances -- refusing to emit an empty netlist")


if __name__ == "__main__":
    main()
