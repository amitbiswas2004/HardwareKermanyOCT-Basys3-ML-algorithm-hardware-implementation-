#!/usr/bin/env python3
"""Validate rtl_ok coefficient files and pack the four dense rows feature-major.

Expected source files are the copies supplied in reference/bit_true_hw_files.
Run from the project root:
    python scripts/export_mem.py --source-dir reference/bit_true_hw_files --out-dir memory
"""
from __future__ import annotations

import argparse
from pathlib import Path

EXPECTED = {
    "layer1_weights.mem": 144,
    "layer2_weights.mem": 4608,
    "layer3_weights.mem": 18432,
    "layer4_weights.mem": 36864,
    "layer1_multipliers.mem": 16,
    "layer2_multipliers.mem": 32,
    "layer3_multipliers.mem": 64,
    "layer4_multipliers.mem": 64,
    "layer5_dense_weights.mem": 4 * 2304,
    "layer5_dense_biases.mem": 4,
    "layer5_dense_multiplier.mem": 1,
}


def read_hex_words(path: Path, bits: int, expected_count: int) -> list[int]:
    if not path.is_file():
        raise FileNotFoundError(f"Missing required file: {path}")
    words: list[int] = []
    mask = (1 << bits) - 1
    for line_no, line in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        token = line.strip()
        if not token:
            continue
        try:
            value = int(token, 16)
        except ValueError as exc:
            raise ValueError(f"Invalid hexadecimal word at {path}:{line_no}: {token!r}") from exc
        if value < 0 or value > mask:
            raise ValueError(f"Word does not fit {bits} bits at {path}:{line_no}: {token}")
        words.append(value)
    if len(words) != expected_count:
        raise ValueError(f"{path.name}: expected {expected_count} words, found {len(words)}")
    return words


def write_words(path: Path, words: list[int], digits: int) -> None:
    path.write_text("".join(f"{word:0{digits}X}\n" for word in words), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, default=Path("reference/bit_true_hw_files"))
    parser.add_argument("--out-dir", type=Path, default=Path("memory"))
    args = parser.parse_args()

    src = args.source_dir
    out = args.out_dir
    out.mkdir(parents=True, exist_ok=True)

    loaded: dict[str, list[int]] = {}
    for name, count in EXPECTED.items():
        bits = 32 if ("multipliers" in name or "biases" in name or name == "layer5_dense_multiplier.mem") else 8
        loaded[name] = read_hex_words(src / name, bits, count)
        if name != "layer5_dense_weights.mem":
            write_words(out / name, loaded[name], bits // 4)

    dense = loaded["layer5_dense_weights.mem"]
    # The original file is class-major: dense[class * FEATURES + feature].
    # The packed ROM is feature-major; byte lane 0 belongs to class 0, etc.
    packed: list[int] = []
    for feature in range(2304):
        word = 0
        for cls in range(4):
            word |= (dense[cls * 2304 + feature] & 0xFF) << (8 * cls)
        packed.append(word)
    write_words(out / "layer5_dense_weights_packed.mem", packed, 8)

    print(f"Validated {len(EXPECTED)} source memories.")
    print(f"Wrote {len(packed)} packed dense words to {out / 'layer5_dense_weights_packed.mem'}.")


if __name__ == "__main__":
    main()
