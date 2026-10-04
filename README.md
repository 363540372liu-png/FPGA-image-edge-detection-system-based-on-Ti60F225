# FPGA Image Edge Detection System Based on Ti60F225

## Overview

This project is a real-time FPGA image-processing platform for the Efinix Titanium Ti60F225. The first release freezes the verified camera-to-display hardware baseline before image-processing stages are added.

Target pipeline:

```text
OV5640 Camera -> RGB -> Grayscale -> 3x3 Window / Line Buffer
              -> Sobel -> Threshold -> Edge Output -> Display
```

## Hardware

- Efinix Titanium Ti60F225, C4 timing model
- OV5640 camera module
- HDMI-compatible display path using the verified Waveshare display timing
- Efinity 2026.1.132

## Current Status

| Stage | Status |
|---|---|
| Board bring-up | PASS |
| Clock / PLL verification | PASS |
| OV5640 camera input | PASS |
| Display output | PASS |
| Camera-to-display passthrough | PASS |
| RGB to grayscale | PASS |
| 3x3 line buffer | PASS |
| Sobel edge detection | PASS |
| Thresholded edge output | PASS |
| Core real-time edge pipeline | PASS |
| Quality optimization | Planned |
| Python golden-model comparison | PASS offline; quantitative extension planned |
| Final competition demonstration | In Progress |

## Current Baseline

`v0.1-camera-display-baseline` preserves the user-verified Ti60F225 camera-to-display path. The OV5640 is configured for 1280x720 RGB565, sampled to 320x240, and shown in the center of a 480x640 display frame. The release bitstream is the capture-fix build with SHA-256 recorded in the release manifest.

The hardware PASS is based on the existing user acceptance record. The release process did not reprogram the board or alter the verified RTL.

## Architecture

```text
OV5640 DVP
  -> camera_frontend / RGB565 capture and frame checks
  -> rgb565_to_gray8
  -> two line buffers / gray_window_3x3
  -> sobel_threshold: signed Gx/Gy -> abs(Gx)+abs(Gy) -> threshold
  -> full-frame edge scheduler -> 2x2 OR binary preview
  -> grayscale mean + preview aligner
  -> split triple framebuffer / frame counters / overlays
  -> TMDS encoding -> HDMI-compatible display
```

## Repository Structure

- `rtl/` — verified RTL, including the OV5640 configuration table
- `constraints/` — clock definitions, input timing, and clock-domain constraints
- `efinity/` — Efinity project and Interface Designer configuration
- `sim/` — source testbenches and the simulation entry script
- `docs/` — English baseline and reproducibility documentation
- `releases/` — frozen milestone artifacts and checksums

## Development Roadmap

1. RGB-to-grayscale
2. Streaming interface normalization
3. Line buffer / 3x3 window
4. Sobel operator
5. Threshold
6. Python golden model versus RTL verification
7. Hardware integration
8. Real-time edge-detection demonstration

Future algorithm work must start from a copy of this frozen baseline and must not modify the release RTL in place.

## Verification

The baseline RTL passed the recorded simulation regressions and the Efinity 2026.1 synthesis, interface generation, place-and-route, timing, and bitstream-generation flow. The recorded user hardware test passed camera-to-display output on the real Ti60F225 board. See [the baseline record](docs/baseline-camera-display-passthrough.md) for scope, limitations, clocks, resources, and rebuild notes.

## Latest Milestone

`v0.3-core-pipeline` preserves the user-accepted 640x480 core pipeline,
including the split grayscale/binary-edge view, debounced threshold buttons,
coherent counters, and triple-buffer frame ownership fix. See [the core pipeline
document](docs/core-edge-detection-pipeline.md) and [the v0.3 acceptance
record](releases/v0.3-core-pipeline/acceptance-record.md).

The delivered bitstream is `ti60f225_edge_detection_core.bit` with SHA-256
`FE4D0B0FC98C6167C1D798F4222D78E300689B10A8867A6C9FE7449D720F82AA`.
The acceptance record preserves the boundary between user-observed hardware
behavior and offline-only measurements.
