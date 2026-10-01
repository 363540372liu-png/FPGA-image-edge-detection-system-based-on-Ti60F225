create_clock -name clk_sys -period 10.416667 [get_ports {clk_sys}]
create_clock -name clk_xclk_24m -period 41.666667 [get_ports {clk_27m}]
create_clock -name clk_display_feedback_24m -period 41.666667 [get_ports {display_feedback_24m}]
create_clock -name clk_pixel_25p2m -period 39.682540 [get_ports {clk_pixel}]
create_clock -name clk_pixel_5x_126m -period 7.936508 \
    -waveform {1.190476 5.158730} [get_ports {clk_pixel_5x}]

# Conservative limit retained from the verified camera-minimal project.
create_clock -name cmos_pclk -period 10.000000 [get_ports {cmos_pclk}]

# Official source-synchronous DVP input window.
set_input_delay -clock_fall -clock cmos_pclk -max 1.191 [get_ports {cmos_data[*]}]
set_input_delay -clock_fall -clock cmos_pclk -min 0.961 [get_ports {cmos_data[*]}]
set_input_delay -clock_fall -clock cmos_pclk -max 1.191 [get_ports {cmos_href}]
set_input_delay -clock_fall -clock cmos_pclk -min 0.961 [get_ports {cmos_href}]
set_input_delay -clock_fall -clock cmos_pclk -max 1.191 [get_ports {cmos_vsync}]
set_input_delay -clock_fall -clock cmos_pclk -min 0.961 [get_ports {cmos_vsync}]

# The camera PCLK, system/XCLK PLL and display PLL are distinct clock domains.
# Crossings are restricted to the dual-clock frame RAM and explicit two-flop
# toggle/status synchronizers. The display PLL is reference-locked to 24 MHz,
# but its phase after lock is not treated as deterministic relative to sys_pll.
set_clock_groups -asynchronous \
    -group [get_clocks {cmos_pclk}] \
    -group [get_clocks {clk_sys clk_xclk_24m}] \
    -group [get_clocks {clk_display_feedback_24m clk_pixel_25p2m clk_pixel_5x_126m}]

# No fabricated board I/O delay is applied to dedicated LVDS serializers.
