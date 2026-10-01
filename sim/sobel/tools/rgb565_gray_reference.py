#!/usr/bin/env python3
"""Generate and self-check the exhaustive RGB565-to-gray8 reference vector."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def expand_rgb565(pixel: int) -> tuple[int, int, int]:
    r5 = (pixel >> 11) & 0x1F
    g6 = (pixel >> 5) & 0x3F
    b5 = pixel & 0x1F
    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g6 << 2) | (g6 >> 4)
    b8 = (b5 << 3) | (b5 >> 2)
    return r8, g8, b8


def gray8(pixel: int) -> int:
    r8, g8, b8 = expand_rgb565(pixel)
    return (77 * r8 + 150 * g8 + 29 * b8 + 128) >> 8


def shift_add_gray8(pixel: int) -> int:
    r8, g8, b8 = expand_rgb565(pixel)
    r_term = (r8 << 6) + (r8 << 3) + (r8 << 2) + r8
    g_term = (g8 << 7) + (g8 << 4) + (g8 << 2) + (g8 << 1)
    b_term = (b8 << 4) + (b8 << 3) + (b8 << 2) + b8
    return (r_term + g_term + b_term + 128) >> 8


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "vectors"
        / "rgb565_gray_expected.mem",
    )
    args = parser.parse_args()

    values = []
    for pixel in range(1 << 16):
        direct = gray8(pixel)
        shift_add = shift_add_gray8(pixel)
        if direct != shift_add:
            raise AssertionError(
                f"shift/add mismatch at 0x{pixel:04x}: {shift_add} != {direct}"
            )
        if not 0 <= direct <= 255:
            raise AssertionError(f"out-of-range result at 0x{pixel:04x}: {direct}")
        values.append(direct)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    payload = "".join(f"{value:02x}\n" for value in values).encode("ascii")
    args.output.write_bytes(payload)

    anchors = {
        0x0000: 0,
        0xFFFF: 255,
        0xF800: 77,
        0x07E0: 149,
        0x001F: 29,
    }
    for pixel, expected in anchors.items():
        actual = values[pixel]
        if actual != expected:
            raise AssertionError(
                f"anchor mismatch at 0x{pixel:04x}: {actual} != {expected}"
            )

    print(f"PASS: generated and checked all {len(values)} RGB565 values")
    print(f"VECTOR={args.output}")
    print(f"SHA256={hashlib.sha256(payload).hexdigest().upper()}")
    print("ANCHORS=" + ", ".join(f"0x{k:04X}:{v}" for k, v in anchors.items()))


if __name__ == "__main__":
    main()
