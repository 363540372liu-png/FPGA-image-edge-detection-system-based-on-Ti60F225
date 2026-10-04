`timescale 1ns/1ps
module camera_frontend (
    input  logic        clk_sys,
    input  logic        clocks_locked,
    output logic        cmos_sclk,
    input  logic        cmos_sdat_in,
    output logic        cmos_sdat_out,
    output logic        cmos_sdat_oe,
    input  logic        cmos_pclk,
    input  logic        cmos_vsync,
    input  logic        cmos_href,
    input  logic [7:0]  cmos_data,
    output logic        cmos_ctl1_pwdn,
    output logic        cmos_ctl2_out,
    output logic        cmos_ctl2_oe,
    output logic        cmos_ctl3_out,
    output logic        cmos_ctl3_oe,
    output logic        sys_rst_n,
    output logic        pclk_rst_n,
    output logic        chip_id_ok,
    output logic        init_done,
    output logic        init_failed,
    output logic [15:0] pixel,
    output logic        pixel_valid,
    output logic        start_of_frame,
    output logic        frame_end,
    output logic [11:0] pixel_x,
    output logic [11:0] pixel_y,
    output logic        capture_error_pclk,
    output logic [3:0]  capture_error_code_pclk,
    output logic [15:0] last_frame_lines_pclk,
    output logic [31:0] last_frame_pixels_pclk,
    output logic [15:0] last_min_line_pixels_pclk,
    output logic [15:0] last_max_line_pixels_pclk,
    output logic        frame_snapshot_toggle_pclk,
    output logic        frame_good_pclk,
    output logic [31:0] frame_count
);
    // Full merchant-supplied VGA RGB565 operating point.
    localparam int unsigned IMAGE_WIDTH  = 640;
    localparam int unsigned IMAGE_HEIGHT = 480;

    logic init_enable;
    logic txn_start, txn_read, txn_done, txn_ack_error, txn_busy;
    logic [15:0] txn_reg_addr;
    logic [7:0] txn_write_data, txn_read_data;
    logic [8:0] lut_index, lut_size;
    logic [23:0] lut_data;
    logic [15:0] chip_id;
    logic [8:0] failed_index;
    logic [3:0] fail_code;
    logic end_of_line, line_end, odd_byte_error;
    logic [15:0] last_line_pixels;
    logic [31:0] line_error_count, frame_error_count;

    reset_sync u_sys_reset_sync (
        .clk(clk_sys), .arst_n(clocks_locked), .srst_n(sys_rst_n)
    );

    camera_power_seq #(.CLK_HZ(96_000_000)) u_power_seq (
        .clk(clk_sys), .rst_n(sys_rst_n),
        .camera_pwdn(cmos_ctl1_pwdn), .init_enable(init_enable)
    );

    I2C_OV5640_640480_Config u_init_rom (
        .LUT_INDEX(lut_index), .LUT_DATA(lut_data), .LUT_SIZE(lut_size)
    );

    ov5640_init_controller #(
        .CLK_HZ(96_000_000), .INIT_COUNT(312)
    ) u_init_controller (
        .clk(clk_sys), .rst_n(sys_rst_n), .enable(init_enable),
        .txn_start(txn_start), .txn_read(txn_read),
        .txn_reg_addr(txn_reg_addr), .txn_write_data(txn_write_data),
        .txn_done(txn_done), .txn_ack_error(txn_ack_error),
        .txn_read_data(txn_read_data), .chip_id(chip_id),
        .chip_id_ok(chip_id_ok), .init_done(init_done),
        .init_failed(init_failed), .failed_index(failed_index),
        .fail_code(fail_code), .lut_index(lut_index), .lut_data(lut_data)
    );

    sccb_master #(.CLK_HZ(96_000_000), .SCL_HZ(100_000)) u_sccb_master (
        .clk(clk_sys), .rst_n(sys_rst_n), .start(txn_start),
        .read_not_write(txn_read), .reg_addr(txn_reg_addr),
        .write_data(txn_write_data), .read_data(txn_read_data),
        .busy(txn_busy), .done(txn_done), .ack_error(txn_ack_error),
        .scl(cmos_sclk), .sda_i(cmos_sdat_in),
        .sda_o(cmos_sdat_out), .sda_oe(cmos_sdat_oe)
    );

    reset_sync u_pclk_reset_sync (
        .clk(cmos_pclk), .arst_n(sys_rst_n && init_done), .srst_n(pclk_rst_n)
    );

    dvp_rgb565_capture #(
        .ACTIVE_WIDTH(IMAGE_WIDTH), .ACTIVE_HEIGHT(IMAGE_HEIGHT)
    ) u_dvp_capture (
        .pclk(cmos_pclk), .rst_n(pclk_rst_n), .vsync(cmos_vsync),
        .href(cmos_href), .data(cmos_data), .pixel(pixel),
        .pixel_valid(pixel_valid), .start_of_frame(start_of_frame),
        .end_of_line(end_of_line), .line_end(line_end),
        .frame_end(frame_end), .x(pixel_x), .y(pixel_y),
        .odd_byte_error(odd_byte_error)
    );

    camera_frame_monitor #(
        .ACTIVE_WIDTH(IMAGE_WIDTH), .ACTIVE_HEIGHT(IMAGE_HEIGHT)
    ) u_frame_monitor (
        .pclk(cmos_pclk), .rst_n(pclk_rst_n), .pixel_valid(pixel_valid),
        .start_of_frame(start_of_frame), .line_end(line_end),
        .frame_end(frame_end), .odd_byte_error(odd_byte_error),
        .frame_count(frame_count), .last_line_pixels(last_line_pixels),
        .last_frame_lines(last_frame_lines_pclk),
        .last_frame_pixels(last_frame_pixels_pclk),
        .last_min_line_pixels(last_min_line_pixels_pclk),
        .last_max_line_pixels(last_max_line_pixels_pclk),
        .last_error_code(capture_error_code_pclk),
        .frame_good(frame_good_pclk),
        .snapshot_toggle(frame_snapshot_toggle_pclk),
        .line_error_count(line_error_count), .frame_error_count(frame_error_count)
    );

    // Report the most recently completed admitted frame. A discarded startup
    // fragment is not an error, and a later good frame clears a prior bad one.
    assign capture_error_pclk = |capture_error_code_pclk;

    // Rev7.0: CTL1 is PWDN. FREX and STRO remain high impedance.
    assign cmos_ctl2_out = 1'b0;
    assign cmos_ctl2_oe  = 1'b0;
    assign cmos_ctl3_out = 1'b0;
    assign cmos_ctl3_oe  = 1'b0;
endmodule
