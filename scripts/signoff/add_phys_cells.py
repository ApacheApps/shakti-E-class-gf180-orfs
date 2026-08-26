#!/usr/bin/env python3
"""Splice physical-only cells into an LVS schematic netlist, ordered by the PDK's own .SUBCKT lines.

WHY ALL of them, not just device-bearing ones: KLayout LVS builds a circuit for EVERY cell it finds
in the layout, devices or not, and expects a matching circuit on the schematic side. Adding only the
antenna diodes left LVS still failing with ten mismatching circuits — ANTENNA, ENDCAP, FILLTIE and
every FILL_* size. "Contains no transistors" does not mean "invisible to LVS".

Input lines: `X<inst> <master> pin=net pin=net ...` (order-independent pairs).
Pin ORDER is taken from the PDK SPICE, never from the LEF, because subcircuit calls are positional.

Usage: add_phys_cells.py <netlist.spice> <physcells.txt> <cells.spice>
"""
import collections
import pathlib
import re
import sys


def subckt_pin_order(spice_path):
    order = {}
    with open(spice_path) as fh:
        for line in fh:
            m = re.match(r"\.SUBCKT\s+(\S+)\s*(.*)", line.strip(), re.I)
            if m:
                order[m.group(1)] = m.group(2).split()
    return order


def main():
    net_path, phys_path, cells_spice = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]),
                                        sys.argv[3])
    order = subckt_pin_order(cells_spice)
    s = net_path.read_text()
    if ".ENDS" not in s:
        sys.exit("add_phys_cells: no .ENDS in netlist -- refusing to guess where cells belong")

    lines, stats, unknown = [], collections.Counter(), set()
    for raw in phys_path.read_text().splitlines():
        raw = raw.strip()
        if not raw or raw.startswith(("PHYSCELL_STAT", "PHYSCELL_COUNT")):
            continue
        parts = raw.split()
        inst, master, pairs = parts[0], parts[1], parts[2:]
        if master not in order:
            unknown.add(master)
            continue
        conn = dict(p.split("=", 1) for p in pairs if "=" in p)
        pins = []
        for pin in order[master]:
            if pin in ("VDD", "VNW"):
                pins.append("VDD")
            elif pin in ("VSS", "VPW"):
                pins.append("VSS")
            else:
                pins.append(conn.get(pin, f"UNCONN_{inst}_{pin}"))
        lines.append(f"{inst} {' '.join(pins)} {master}")
        stats[master] += 1

    if unknown:
        sys.exit(f"add_phys_cells: no .SUBCKT for {sorted(unknown)} -- refusing to emit a call whose "
                 "pin order cannot be verified")

    added = [l for l in lines if l.split()[0] not in s]
    if added:
        s = s.replace(".ENDS ", "\n".join(added) + "\n.ENDS ", 1)
        net_path.write_text(s)
    print(f"add_phys_cells: added {len(added)} physical-only cells")
    for k, v in sorted(stats.items()):
        print(f"    {v:>7} {k}")


if __name__ == "__main__":
    main()
