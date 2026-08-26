"""Emit one 32-bit little-endian word per line for $readmemh.

Deliberately NOT `objcopy -O verilog`: that emits byte records whose @address semantics shift with
--verilog-data-width, which is exactly the kind of ambiguity that turns into a phantom 'broken core'.
Here the TB knows the load index explicitly.
"""
import sys

data = open(sys.argv[1], "rb").read()
data += b"\x00" * (-len(data) % 4)
for i in range(0, len(data), 4):
    print(f"{int.from_bytes(data[i:i+4], 'little'):08x}")
