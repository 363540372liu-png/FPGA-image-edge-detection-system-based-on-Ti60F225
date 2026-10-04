# Acceptance record

## Accepted artifact

- Project snapshot: `project_snapshot/`
- Efinity project:
  `project_snapshot/phase_camera_display_640x480_stability_fix.xml`
- Bitstream:
  `project_snapshot/bitstream/phase_camera_display_640x480_stability_fix.bit`
- SHA-256:
  `FE4D0B0FC98C6167C1D798F4222D78E300689B10A8867A6C9FE7449D720F82AA`

This identity is supported by the bitstream itself, the original
`bitstream/SHA256.txt`, and `reports/build_command.txt`. The accepted artifact
is not the earlier `phase_camera_display_640x480_stability` diagnostic build.

## User-confirmed hardware behavior

The user reported that:

- grayscale and edge views have consistent orientation and field of view, and
  the displayed proportions are correct;
- threshold adjustment through the two buttons operates normally;
- during the post-fix test, video remained normal;
- the capture-bad and buffer-busy-drop counters did not increase.

No test duration, precise frame rate, exact counter values, or additional
measurements were provided. None are added by this record.

## Offline-verified configuration

- OV5640 capture: 640x480 RGB565;
- algorithm input: full 640x480 stream;
- grayscale: 8-bit integer conversion already covered by exhaustive testing;
- Sobel: 3x3, `abs(Gx) + abs(Gy)`, strict configurable threshold;
- preview composition: 320x240 grayscale mean and 320x240 2x2-OR edge data in
  a packed 9-bit-per-location triple buffer;
- HDMI: 640x480 timing, 25.2 MHz pixel clock and approximately 126 MHz 5x
  serializer clock;
- display mapping: preserved accepted landscape rotation/scale compensation;
- frame ownership: display bank, pending bank, and capture bank remain mutually
  exclusive, with display switching only at HDMI frame boundaries;
- diagnostic counter transfer: coherent snapshot CDC, not direct sampling of
  changing multi-bit counters.

Implementation evidence:

- RAM10: 229/256;
- FF: 3422;
- LUT: 6858;
- DSP/multiplier: 0;
- worst reported setup slack: +2.466 ns;
- worst reported hold slack: +0.034 ns;
- synchronizer report: no warnings;
- Efinity error log: empty.

## Preservation statement

The snapshot copies the successful project RTL, periphery, SDC, scripts,
testbenches, software references, vectors, reports, and bitstream without
functional edits. No new synthesis or bitstream generation was performed for
the archival copy. File integrity is recorded in `FILE_MANIFEST.tsv` and
`KEY_SHA256.txt`.

## Outstanding material and limitations

- Demonstration video: pending user delivery.
- Threshold character readout issue: known, non-blocking, intentionally not
  repaired in this archive.
- Exact camera frame rate and unreported long-duration behavior: not measured
  or claimed here.
