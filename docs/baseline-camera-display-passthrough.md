# v0.1 Camera-to-Display Baseline

## Objective

Freeze the latest verified hardware I/O baseline before integrating grayscale and edge-detection stages.

## Hardware Setup

- Board: Efinix Titanium Ti60F225, C4 timing model
- Camera: OV5640 module using the verified 1280x720 RGB565 initialization table
- Display: HDMI-compatible Waveshare display path
- Tool: Efinity 2026.1.132

## Verified Data Path

```text
OV5640 DVP -> RGB565 capture -> 4x3 spatial subsampling
            -> 320x240 dual-bank frame buffer -> display overlay
            -> TMDS encoder -> Efinix LVDS TX -> display
```

The input camera frame is 1280x720. Even columns and every third row are retained, producing a 320x240 image centered at display coordinates x=80..399 and y=200..439 in the 480x640 timing. Incomplete frames are rejected; the display changes frame-buffer banks only at a display frame boundary.

## Clocks and Reset

The recorded project uses a 24 MHz board reference, a 96 MHz system clock, a 16 MHz camera XCLK, a 42 MHz display pixel clock, and a 210 MHz LVDS serializer clock. Camera PCLK, system/XCLK, and display clocks are treated as separate clock domains. Crossings use dual-clock RAM or explicit synchronizers. Reset release is synchronized per domain.

## Important RTL Modules

- `rtl/phase_camera_display_official_waveshare.sv` — top-level module
- `rtl/camera_frontend.sv` — camera power, configuration, and capture integration
- `rtl/dvp_rgb565_capture.sv` — DVP byte pairing and frame boundaries
- `rtl/packed_pingpong_framebuffer.sv` and `rtl/frame_ram20.sv` — dual-bank frame storage
- `rtl/video_timing_gen.sv` — display timing
- `rtl/display_diagnostic_overlay.sv` — diagnostic background and camera window
- `rtl/tmds_encoder.sv` — TMDS symbols before the Efinix LVDS serializer
- `rtl/vendor/I2C_OV5640_1280720_Config.v` — OV5640 register initialization

## Constraints and Efinity Configuration

The rebuild inputs are:

- `efinity/ti60f225_camera_display_baseline.xml`
- `efinity/ti60f225_camera_display_baseline.peri.xml`
- `constraints/ti60f225_camera_display_baseline.sdc`
- all RTL files listed by the project XML

The periphery configuration contains the Ti60F225 pin assignments, PLLs, camera DVP inputs, and HDMI LVDS TX resources. The SDC contains clock definitions, DVP input delays, and asynchronous clock groups. The exported periphery file has its machine-specific project location replaced with a relative location; all design-file references in the exported project XML are repository-relative.

## Build Method

Open `efinity/ti60f225_camera_display_baseline.xml` with Efinity 2026.1.132 and run the normal compile flow. The historical source project used a local Efinity installation path in its helper script; this export intentionally does not commit that machine-specific path. Set the Efinity executable location in the local build environment or run the flow from the Efinity GUI.

The testbench sources are under `sim/tb/`. The original verification logs and generated binaries are not part of the release because they contain machine paths and tool-generated state.

## Hardware Test and Result

The existing acceptance record reports a real-board camera-to-display PASS using the capture-fix bitstream. The observed path was a live OV5640 image displayed in the central 320x240 window with the diagnostic background outside it. The release bitstream is included at `releases/v0.1-camera-display-baseline/bitstream/ti60f225_camera_display_baseline.bit`.

## Known Limitations

- The baseline is not an edge detector yet.
- The display timing is the verified 480x640 mode, not a claim of a generic 640x480 monitor mode.
- No board programming was performed during this cleanup.
- The release preserves the recorded user hardware result; it does not add new electrical measurements or runtime-duration claims.
- The Efinity tool and device support remain proprietary external dependencies.

## Next Integration Point

Insert RGB565-to-grayscale processing between `camera_frontend` and `packed_pingpong_framebuffer` in a new project copy. Any added pipeline latency must be applied equally to pixel data, valid, coordinates, start-of-frame, frame-end, and frame-good signals.

