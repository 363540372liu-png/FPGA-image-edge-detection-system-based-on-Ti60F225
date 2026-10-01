# Sobel Phase Offline Acceptance Report

Status: **offline verification complete; physical verification pending user**

## Baseline protection

The project was created as an independent copy of
`phase_camera_display_640x480_gray`. The accepted camera configuration, PLLs,
pin/periphery definition, SDC, 640x480 HDMI timing, TMDS path, reset structure,
packed double buffer, and accepted landscape mapping were retained. A pinout
CSV comparison found only generated date/project-name differences. The source
grayscale bitstream still hashes to
`71916458DB1322EAE324E9C74D08ECD11DEF1A43591E435ABFDE0331F750AC3F`.

## References reviewed

- Local Raspberry Pi/FPGA work:
  `E:\codex\fgpa\rasberry\fpga-edge-step1`
  (`window_3x3.sv`, `sobel_core.sv`, full-frame tests, Python references, and
  `inputs\real\scene_input.png`). These files informed test structure and
  expected behavior; incompatible old threshold and valid semantics were not
  copied.
- Local official Ti60 image pipeline:
  `07-FPGA_HDL_Image-2023.2\04-1_Ti60_SC2210_HDMI_1080P60\src\isp\VIP_Matrix_Generate_3X3_8Bit.v`
  and `Line_Shift_RAM_8Bit.v`. They were used only as an architectural check
  for line-RAM organization; proprietary source was not copied.
- User-specified third-party architecture reference at commit
  `b90dd15b2f87bf7c04017ba89a294f477e37ceeb` was not imported. None of its
  RTL, constraints, clock modules, or board display logic is present here.

## Added or modified implementation

- `rtl/line_delay_ram8.sv`: explicit one-block RAM10 accepted-pixel delay.
- `rtl/gray_window_3x3.sv`: two line delays, column shifts, coordinate and
  valid alignment; no RAM-clearing reset.
- `rtl/sobel_threshold.sv`: signed Sobel arithmetic, unscaled magnitude, and
  strict configurable threshold (delivered value 128).
- `rtl/edge_full_frame_stream.sv`: complete 640x480 border-aware scheduler,
  bad-frame rejection, and sticky FIFO/coordinate/queue diagnostics.
- `rtl/edge_preview_2x2_or.sv`: 2x2 OR reduction to 320x240 binary RGB565.
- `rtl/phase_camera_display_official_waveshare.sv`: integrates the algorithm
  before preview reduction; accepted HDMI/read mapping is unchanged.
- Project XML, build script, one-command simulation script, and self-checking
  testbenches were updated in this independent directory.

The initial scheduler FIFO was conservatively 1296 entries. Efinity correctly
warned that its asynchronous read forced 25,920 bits into logic storage. Full
random, real-image, gap, and recovery tests all measured a maximum FIFO level
of one, so the final implementation uses 16 entries plus sticky overflow
detection. This reduced the mapped design from roughly 27k FF/27k LUT to the
final resource figures below without relaxing any correctness check.

## Automatic verification completed

The independent Python reference uses the required grayscale expansion,
unscaled Sobel kernels, strict `G > 128`, zero outer border, and 2x2 OR preview.
It covers constant, horizontal/vertical steps, diagonal, checkerboard,
fixed-seed random data, a full 640x480 random frame, and the local real image.

Representative expected results:

- Constant 8x6: zero edge pixels.
- Vertical 8x6 step at source x=4: white centers at x=3 and x=4 for y=1..4
  (8 full-resolution edge pixels; 6 white preview blocks).
- Horizontal 8x6 step at source y=3: white centers at y=2 and y=3 for x=1..6
  (12 full-resolution edge pixels; 4 white preview blocks).
- A magnitude of exactly 128 is black; 132 is white, including negative-Gx
  absolute-value coverage.

Completed checks include:

- Numbered 3x3 windows, center coordinates, row changes, valid gaps, frame
  restart, and reset recovery.
- Signed Sobel arithmetic and the strict threshold boundary.
- Partial-frame rejection followed by two complete frames.
- Per-pixel comparison for all synthetic cases.
- Full 640x480 fixed-random comparison: 307,200 full outputs and 76,800 OR
  preview outputs; observed scheduler FIFO maximum was one.
