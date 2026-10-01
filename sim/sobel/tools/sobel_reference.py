#!/usr/bin/env python3
"""Generate deterministic grayscale/Sobel vectors for the Ti60 edge pipeline.

The arithmetic is intentionally independent from the RTL implementation:
  * RGB565 expansion follows the accepted grayscale-stage rule.
  * Sobel uses signed int32 convolution and unscaled abs(Gx)+abs(Gy).
  * The threshold comparison is strict (> 128 by default).
  * The outermost output border is zero.
  * The 320x240 display preview is a non-overlapping 2x2 logical OR.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps


DEFAULT_REAL_IMAGE = Path(
    r"E:\codex\fgpa\rasberry\fpga-edge-step1\inputs\real\scene_input.png"
)


def rgb888_to_gray_via_rgb565(rgb: np.ndarray) -> np.ndarray:
    """Quantize to RGB565, expand to RGB888, then apply the fixed gray rule."""
    rgb_u16 = rgb.astype(np.uint16)
    r5 = rgb_u16[..., 0] >> 3
    g6 = rgb_u16[..., 1] >> 2
    b5 = rgb_u16[..., 2] >> 3
    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g6 << 2) | (g6 >> 4)
    b8 = (b5 << 3) | (b5 >> 2)
    weighted = 77 * r8.astype(np.uint32)
    weighted += 150 * g8.astype(np.uint32)
    weighted += 29 * b8.astype(np.uint32)
    return ((weighted + 128) >> 8).astype(np.uint8)


def sobel_reference(gray: np.ndarray, threshold: int) -> tuple[np.ndarray, ...]:
    """Return Gx, Gy, magnitude, and full-size binary edge image."""
    if gray.ndim != 2 or gray.shape[0] < 3 or gray.shape[1] < 3:
        raise ValueError("gray image must be a two-dimensional array of at least 3x3")
    source = gray.astype(np.int32)
    p00, p01, p02 = source[:-2, :-2], source[:-2, 1:-1], source[:-2, 2:]
    p10, p12 = source[1:-1, :-2], source[1:-1, 2:]
    p20, p21, p22 = source[2:, :-2], source[2:, 1:-1], source[2:, 2:]
    gx = (p02 - p00) + 2 * (p12 - p10) + (p22 - p20)
    gy = (p20 - p00) + 2 * (p21 - p01) + (p22 - p02)
    magnitude = np.abs(gx) + np.abs(gy)
    edge = np.zeros_like(gray, dtype=np.uint8)
    edge[1:-1, 1:-1] = np.where(magnitude > threshold, 255, 0).astype(np.uint8)
    return gx, gy, magnitude, edge


def preview_or_2x2(edge: np.ndarray) -> np.ndarray:
    """Collapse each non-overlapping 2x2 edge block using logical OR."""
    height, width = edge.shape
    if (width % 2) or (height % 2):
        raise ValueError("2x2 preview requires even width and height")
    blocks = edge.reshape(height // 2, 2, width // 2, 2)
    return np.where(np.any(blocks != 0, axis=(1, 3)), 255, 0).astype(np.uint8)


def write_mem(path: Path, data: np.ndarray) -> None:
    flat = data.reshape(-1)
    path.write_text("".join(f"{int(value):02x}\n" for value in flat), encoding="ascii")


def write_case(root: Path, name: str, gray: np.ndarray, threshold: int) -> dict[str, object]:
    case_dir = root / name
    case_dir.mkdir(parents=True, exist_ok=True)
    gx, gy, magnitude, edge = sobel_reference(gray, threshold)
    preview = preview_or_2x2(edge)

    if np.any(edge[0, :]) or np.any(edge[-1, :]) or np.any(edge[:, 0]) or np.any(edge[:, -1]):
        raise AssertionError(f"{name}: non-zero outer border")
    if int(magnitude.max(initial=0)) > 2040:
        raise AssertionError(f"{name}: Sobel magnitude exceeds 2040")

    write_mem(case_dir / "gray.mem", gray)
    write_mem(case_dir / "edge.mem", edge)
    write_mem(case_dir / "preview.mem", preview)
    np.save(case_dir / "gx.npy", gx)
    np.save(case_dir / "gy.npy", gy)
    np.save(case_dir / "magnitude.npy", magnitude)
    Image.fromarray(gray, mode="L").save(case_dir / "gray.png")
    Image.fromarray(edge, mode="L").save(case_dir / "edge.png")
    Image.fromarray(preview, mode="L").save(case_dir / "preview.png")

    digest = hashlib.sha256(edge.tobytes()).hexdigest().upper()
    return {
        "name": name,
        "width": int(gray.shape[1]),
        "height": int(gray.shape[0]),
        "input_pixels": int(gray.size),
        "interior_windows": int((gray.shape[1] - 2) * (gray.shape[0] - 2)),
        "edge_pixels": int(np.count_nonzero(edge)),
        "preview_pixels": int(preview.size),
        "preview_white_pixels": int(np.count_nonzero(preview)),
        "max_magnitude": int(magnitude.max(initial=0)),
        "edge_sha256": digest,
    }


def make_cases(real_image: Path) -> list[tuple[str, np.ndarray]]:
    cases: list[tuple[str, np.ndarray]] = []
    cases.append(("constant_8x6", np.full((6, 8), 73, dtype=np.uint8)))

    vertical = np.zeros((6, 8), dtype=np.uint8)
    vertical[:, 4:] = 255
    cases.append(("vertical_step_8x6", vertical))

    horizontal = np.zeros((6, 8), dtype=np.uint8)
    horizontal[3:, :] = 255
    cases.append(("horizontal_step_8x6", horizontal))

    diagonal = np.fromfunction(
        lambda y, x: np.where(x >= y, 230, 15), (8, 8), dtype=int
    ).astype(np.uint8)
    cases.append(("diagonal_8x8", diagonal))

    checker = np.fromfunction(
        lambda y, x: ((x + y) & 1) * 255, (8, 8), dtype=int
    ).astype(np.uint8)
    cases.append(("checker_8x8", checker))

    rng = np.random.default_rng(20261001)
    cases.append(("random_18x14", rng.integers(0, 256, (14, 18), dtype=np.uint8)))
    cases.append(("random_640x480", rng.integers(0, 256, (480, 640), dtype=np.uint8)))

    if not real_image.is_file():
        raise FileNotFoundError(f"required local real image not found: {real_image}")
    with Image.open(real_image) as image:
        rgb = ImageOps.fit(image.convert("RGB"), (640, 480), method=Image.Resampling.LANCZOS)
        real_gray = rgb888_to_gray_via_rgb565(np.asarray(rgb, dtype=np.uint8))
    cases.append(("real_scene_640x480", real_gray))
    return cases


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--real-image", type=Path, default=DEFAULT_REAL_IMAGE)
    parser.add_argument("--threshold", type=int, default=128)
    args = parser.parse_args()
    if not 0 <= args.threshold <= 2040:
        raise ValueError("threshold must be in the unscaled Sobel range 0..2040")

    args.output.mkdir(parents=True, exist_ok=True)
    reports = [write_case(args.output, name, gray, args.threshold)
               for name, gray in make_cases(args.real_image)]
    manifest = {
        "reference": "unscaled abs(Gx)+abs(Gy), strict greater-than threshold",
        "threshold": args.threshold,
        "border": "outermost row and column forced to zero",
        "preview": "non-overlapping 2x2 logical OR",
        "real_image_source": str(args.real_image.resolve()),
        "cases": reports,
    }
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )

    for report in reports:
        print(
            f"{report['name']}: {report['width']}x{report['height']}, "
            f"windows={report['interior_windows']}, edge_white={report['edge_pixels']}, "
            f"preview_white={report['preview_white_pixels']}, "
            f"max_magnitude={report['max_magnitude']}"
        )
    print("PASS sobel_reference: deterministic vectors and invariants generated")


if __name__ == "__main__":
    main()
