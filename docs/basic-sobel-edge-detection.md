# Basic 640x480 Sobel Edge Detection

This document records the second repository milestone. It is a separate copy
of the accepted 640x480 grayscale camera/display project; the v0.1 release is
not overwritten.

## Data path

```text
OV5640 RGB565 -> grayscale -> two-line 3x3 window -> signed Sobel
               -> strict threshold -> full 640x480 edge frame
               -> 2x2 OR -> 320x240 packed framebuffer -> HDMI display
```

The default output is black background with white edges. The outermost row and
column are forced to zero. The threshold is `abs(Gx) + abs(Gy) > 128`, with no
scaling before comparison. The 2x2 OR preview intentionally favors retaining
thin edges over point-sampling them.

## Verification and implementation

The archived acceptance report records synthetic patterns, random and local
real-image 640x480 comparisons, gap/recovery tests, integrated framebuffer
checks, inherited camera/display regressions, and top-level syntax checks.
Efinity 2026.1.132 completed map, interface generation, place/route, timing,
and bitstream generation for Ti60F225 C4.

Key final figures are 242/256 RAM10 blocks, 0/160 DSP blocks, 8,620/60,800
XLR placement, and positive setup/hold slack on all reported relationships.
The final bitstream is in the release directory with its SHA-256 manifest.

## Physical-test boundary

No JTAG or flash programming was performed as part of this repository export.
The user should load the candidate using the already accepted camera and
clock/display setup, then check image orientation, live edge updates, blank
screen behavior, gross shifts, excessive noise, and the error LED. Visual
success does not establish frame rate or long-run no-drop behavior.

## Rebuild inputs

- Efinity project: `efinity/sobel/phase_camera_display_640x480_sobel.xml`
- Constraints: `efinity/sobel/phase_camera_display_640x480_sobel.sdc`
- Milestone RTL: `rtl/sobel/`
- Testbenches and golden vectors: `sim/sobel/`
- Archived reports and acceptance record: `releases/v0.2-basic-sobel-edge-detection/`

The XML retains the original Efinity project name and top module. Its source
paths are relative to this repository so the v0.2 tree is portable and does
not depend on the original working-directory path.