- Full 640x480 local-real-image comparison with the same counts.
- Integrated commit: 307,200 source pixels -> 76,800 preview pixels -> 15,360
  packed 80-bit writes -> one display-side frame acceptance.
- Existing RGB565-gray exhaustive 65,536-input test, DVP capture/recovery,
  snapshot CDC, packed RAM, 2x upscale, accepted landscape rotation, clean
  preview, 640x480 timing, and official OV5640 register-table regressions.
- Default edge top, diagnostic-overlay top, and grayscale-fallback top syntax.

Master log:
`sim\run_sim_master_fifo16.log`

Python manifest:
`vectors\sobel\manifest.json`

## Efinity implementation result

- Map: PASS
- Interface generation: PASS
- Place/route: PASS
- Bitstream generation: PASS
- CDC report: no synchronizer warnings
- Errors: none
- Device/timing model: Ti60F225 C4
- Total XLR placement: 8,620/60,800 (14.18%)
- RAM10: 242/256 (94.53%), 14 remaining
- DSP: 0/160
- Mapped primitives: 6,688 LUT4, 1,829 FF, 836 adders

Final timing slacks are positive:

| Relationship | Setup slack | Hold slack |
|---|---:|---:|
| `cmos_pclk` full-cycle | 5.262 ns | 0.080 ns |
| DVP falling-input to rising-capture | 2.305 ns | 5.293 ns |
| `clk_sys` | 5.795 ns | 0.093 ns |
| `clk_pixel_25p2m` | 31.054 ns | 0.099 ns |
| `clk_pixel_5x_126m` | 7.537 ns | 0.115 ns |
| `clk_display_feedback_24m` | 41.267 ns | 0.109 ns |

No broad false path was added. The existing asynchronous clock groups cover
the camera, system/XCLK, and display domains, while frame RAM and explicit
synchronizers implement the crossings.

Warnings retained and reviewed:

- Two 320-bit asynchronous-read arrays (scheduler FIFO and OR-row state) map
  to logic instead of RAM. Their final cost is included above.
- `wr_x/wr_y` are optimized from the framebuffer because the delivered edge
  stream is already 320x240 and uses step 1; coordinate/order checking occurs
  upstream and remains covered by simulation.
- Fabric ports `clk_lvds_1x`, `clk_27m`, `cmos_ctl2_in`, and `cmos_ctl3_in`
  are unused by the top RTL. The inherited periphery clock/serializer and
  camera-control configuration is unchanged from the accepted baseline.
- Icarus reports that constant bit selects in several inherited `always_*`
  blocks are handled by including all bits in the sensitivity set, and that
  the vendor RAM model has no explicit timescale. These are simulator-model
  diagnostics rather than failed comparisons; Efinity does not report them.

Final reports are under `reports\`; `build_console_final.log` is the final
clean-build console log. Earlier console logs document development builds and
are not the delivered report set.

## Candidate and physical test

Bitstream:
`E:\codex\fgpa\Efinity test\phase_camera_display_640x480_sobel\bitstream\phase_camera_display_640x480_sobel.bit`

Last write time: `2026-10-01 23:38:45 +08:00`

SHA-256:
`6952E2A1DE00E472C017B02AFB04F0B06C498531CBA2D065C5060783B9271DE9`

No JTAG download or Flash programming was performed by Codex. For the physical
test, keep the accepted camera connection and clockwise-rotated screen
orientation, load the candidate through JTAG, and check at most these items:

1. A clean black-background/white-edge landscape image appears after the first
   complete camera frame, with the already accepted direction and proportions.
2. Object and camera motion causes corresponding edges to update rather than
   freeze; note any persistent blank screen or gross one-row/one-column shift.
3. Report obvious missing thin lines, excessive all-white noise, or an active
   error LED. Do not infer frame rate or no-drop operation from visual success.

Physical screen compatibility, live scene quality, actual frame rate, and
long-run/no-drop behavior remain outside offline verification. The inherited
busy-buffer dropped-frame counter and diagnostic build option remain present.
