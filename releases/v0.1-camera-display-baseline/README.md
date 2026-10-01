# v0.1 Camera-to-Display Baseline

Status: **PASS**

- Board: Efinix Titanium Ti60F225
- Camera: OV5640
- Input: 1280x720 RGB565, reduced to 320x240 for display
- Display: verified 480x640 HDMI-compatible timing

Verified pipeline:

```text
OV5640 Camera -> Camera Capture -> FPGA Pixel/Data Path -> Display Output
```

Result: the recorded real-board test displayed the live camera image. This is the stable hardware I/O baseline for later image-processing integration. The included bitstream is the capture-fix build; verify its SHA-256 before programming.

