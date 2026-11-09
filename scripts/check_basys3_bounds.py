#!/usr/bin/env python3
"""Prove accumulator and quant multiplier widths for this exact coefficient set."""
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MEM = ROOT / "memory"

def signed_hex(path: Path, bits: int) -> np.ndarray:
    raw = np.array([int(x, 16) for x in path.read_text(encoding="ascii").split()], dtype=np.uint32)
    mask = (1 << bits) - 1
    raw &= mask
    if bits == 8:
        return raw.astype(np.uint8).view(np.int8)
    return raw.astype(np.uint32).view(np.int32)

def signed_width_for_abs_bound(bound: int) -> int:
    width = 1
    while bound > (1 << (width - 1)) - 1:
        width += 1
    return width

conv_max = 0
for layer, (oc, ic) in enumerate(((16,1),(32,16),(64,32),(64,64)), start=1):
    w = signed_hex(MEM / f"layer{layer}_weights.mem", 8).reshape(oc, ic, 3, 3).astype(np.int64)
    bounds = np.abs(w).sum(axis=(1,2,3)) * 255
    layer_max = int(bounds.max())
    conv_max = max(conv_max, layer_max)
    print(f"conv{layer}: max |accumulator| <= {layer_max:,}; signed width required={signed_width_for_abs_bound(layer_max)}")

dw = signed_hex(MEM / "layer5_dense_weights.mem", 8).reshape(4,2304).astype(np.int64)
db = signed_hex(MEM / "layer5_dense_biases.mem", 32).astype(np.int64)
dense_bounds = np.abs(dw).sum(axis=1) * 255 + np.abs(db)
dense_max = int(dense_bounds.max())
print(f"dense: max |accumulator| <= {dense_max:,}; signed width required={signed_width_for_abs_bound(dense_max)}")

mult_files = [MEM / f"layer{i}_multipliers.mem" for i in range(1,5)] + [MEM / "layer5_dense_multiplier.mem"]
mults = np.concatenate([signed_hex(p, 32).astype(np.int64) for p in mult_files])
max_mult = int(np.abs(mults).max())
print(f"Q24 multipliers: max |M|={max_mult:,}; signed width required={signed_width_for_abs_bound(max_mult)}")

assert conv_max <= (1 << 23) - 1, "24-bit signed convolution accumulator is not sufficient"
assert dense_max <= (1 << 24) - 1, "25-bit signed dense accumulator is not sufficient"
assert max_mult <= (1 << 17) - 1, "18-bit signed multiplier is not sufficient"
print("PASS: 24-bit conv accumulators, 25-bit dense accumulators, and 18-bit Q multipliers are safe for these exact MEM files.")
