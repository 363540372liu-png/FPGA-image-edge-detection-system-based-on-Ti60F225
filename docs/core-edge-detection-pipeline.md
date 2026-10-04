# Core Real-Time Edge Detection Pipeline

## Objective

This milestone preserves the current hardware-accepted Ti60F225 image pipeline:
camera capture, grayscale conversion, streaming Sobel processing, thresholded
edge output, grayscale/edge preview composition, and HDMI display. The release
also preserves the stability fix that keeps capture, pending, and display
frame ownership separate.

## Hardware Platform

- FPGA: Efinix Titanium Ti60F225, C4 timing model
- Camera: OV5640, configured for 640x480 RGB565
- Display: the accepted 640x480 HDMI-compatible Waveshare/LVDS-TMDS path
- Toolchain: Efinity 2026.1.132
- Pixel clock: 25.2 MHz; serializer clock: approximately 126 MHz

## Actual Architecture

```text
OV5640 DVP
  -> camera_frontend / dvp_rgb565_capture
  -> rgb565_to_gray8 (8-bit grayscale stream)
  -> line_delay_ram8 x2 / gray_window_3x3
  -> sobel_threshold (signed Gx/Gy and strict threshold)
  -> edge_full_frame_stream
  -> edge_preview_2x2_or (binary edge preview)
  -> preview_pair_aligner + split_triple_framebuffer
  -> split_preview_output / threshold and counter overlays
  -> tmds_encoder + LVDS serializer to display
```

The top-level module is `phase_camera_display_official_waveshare` in
`rtl/core_pipeline/phase_camera_display_official_waveshare.sv`.

## Camera Input

`camera_frontend` combines `dvp_rgb565_capture`, `camera_frame_monitor`,
`camera_power_seq`, `sccb_master`, and `ov5640_init_controller`. The active
camera table is `I2C_OV5640_RGB565_Config_Official.v` together with
`I2C_OV5640_640480_Config.sv`. The capture monitor marks a frame good only when
the expected frame completion and byte/size checks pass.

## Grayscale Conversion

`rgb565_to_gray8` expands RGB565 to 8-bit channels and computes the exact
integer approximation:

```text
Y = (77*R8 + 150*G8 + 29*B8 + 128) >> 8
```

The multipliers are implemented as shift/add networks. Stream controls and
coordinates are registered with the one-cycle grayscale data latency.

## Line Buffer and 3x3 Window

`gray_window_3x3` uses two `line_delay_ram8` instances and three horizontal
shift chains. It emits a valid window for centers `(x-1,y-1)` after the first
two rows and the first three pixels of the next row are available. Valid gaps
pause the accepted-pixel state. The outer image border is not passed as an
interior window; `edge_full_frame_stream` emits those border positions as zero.

## Sobel Operator

`sobel_threshold` implements the standard signed kernels. Its RTL equations
are equivalent to:

```text
Gx = (p02-p00) + 2*(p12-p10) + (p22-p20)
Gy = (p20-p00) + 2*(p21-p01) + (p22-p02)
```

Thus the horizontal and vertical kernels are the standard 3x3 Sobel pair.
The gradients are registered and coordinate-aligned with the valid stream.

## Gradient Magnitude and Threshold

The magnitude is the unscaled approximation `abs(Gx) + abs(Gy)`, accumulated
before output truncation. The comparison is strict: `magnitude > threshold`.
The default threshold is 128. In this accepted build, `threshold_control`
starts at 128 and changes it by 16 through debounced active-low buttons,
saturating at 0 and 2040; both buttons restore 128 after the specified hold.
`threshold_bus_cdc` transfers the stable request to the camera-pixel domain,
and the active threshold is latched per frame. The edge pixel is binary
RGB565: black `0x0000` or white `0xFFFF`.

## Video Output and Stability

`edge_preview_2x2_or` reduces the full edge image to 320x240, while
`gray_preview_2x2_mean` generates the grayscale half of the split view.
`preview_pair_aligner` aligns both previews. `split_triple_framebuffer`
maintains display, pending, and capture ownership and commits only at display
frame boundaries. `video_timing_gen`, `split_preview_output`,
`tmds_encoder`, and the embedded Efinity periphery provide the unchanged HDMI
timing and accepted landscape mapping.

## Pipeline Timing

The grayscale stage adds one registered cycle. The 3x3 window requires two
previous rows and uses accepted-pixel valid gating. The Sobel arithmetic adds
one registered cycle after a valid window. Frame and line markers travel with
the stream; frame ownership crosses clock domains through explicit bundled
data/toggle and snapshot CDC logic.

## Hardware Verification

The 2026-10-02 acceptance record reports that the user observed matching
orientation and field of view for grayscale and binary-edge views, working
threshold buttons, a normal picture during the post-fix test, and no increase
in capture-bad or buffer-busy-drop counters. These are user observations; no
unreported duration or frame-rate claim is added here. Offline regressions,
Efinity synthesis, place/route, timing, CDC, and bitstream generation are
archived with the release.

## Known Limitations

- Threshold is global and frame-latched rather than adaptive.
- The threshold character readout is known to be visually abnormal, although
  it is non-blocking and was intentionally preserved.
- The design is sensitive to camera noise and has no denoising stage.
- Thin edges can become up to one preview pixel thicker through 2x2 OR.
- Exact frame rate and unreported long-duration behavior are not claimed.

## Next Steps

Possible future work includes threshold-quality tuning, optional filtering,
edge visualization refinement, quantitative golden-model comparisons, and a
final competition demonstration. None of these are part of this release.
