`timescale 1ns/1ps
module phase_camera_display_official_waveshare (
    input  logic        clk_sys,
    input  logic [1:0]  key_data,
    input  logic        clk_lvds_1x,
    input  logic        clk_27m,
    input  logic        sys_pll_lock,
    input  logic        lvds_pll_lock,
    output logic        sys_pll_rstn_o,
    output logic        lvds_pll_rstn_o,

    input  logic        clk_pixel,
    input  logic        clk_pixel_5x,
    input  logic        display_feedback_24m,
    input  logic        display_pll_lock,
    output logic        display_pll_rstn_o,

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
    input  logic        cmos_ctl2_in,
    output logic        cmos_ctl3_out,
    output logic        cmos_ctl3_oe,
    input  logic        cmos_ctl3_in,

    output logic [9:0]  tmds_lvds_tx_clk_o,
    output logic [9:0]  tmds_lvds_tx_data0,
    output logic [9:0]  tmds_lvds_tx_data1,
    output logic [9:0]  tmds_lvds_tx_data2,
    output logic        tmds_lvds_tx_clk_oe,
    output logic        tmds_lvds_tx_data0_oe,
    output logic        tmds_lvds_tx_data1_oe,
    output logic        tmds_lvds_tx_data2_oe,
    output logic        tmds_lvds_tx_clk_rst,
    output logic        tmds_lvds_tx_data0_rst,
    output logic        tmds_lvds_tx_data1_rst,
    output logic        tmds_lvds_tx_data2_rst,
    output logic [5:0]  led_o
);
`ifdef FORCE_COLOR_BARS
    localparam bit FORCE_COLOR_BARS_BUILD = 1'b1;
`else
    localparam bit FORCE_COLOR_BARS_BUILD = 1'b0;
`endif
`ifdef ENABLE_DIAGNOSTIC_OVERLAY
    localparam bit DIAGNOSTIC_OVERLAY_BUILD = 1'b1;
`else
    localparam bit DIAGNOSTIC_OVERLAY_BUILD = 1'b0;
`endif
`ifdef DISPLAY_GRAY_FULLSCREEN
    localparam int SPLIT_DISPLAY_MODE = 1;
`elsif DISPLAY_EDGE_FULLSCREEN
    localparam int SPLIT_DISPLAY_MODE = 2;
`else
    localparam int SPLIT_DISPLAY_MODE = 0;
