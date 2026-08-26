"""Extract the top module's port list from generated Verilog into a stable, diffable form.
bsc emits a plain `module mkeclass_axi4lite(...)` header with one declaration per line.

The --top switch exists so the SAME extractor can be pointed at our wrapper (eclass_top), which is
how G1 proves the wrapper's boundary is identical to the core's: one extractor, two inputs, one
golden file. A second extractor would eventually disagree with this one."""
import pathlib, re, sys

DEFAULT_TOP = "mkeclass_axi4lite"


def extract(vfile, top=DEFAULT_TOP):
    src = pathlib.Path(vfile).read_text()
    m = re.search(rf"^module\s+{top}\s*\((.*?)\);", src, re.S | re.M)
    if not m:
        sys.exit(f"top module {top} not found in {vfile}")
    body = src[m.end():]
    ports = []
    for name in [p.strip() for p in m.group(1).split(",") if p.strip()]:
        # The optional wire/reg is required for the wrapper: it declares `input wire CLK;` where
        # bsc writes `input CLK;`. Without it every wrapper port would extract as "unknown" and the
        # golden diff would fail for a purely cosmetic reason.
        d = re.search(rf"^\s*(input|output|inout)\s*(?:wire\s+|reg\s+)?"
                      rf"(\[\s*(\d+)\s*:\s*(\d+)\s*\])?\s*{re.escape(name)}\s*;",
                      body, re.M)
        if not d:
            ports.append((name, 1, "unknown"))
            continue
        width = 1 if not d.group(2) else abs(int(d.group(3)) - int(d.group(4))) + 1
        ports.append((name, width, d.group(1)))
    return sorted(ports)


if __name__ == "__main__":
    args = sys.argv[1:]
    top = DEFAULT_TOP
    if "--top" in args:
        i = args.index("--top")
        top = args[i + 1]
        args = args[:i] + args[i + 2:]
    for n, w, d in extract(args[0], top):
        print(f"{n} {w} {d}")
