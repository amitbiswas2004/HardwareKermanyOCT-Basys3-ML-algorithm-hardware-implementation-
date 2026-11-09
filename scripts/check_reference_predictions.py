#!/usr/bin/env python3
"""Numpy reference check using only rtl_ok's quantized weights and test vectors.

This checks the intended layer order, valid convolution, Q24 scaling, uint8
ReLU/clamp, floor 2x2 pooling and dense flatten/argmax arithmetic. It is not an
RTL simulator and does not replace Vivado behavioral simulation.
"""
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MEM = ROOT / "memory"
VECTORS = ROOT / "simulation" / "testbench_vectors"
CLASSES = ["CNV", "DME", "DRUSEN", "NORMAL"]


def read_signed(path: Path, dtype: str) -> np.ndarray:
    bits = 8 if dtype == "i8" else 32
    raw = np.array([int(v, 16) for v in path.read_text(encoding="ascii").split()], dtype=np.uint32)
    mask = (1 << bits) - 1
    raw &= mask
    if dtype == "i8":
        return raw.astype(np.uint8).view(np.int8)
    return raw.astype(np.uint32).view(np.int32)


def valid_conv_relu_pool(x: np.ndarray, weights: np.ndarray, multiplier: np.ndarray) -> np.ndarray:
    out_channels, in_channels = weights.shape[:2]
    height, width = x.shape[1:]
    oh, ow = height - 2, width - 2
    windows = np.lib.stride_tricks.sliding_window_view(x, (3, 3), axis=(1, 2))
    acc = np.einsum(
        "cxyij,ocij->oxy",
        windows.astype(np.int64),
        weights.reshape(out_channels, in_channels, 3, 3).astype(np.int64),
        optimize=True,
    )
    scaled = acc * multiplier.astype(np.int64)[:, None, None]
    shifted = np.right_shift(scaled, 24)  # Original conv RTL uses ZERO_POINT=0.
    quantized = np.clip(shifted, 0, 255).astype(np.uint8)
    ph, pw = oh // 2, ow // 2
    return quantized[:, :2 * ph, :2 * pw].reshape(out_channels, ph, 2, pw, 2).max(axis=(2, 4))


def predict(image_file: Path) -> tuple[int, list[int]]:
    pixels = np.array([int(v, 16) for v in image_file.read_text(encoding="ascii").split()], dtype=np.uint8)
    if pixels.size != 128 * 128:
        raise ValueError(f"{image_file.name}: expected 16384 pixels, found {pixels.size}")
    x = pixels.reshape(1, 128, 128)

    channel_shapes = [(16, 1), (32, 16), (64, 32), (64, 64)]
    for layer, (out_ch, in_ch) in enumerate(channel_shapes, start=1):
        w = read_signed(MEM / f"layer{layer}_weights.mem", "i8")
        m = read_signed(MEM / f"layer{layer}_multipliers.mem", "i32")
        expected = out_ch * in_ch * 9
        if w.size != expected or m.size != out_ch:
            raise ValueError(f"Layer {layer}: incorrect weight/multiplier count")
        x = valid_conv_relu_pool(x, w.reshape(out_ch, in_ch, 3, 3), m)

    features = x.reshape(-1).astype(np.int64)
    if features.size != 2304:
        raise ValueError(f"Expected 2304 dense features, got {features.size}")
    dense_w = read_signed(MEM / "layer5_dense_weights.mem", "i8").reshape(4, 2304).astype(np.int64)
    dense_b = read_signed(MEM / "layer5_dense_biases.mem", "i32").astype(np.int64)
    dense_m = int(read_signed(MEM / "layer5_dense_multiplier.mem", "i32")[0])
    acc = dense_b + dense_w @ features
    logits = np.right_shift(acc * dense_m, 24) + 86
    logits = ((logits + (1 << 31)) % (1 << 32)) - (1 << 31)
    return int(np.argmax(logits)), [int(v) for v in logits]


def main() -> None:
    passed = 0
    for label in CLASSES:
        vector = VECTORS / f"tb_img_{label}_expected_{label}.mem"
        prediction, logits = predict(vector)
        ok = CLASSES[prediction] == label
        passed += int(ok)
        print(f"{label:7s}: predicted={CLASSES[prediction]:7s} {'PASS' if ok else 'FAIL'} logits={logits}")
    print(f"Reference-vector class agreement: {passed}/4")
    if passed != 4:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