`endif

    logic camera_plls_locked;
    logic camera_sys_rst_n, camera_pclk_rst_n;
    logic chip_id_ok, init_done, init_failed;
    logic [15:0] camera_pixel;
    logic camera_pixel_valid, camera_start_of_frame, camera_frame_end;
    logic [11:0] camera_x, camera_y;
    // Full-resolution algorithm insertion point in the camera PCLK domain.
    logic [7:0] gray_pixel8;
    logic [15:0] gray_preview_pixel565;
    logic gray_pixel_valid, gray_start_of_frame, gray_end_of_line;
    logic gray_frame_end, gray_frame_good;
    logic [11:0] gray_x, gray_y;
    logic window_valid;
    logic [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    logic [9:0] window_x;
    logic [8:0] window_y;
    logic sobel_valid, sobel_edge;
    logic signed [10:0] sobel_gx, sobel_gy;
    logic [10:0] sobel_magnitude;
    logic [10:0] requested_threshold_sys, active_threshold_pclk, threshold_pclk;
    logic threshold_request_toggle, threshold_cdc_update;
    logic key_inc_press, key_dec_press, key_default_press;
    logic [9:0] sobel_x;
    logic [8:0] sobel_y;
    logic edge_full_valid, edge_full_bit, edge_full_sof;
    logic edge_full_end, edge_full_good;
    logic [9:0] edge_full_x;
    logic [8:0] edge_full_y;
    logic edge_preview_valid, edge_preview_sof;
    logic edge_preview_end, edge_preview_good;
    logic [15:0] edge_preview_pixel565;
    logic [11:0] edge_preview_x, edge_preview_y;
    logic edge_fifo_overflow, edge_coordinate_error;
    logic edge_frame_queue_overflow, edge_good_queue_overflow;
    logic edge_preview_coordinate_error;
    logic gray_preview_valid, gray_preview_sof;
    logic gray_preview_end, gray_preview_good;
    logic [7:0] gray_preview_value;
    logic [11:0] gray_preview_x, gray_preview_y;
    logic gray_preview_coordinate_error;
    logic paired_valid, paired_edge, paired_sof;
    logic paired_end, paired_good;
    logic [7:0] paired_gray;
    logic [11:0] paired_x, paired_y;
    logic [10:0] paired_threshold;
    logic pair_alignment_error;
    logic [10:0] pair_fifo_max_level;
    logic [4:0] edge_fifo_level, edge_fifo_max_level;
    logic algorithm_error_pclk;
    logic capture_error_pclk, buffer_error_pclk;
    (* syn_keep = "true" *) logic [3:0] capture_error_code_pclk;
    (* syn_keep = "true" *) logic [3:0] buffer_error_code_pclk;
    (* syn_keep = "true" *) logic [31:0] camera_frame_count;
    (* syn_keep = "true" *) logic [31:0] dropped_frame_count;
    (* syn_keep = "true" *) logic [31:0] committed_frame_count_pclk;
    logic [15:0] last_frame_lines_pclk;
    logic [31:0] last_frame_pixels_pclk;
    logic [15:0] last_min_line_pixels_pclk, last_max_line_pixels_pclk;
    logic frame_snapshot_toggle_pclk;
    logic frame_good_pclk;
    logic [31:0] last_sampled_pixels_pclk;
    logic [15:0] last_written_words_pclk;

    logic pixel_reset_n, fast_reset_n, feedback_reset_n, link_ready;
    logic [11:0] display_x, display_y;
    logic display_de, display_hsync, display_vsync, display_frame_tick;
    logic display_de_d, display_hsync_d, display_vsync_d;
    logic [15:0] display_pixel565;
    logic [7:0] display_gray;
    logic display_edge, display_gray_view, display_edge_view;
    logic display_pixel_valid, display_has_frame;
    logic [10:0] displayed_frame_threshold;
    logic frame_committed_pclk;
    (* syn_keep = "true" *) logic [31:0] displayed_frame_count;
    logic [7:0] display_red, display_green, display_blue;
    logic [7:0] display_base_red, display_base_green, display_base_blue;
    logic [11:0] display_x_d, display_y_d;
    logic pclk_seen_pclk, input_frame_seen_pclk;
    logic any_error_pixel;
    logic [6:0] display_status;
    logic [7:0] display_error_code;
    logic [135:0] frame_diag_src, frame_diag_pixel;
    logic [95:0] frame_count_src, frame_count_pixel;
    logic frame_diag_valid;
    logic frame_count_snapshot_valid;
    logic [31:0] input_sof_count_pclk;
    logic [31:0] capture_good_count_pclk, capture_bad_count_pclk;
    logic [31:0] algorithm_good_count_pclk;
    logic [191:0] stability_snapshot_pclk, stability_snapshot_pixel;
    logic [191:0] stability_snapshot_display;
    logic stability_snapshot_toggle_pclk;
    logic stability_snapshot_valid, stability_counts_display_valid;
    (* async_reg = "true" *) logic [1:0] chip_id_pixel_sync;
    (* async_reg = "true" *) logic [1:0] init_done_pixel_sync;
    (* async_reg = "true" *) logic [1:0] init_failed_pixel_sync;
    (* async_reg = "true" *) logic [1:0] pclk_seen_pixel_sync;
    (* async_reg = "true" *) logic [1:0] input_frame_pixel_sync;
    (* async_reg = "true" *) logic [1:0] frame_committed_pixel_sync;
    (* async_reg = "true" *) logic [1:0] algorithm_error_pixel_sync;

    assign sys_pll_rstn_o = 1'b1;
    assign lvds_pll_rstn_o = 1'b1;
    assign display_pll_rstn_o = 1'b1;
    assign camera_plls_locked = sys_pll_lock && lvds_pll_lock;

    button_sync_debounce #(.CLK_HZ(96_000_000)) u_button_sync (
        .clk(clk_sys), .rst_n(sys_pll_lock), .key_n(key_data),
        .inc_press(key_inc_press), .dec_press(key_dec_press),
        .default_press(key_default_press), .debounced_key_n()
    );

    threshold_control u_threshold_control (
        .clk(clk_sys), .rst_n(sys_pll_lock),
        .inc_press(key_inc_press), .dec_press(key_dec_press),
        .default_press(key_default_press),
        .requested_threshold(requested_threshold_sys),
        .request_toggle(threshold_request_toggle)
    );

    threshold_bus_cdc #(.WIDTH(11)) u_threshold_to_pclk (
        .dst_clk(cmos_pclk), .dst_rst_n(camera_pclk_rst_n),
        .src_data(requested_threshold_sys), .src_toggle(threshold_request_toggle),
        .dst_data(threshold_pclk), .dst_update(threshold_cdc_update)
    );

    always_ff @(posedge cmos_pclk or negedge camera_pclk_rst_n) begin
        if (!camera_pclk_rst_n)
            active_threshold_pclk <= 11'd128;
        else if (gray_start_of_frame)
            active_threshold_pclk <= threshold_pclk;
    end
    camera_frontend u_camera (
        .clk_sys(clk_sys), .clocks_locked(camera_plls_locked),
        .cmos_sclk(cmos_sclk), .cmos_sdat_in(cmos_sdat_in),
        .cmos_sdat_out(cmos_sdat_out), .cmos_sdat_oe(cmos_sdat_oe),
        .cmos_pclk(cmos_pclk), .cmos_vsync(cmos_vsync),
        .cmos_href(cmos_href), .cmos_data(cmos_data),
        .cmos_ctl1_pwdn(cmos_ctl1_pwdn),
        .cmos_ctl2_out(cmos_ctl2_out), .cmos_ctl2_oe(cmos_ctl2_oe),
        .cmos_ctl3_out(cmos_ctl3_out), .cmos_ctl3_oe(cmos_ctl3_oe),
        .sys_rst_n(camera_sys_rst_n), .pclk_rst_n(camera_pclk_rst_n),
        .chip_id_ok(chip_id_ok), .init_done(init_done),
        .init_failed(init_failed), .pixel(camera_pixel),
        .pixel_valid(camera_pixel_valid),
        .start_of_frame(camera_start_of_frame), .frame_end(camera_frame_end),
        .pixel_x(camera_x), .pixel_y(camera_y),
        .capture_error_pclk(capture_error_pclk),
        .capture_error_code_pclk(capture_error_code_pclk),
        .last_frame_lines_pclk(last_frame_lines_pclk),
        .last_frame_pixels_pclk(last_frame_pixels_pclk),
        .last_min_line_pixels_pclk(last_min_line_pixels_pclk),
        .last_max_line_pixels_pclk(last_max_line_pixels_pclk),
        .frame_snapshot_toggle_pclk(frame_snapshot_toggle_pclk),
        .frame_good_pclk(frame_good_pclk),
        .frame_count(camera_frame_count)
    );

    rgb565_to_gray8 u_rgb565_to_gray8 (
        .clk(cmos_pclk), .rst_n(camera_pclk_rst_n),
        .rgb565(camera_pixel), .pixel_valid(camera_pixel_valid),
        .pixel_x(camera_x), .pixel_y(camera_y),
        .start_of_frame(camera_start_of_frame),
        .frame_end(camera_frame_end), .frame_good(frame_good_pclk),
        .gray(gray_pixel8), .gray_rgb565(gray_preview_pixel565),
        .gray_valid(gray_pixel_valid), .gray_x(gray_x), .gray_y(gray_y),
        .gray_start_of_frame(gray_start_of_frame),
        .gray_end_of_line(gray_end_of_line),
        .gray_frame_end(gray_frame_end), .gray_frame_good(gray_frame_good)
    );

    gray_window_3x3 #(.WIDTH(640), .HEIGHT(480)) u_gray_window_3x3 (
        .clk(cmos_pclk), .rst_n(camera_pclk_rst_n),
        .gray_in(gray_pixel8), .in_valid(gray_pixel_valid),
        .in_x(gray_x[9:0]), .in_y(gray_y[8:0]),
        .in_sof(gray_start_of_frame), .in_frame_end(gray_frame_end),
        .out_valid(window_valid),
        .p00(w00), .p01(w01), .p02(w02),
        .p10(w10), .p11(w11), .p12(w12),
        .p20(w20), .p21(w21), .p22(w22),
        .center_x(window_x), .center_y(window_y)
    );

    sobel_threshold u_sobel_threshold (
        .clk(cmos_pclk), .rst_n(camera_pclk_rst_n),
        .flush(gray_start_of_frame), .in_valid(window_valid),
        .p00(w00), .p01(w01), .p02(w02),
        .p10(w10), .p11(w11), .p12(w12),
        .p20(w20), .p21(w21), .p22(w22),
        .in_x(window_x), .in_y(window_y), .threshold_in(active_threshold_pclk),
        .out_valid(sobel_valid), .edge_out(sobel_edge),
        .gx_out(sobel_gx), .gy_out(sobel_gy),
        .magnitude_out(sobel_magnitude), .out_x(sobel_x), .out_y(sobel_y)
    );

    edge_full_frame_stream #(.WIDTH(640), .HEIGHT(480)) u_edge_full_frame (
        .clk(cmos_pclk), .rst_n(camera_pclk_rst_n),
        .input_sof(gray_start_of_frame),
        .input_frame_end(gray_frame_end), .input_frame_good(gray_frame_good),
        .interior_valid(sobel_valid), .interior_edge(sobel_edge),
        .interior_x(sobel_x), .interior_y(sobel_y),
        .out_valid(edge_full_valid), .out_edge(edge_full_bit),
        .out_x(edge_full_x), .out_y(edge_full_y), .out_sof(edge_full_sof),
        .out_frame_end(edge_full_end), .out_frame_good(edge_full_good),
        .fifo_overflow(edge_fifo_overflow),
        .coordinate_error(edge_coordinate_error),
        .frame_queue_overflow(edge_frame_queue_overflow),
        .good_queue_overflow(edge_good_queue_overflow),
        .fifo_level_dbg(edge_fifo_level), .fifo_max_level_dbg(edge_fifo_max_level)
    );

    edge_preview_2x2_or #(
        .SOURCE_WIDTH(640), .SOURCE_HEIGHT(480)
    ) u_edge_preview_2x2_or (
        .clk(cmos_pclk), .rst_n(camera_pclk_rst_n),
        .in_valid(edge_full_valid), .edge_in(edge_full_bit),
        .in_x(edge_full_x), .in_y(edge_full_y), .in_sof(edge_full_sof),
        .in_frame_end(edge_full_end), .in_frame_good(edge_full_good),
        .out_valid(edge_preview_valid), .out_pixel565(edge_preview_pixel565),
        .out_x(edge_preview_x), .out_y(edge_preview_y),
        .out_sof(edge_preview_sof), .out_frame_end(edge_preview_end),
        .out_frame_good(edge_preview_good),
        .coordinate_error(edge_preview_coordinate_error)
    );

    gray_preview_2x2_mean #(
        .SOURCE_WIDTH(640), .SOURCE_HEIGHT(480)
    ) u_gray_preview_2x2_mean (
        .clk(cmos_pclk), .rst_n(camera_pclk_rst_n),
        .in_valid(gray_pixel_valid), .gray_in(gray_pixel8),
        .in_x(gray_x[9:0]), .in_y(gray_y[8:0]),
        .in_sof(gray_start_of_frame), .in_frame_end(gray_frame_end),
        .in_frame_good(gray_frame_good),
        .out_valid(gray_preview_valid), .out_gray(gray_preview_value),
        .out_x(gray_preview_x), .out_y(gray_preview_y),
        .out_sof(gray_preview_sof), .out_frame_end(gray_preview_end),
        .out_frame_good(gray_preview_good),
        .coordinate_error(gray_preview_coordinate_error)
    );

    preview_pair_aligner u_preview_pair_aligner (
        .clk(cmos_pclk), .rst_n(camera_pclk_rst_n),
        .gray_valid(gray_preview_valid), .gray_value(gray_preview_value),
        .gray_x(gray_preview_x), .gray_y(gray_preview_y),
        .gray_sof(gray_preview_sof), .gray_frame_end(gray_preview_end),
        .gray_frame_threshold(active_threshold_pclk),
        .edge_valid(edge_preview_valid),
        .edge_value(edge_preview_pixel565[0]),
        .edge_x(edge_preview_x), .edge_y(edge_preview_y),
        .edge_sof(edge_preview_sof), .edge_frame_end(edge_preview_end),
        .edge_frame_good(edge_preview_good),
        .out_valid(paired_valid), .out_gray(paired_gray),
        .out_edge(paired_edge), .out_x(paired_x), .out_y(paired_y),
        .out_sof(paired_sof), .out_frame_end(paired_end),
        .out_frame_good(paired_good),
        .out_frame_threshold(paired_threshold),
        .alignment_error(pair_alignment_error),
        .fifo_max_level(pair_fifo_max_level)
    );

    frame_event_counters u_frame_event_counters (
        .clk(cmos_pclk), .rst_n(camera_pclk_rst_n),
        .input_sof(camera_start_of_frame),
        .capture_frame_end(camera_frame_end),
        .capture_frame_good(frame_good_pclk),
        .algorithm_frame_end(paired_end),
        .algorithm_frame_good(paired_good),
        .committed_frame_count(committed_frame_count_pclk),
        .busy_drop_count(dropped_frame_count),
        .input_sof_count(input_sof_count_pclk),
        .capture_good_count(capture_good_count_pclk),
        .capture_bad_count(capture_bad_count_pclk),
        .algorithm_good_count(algorithm_good_count_pclk),
        .snapshot_data(stability_snapshot_pclk),
        .snapshot_toggle(stability_snapshot_toggle_pclk)
    );

    assign algorithm_error_pclk = edge_fifo_overflow || edge_coordinate_error ||
                                  edge_frame_queue_overflow ||
                                  edge_good_queue_overflow ||
                                  edge_preview_coordinate_error ||
                                  gray_preview_coordinate_error ||
                                  pair_alignment_error;

    reset_release_sync u_pixel_reset (
        .clk(clk_pixel), .async_ready(display_pll_lock), .reset_n(pixel_reset_n)
    );
    reset_release_sync u_fast_reset (
        .clk(clk_pixel_5x), .async_ready(display_pll_lock), .reset_n(fast_reset_n)
    );
    reset_release_sync u_feedback_reset (
        .clk(display_feedback_24m), .async_ready(display_pll_lock),
        .reset_n(feedback_reset_n)
    );
    assign link_ready = pixel_reset_n && fast_reset_n && feedback_reset_n;

    video_timing_gen #(
        .H_ACTIVE(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_ACTIVE(480), .V_FP(10), .V_SYNC(2), .V_BP(33),
        .HS_ACTIVE_LEVEL(1'b0), .VS_ACTIVE_LEVEL(1'b0)
    ) u_timing (
        .clk_pixel(clk_pixel), .rst_n(pixel_reset_n),
        .x(display_x), .y(display_y), .de(display_de),
        .hsync(display_hsync), .vsync(display_vsync),
        .frame_tick(display_frame_tick)
    );

    split_triple_framebuffer #(
        .IMAGE_WIDTH(320), .IMAGE_HEIGHT(240),
        .DISPLAY_WIDTH(640), .DISPLAY_HEIGHT(480),
        .DISPLAY_MODE(SPLIT_DISPLAY_MODE)
    ) u_framebuffer (
        .wr_clk(cmos_pclk), .wr_rst_n(camera_pclk_rst_n),
        .wr_gray(paired_gray), .wr_edge(paired_edge), .wr_valid(paired_valid),
        .wr_start_of_frame(paired_sof), .wr_frame_end(paired_end),
        .wr_x(paired_x), .wr_y(paired_y), .wr_frame_good(paired_good),
        .wr_frame_threshold(paired_threshold),
        .buffer_error_wr(buffer_error_pclk),
        .buffer_error_code_wr(buffer_error_code_pclk),
        .frame_committed_wr(frame_committed_pclk),
        .last_sampled_pixel_count_wr(last_sampled_pixels_pclk),
        .last_written_word_count_wr(last_written_words_pclk),
        .committed_frame_count_wr(committed_frame_count_pclk),
        .dropped_frame_count(dropped_frame_count),
        .rd_clk(clk_pixel), .rd_rst_n(pixel_reset_n),
        .rd_x(display_x), .rd_y(display_y), .rd_de(display_de),
        .rd_frame_tick(display_frame_tick),
        .rd_gray(display_gray), .rd_edge(display_edge),
        .rd_gray_view(display_gray_view), .rd_edge_view(display_edge_view),
        .rd_pixel_valid(display_pixel_valid),
        .display_has_frame(display_has_frame),
        .displayed_frame_count(displayed_frame_count),
        .displayed_frame_threshold(displayed_frame_threshold)
    );

    always_comb begin
        if (display_gray_view)
            display_pixel565 = {display_gray[7:3], display_gray[7:2], display_gray[7:3]};
        else if (display_edge_view)
            display_pixel565 = display_edge ? 16'hFFFF : 16'h0000;
        else
            display_pixel565 = 16'h0000;
    end

    always_ff @(posedge clk_pixel or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            display_de_d <= 1'b0;
            display_hsync_d <= 1'b1;
            display_vsync_d <= 1'b1;
            display_x_d <= 12'd0;
            display_y_d <= 12'd0;
        end else begin
            display_de_d <= display_de;
            display_hsync_d <= display_hsync;
            display_vsync_d <= display_vsync;
            display_x_d <= display_x;
            display_y_d <= display_y;
        end
    end

    // PCLK and input-frame activity become sticky in the PCLK domain. The
    // display diagnostic never depends on PCLK and remains alive if it stops.
    always_ff @(posedge cmos_pclk or negedge camera_pclk_rst_n) begin
        if (!camera_pclk_rst_n) begin
            pclk_seen_pclk <= 1'b0;
            input_frame_seen_pclk <= 1'b0;
        end else begin
            pclk_seen_pclk <= 1'b1;
            if (camera_frame_end)
                input_frame_seen_pclk <= 1'b1;
        end
    end

    always_ff @(posedge clk_pixel or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            chip_id_pixel_sync <= 2'b00;
            init_done_pixel_sync <= 2'b00;
            init_failed_pixel_sync <= 2'b00;
            pclk_seen_pixel_sync <= 2'b00;
            input_frame_pixel_sync <= 2'b00;
            frame_committed_pixel_sync <= 2'b00;
            algorithm_error_pixel_sync <= 2'b00;
        end else begin
            chip_id_pixel_sync <= {chip_id_pixel_sync[0], chip_id_ok};
            init_done_pixel_sync <= {init_done_pixel_sync[0], init_done};
            init_failed_pixel_sync <= {init_failed_pixel_sync[0], init_failed};
            pclk_seen_pixel_sync <= {pclk_seen_pixel_sync[0], pclk_seen_pclk};
            input_frame_pixel_sync <= {input_frame_pixel_sync[0], input_frame_seen_pclk};
            frame_committed_pixel_sync <= {frame_committed_pixel_sync[0], frame_committed_pclk};
            algorithm_error_pixel_sync <= {algorithm_error_pixel_sync[0], algorithm_error_pclk};
        end
    end

    // All counters and per-frame error fields change only when the source
    // toggle changes. The destination captures the stable two-stage snapshot;
    // no changing multi-bit counter is sampled directly across clock domains.
    assign frame_diag_src = {
        buffer_error_code_pclk,
        capture_error_code_pclk,
        last_frame_lines_pclk,
        last_frame_pixels_pclk,
        last_min_line_pixels_pclk,
        last_max_line_pixels_pclk,
        last_sampled_pixels_pclk,
        last_written_words_pclk
    };

    snapshot_cdc #(.WIDTH(136)) u_frame_diag_cdc (
        .dst_clk(clk_pixel), .dst_rst_n(pixel_reset_n),
        .src_toggle(frame_snapshot_toggle_pclk), .src_data(frame_diag_src),
        .dst_data(frame_diag_pixel), .dst_valid(frame_diag_valid),
        .dst_update()
    );

    assign frame_count_src = {
        camera_frame_count, committed_frame_count_pclk, dropped_frame_count
    };

    snapshot_cdc #(.WIDTH(96)) u_frame_count_cdc (
        .dst_clk(clk_pixel), .dst_rst_n(pixel_reset_n),
        .src_toggle(frame_snapshot_toggle_pclk), .src_data(frame_count_src),
        .dst_data(frame_count_pixel), .dst_valid(frame_count_snapshot_valid),
        .dst_update()
    );

    snapshot_cdc #(.WIDTH(192)) u_stability_count_cdc (
        .dst_clk(clk_pixel), .dst_rst_n(pixel_reset_n),
        .src_toggle(stability_snapshot_toggle_pclk),
        .src_data(stability_snapshot_pclk),
        .dst_data(stability_snapshot_pixel),
        .dst_valid(stability_snapshot_valid), .dst_update()
    );

    // Freeze the complete counter bundle at an HDMI frame boundary. This
    // prevents a binary row from changing part-way through a displayed frame.
    always_ff @(posedge clk_pixel or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            stability_snapshot_display <= 192'd0;
            stability_counts_display_valid <= 1'b0;
        end else if (display_frame_tick) begin
            stability_snapshot_display <= stability_snapshot_pixel;
            stability_counts_display_valid <= stability_snapshot_valid;
        end
    end

    assign display_error_code = {
        frame_diag_pixel[135:132], frame_diag_pixel[131:128]
    };
    assign any_error_pixel = init_failed_pixel_sync[1] ||
                             algorithm_error_pixel_sync[1] ||
                             (frame_diag_valid && (|display_error_code));
    assign display_status = {
        any_error_pixel,
        display_has_frame,
        frame_committed_pixel_sync[1],
        input_frame_pixel_sync[1],
        pclk_seen_pixel_sync[1],
        init_done_pixel_sync[1],
        chip_id_pixel_sync[1]
    };

    generate
        if (DIAGNOSTIC_OVERLAY_BUILD) begin : g_diagnostic
            display_diagnostic_overlay #(
                .FORCE_COLOR_BARS(FORCE_COLOR_BARS_BUILD)
            ) u_diagnostic (
                .clk_pixel(clk_pixel), .rst_n(pixel_reset_n),
                .x(display_x_d), .y(display_y_d), .de(display_de_d),
                .frame_tick(display_frame_tick),
                .camera_pixel565(display_pixel565),
                .camera_pixel_valid(display_pixel_valid),
                .status(display_status),
                .frame_diag_valid(frame_diag_valid),
                .error_code({display_error_code, init_failed_pixel_sync[1]}),
                .last_frame_lines(frame_diag_pixel[127:112]),
                .last_min_line_bytes(frame_diag_pixel[79:64] << 1),
                .last_max_line_bytes(frame_diag_pixel[63:48] << 1),
                .last_sampled_pixels(frame_diag_pixel[47:16]),
                .last_written_words(frame_diag_pixel[15:0]),
                .frame_count_valid(frame_count_snapshot_valid),
                .input_frame_count(frame_count_pixel[95:64]),
                .committed_frame_count(frame_count_pixel[63:32]),
                .displayed_frame_count(displayed_frame_count),
                .dropped_frame_count(frame_count_pixel[31:0]),
                .red(display_base_red), .green(display_base_green), .blue(display_base_blue)
            );
        end else begin : g_clean_preview
            split_preview_output u_clean_preview (
                .de(display_de_d), .pixel_valid(display_pixel_valid),
                .gray_view(display_gray_view), .edge_view(display_edge_view),
                .gray(display_gray), .edge_bit(display_edge),
                .red(display_base_red), .green(display_base_green), .blue(display_base_blue)
            );
        end
    endgenerate

    // This dedicated stability build intentionally replaces the unreliable
    // threshold glyph overlay with font-independent binary frame counters.
    // Threshold keys and frame-bound threshold application remain unchanged.
    frame_counter_overlay u_frame_counter_overlay (
        .de(display_de_d), .hdmi_x(display_x_d), .hdmi_y(display_y_d),
        .counters_valid(stability_counts_display_valid),
        .input_sof_count(stability_snapshot_display[191:160]),
        .capture_good_count(stability_snapshot_display[159:128]),
        .capture_bad_count(stability_snapshot_display[127:96]),
        .algorithm_good_count(stability_snapshot_display[95:64]),
        .committed_frame_count(stability_snapshot_display[63:32]),
        .busy_drop_count(stability_snapshot_display[31:0]),
        .displayed_frame_count(displayed_frame_count),
        .base_red(display_base_red), .base_green(display_base_green),
        .base_blue(display_base_blue),
        .red(display_red), .green(display_green), .blue(display_blue)
    );

    tmds_encoder u_tmds_blue (
        .clk_pixel(clk_pixel), .rst_n(pixel_reset_n), .data(display_blue),
        .de(display_de_d), .control({display_vsync_d, display_hsync_d}),
        .symbol(tmds_lvds_tx_data0)
    );
    tmds_encoder u_tmds_green (
        .clk_pixel(clk_pixel), .rst_n(pixel_reset_n), .data(display_green),
        .de(display_de_d), .control(2'b00), .symbol(tmds_lvds_tx_data1)
    );
    tmds_encoder u_tmds_red (
        .clk_pixel(clk_pixel), .rst_n(pixel_reset_n), .data(display_red),
        .de(display_de_d), .control(2'b00), .symbol(tmds_lvds_tx_data2)
    );
    assign tmds_lvds_tx_clk_o = 10'b1111100000;

    assign tmds_lvds_tx_clk_rst   = ~link_ready;
    assign tmds_lvds_tx_data0_rst = ~link_ready;
    assign tmds_lvds_tx_data1_rst = ~link_ready;
    assign tmds_lvds_tx_data2_rst = ~link_ready;
    assign tmds_lvds_tx_clk_oe    = link_ready;
    assign tmds_lvds_tx_data0_oe  = link_ready;
    assign tmds_lvds_tx_data1_oe  = link_ready;
    assign tmds_lvds_tx_data2_oe  = link_ready;

    // Active-low board LEDs. R13 is DDR_REF_CLK and is not an LED output.
    assign led_o[0] = ~display_pll_lock;
    assign led_o[1] = cmos_ctl1_pwdn;
    assign led_o[2] = ~chip_id_pixel_sync[1];
    assign led_o[3] = ~init_done_pixel_sync[1];
    assign led_o[4] = ~displayed_frame_count[4];
    assign led_o[5] = ~any_error_pixel;
endmodule
