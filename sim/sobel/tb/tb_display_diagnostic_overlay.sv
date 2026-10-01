`timescale 1ns/1ps
module tb_display_diagnostic_overlay;
    logic clk_pixel = 0;
    logic rst_n = 0;
    logic [11:0] x, y;
    logic de, frame_tick;
    logic [15:0] camera_pixel565;
    logic camera_pixel_valid;
    logic [6:0] status;
    logic frame_diag_valid;
    logic [8:0] error_code;
    logic [15:0] last_frame_lines, last_min_line_bytes, last_max_line_bytes;
    logic [31:0] last_sampled_pixels;
    logic [15:0] last_written_words;
    logic frame_count_valid;
    logic [31:0] input_frame_count, committed_frame_count;
    logic [31:0] displayed_frame_count, dropped_frame_count;
    logic [7:0] red, green, blue;
    logic [7:0] force_red, force_green, force_blue;

    always #5 clk_pixel = ~clk_pixel;

    display_diagnostic_overlay #(.FORCE_COLOR_BARS(1'b0)) dut (
        .clk_pixel, .rst_n, .x, .y, .de, .frame_tick,
        .camera_pixel565, .camera_pixel_valid, .status,
        .frame_diag_valid, .error_code, .last_frame_lines,
        .last_min_line_bytes, .last_max_line_bytes,
        .last_sampled_pixels, .last_written_words,
        .frame_count_valid, .input_frame_count, .committed_frame_count,
        .displayed_frame_count, .dropped_frame_count,
        .red, .green, .blue
    );

    display_diagnostic_overlay #(.FORCE_COLOR_BARS(1'b1)) dut_force (
        .clk_pixel, .rst_n, .x, .y, .de, .frame_tick,
        .camera_pixel565, .camera_pixel_valid, .status,
        .frame_diag_valid, .error_code, .last_frame_lines,
        .last_min_line_bytes, .last_max_line_bytes,
        .last_sampled_pixels, .last_written_words,
        .frame_count_valid, .input_frame_count, .committed_frame_count,
        .displayed_frame_count, .dropped_frame_count,
        .red(force_red), .green(force_green), .blue(force_blue)
    );

    task automatic sample(input int sx, input int sy);
        begin
            @(negedge clk_pixel);
            x <= sx; y <= sy; de <= 1'b1;
            @(posedge clk_pixel); #1;
        end
    endtask

    initial begin
        x = 0; y = 0; de = 0; frame_tick = 0;
        camera_pixel565 = 16'h07e0;
        camera_pixel_valid = 0;
        status = 7'b0000000;
        frame_diag_valid = 0; error_code = 0;
        last_frame_lines = 16'd480;
        last_min_line_bytes = 16'd1280;
        last_max_line_bytes = 16'd1280;
        last_sampled_pixels = 32'd76800;
        last_written_words = 16'd15360;
        frame_count_valid = 0;
        input_frame_count = 32'd5;
        committed_frame_count = 32'd4;
        displayed_frame_count = 32'd3;
        dropped_frame_count = 32'd1;
        repeat (3) @(posedge clk_pixel);
        rst_n = 1;

        // The display is autonomous before any camera frame exists.
        sample(170, 180);
        if ({red,green,blue} !== 24'h00ffff)
            $fatal(1, "autonomous color bar incorrect: %h", {red,green,blue});

        // A valid camera pixel overrides the bars in the normal build only.
        camera_pixel_valid = 1;
        sample(280, 300);
        if ({red,green,blue} !== 24'h00ff00)
            $fatal(1, "RGB565 camera override incorrect: %h", {red,green,blue});
        if ({force_red,force_green,force_blue} !== 24'h00ff00)
            $fatal(1, "force-bars source bar unexpected at x=280");
        camera_pixel565 = 16'hf800;
        #1;
        if ({red,green,blue} !== 24'hff0000)
            $fatal(1, "normal build did not follow camera RGB565");
        if ({force_red,force_green,force_blue} !== 24'h00ff00)
            $fatal(1, "force-bars build leaked camera data");

        // Status 0 changes from dark red to green when chip ID is good.
        camera_pixel_valid = 0;
        sample(16, 20);
        if ({red,green,blue} !== 24'h900000)
            $fatal(1, "pending status color incorrect");
        status[0] = 1;
        #1;
        if ({red,green,blue} !== 24'h00ff20)
            $fatal(1, "good status color incorrect");

        // Counter rows are amber before the first coherent snapshot and show
        // LSB-first binary afterward. 480 is even, so bit 0 is dark.
        sample(8, 56);
        if ({red,green,blue} !== 24'h906000)
            $fatal(1, "pre-snapshot counter cell is not amber");
        frame_diag_valid = 1;
        #1;
        if ({red,green,blue} !== 24'h202020)
            $fatal(1, "counter bit 0 for 480 should be dark");
        sample(88, 56); // bit 5 of 480 is one
        if ({red,green,blue} !== 24'h00ff20)
            $fatal(1, "counter bit 5 for 480 should be green");

        sample(8, 188);
        if ({red,green,blue} !== 24'h906000)
            $fatal(1, "pre-snapshot frame counter is not amber");
        frame_count_valid = 1;
        #1;
        if ({red,green,blue} !== 24'h00ff20)
            $fatal(1, "input frame counter bit 0 should be green");

        sample(56, 150); // error block 1: capture odd-byte error
        if ({red,green,blue} !== 24'h00ff20)
            $fatal(1, "clear error block should be green");
        error_code[1] = 1;
        #1;
        if ({red,green,blue} !== 24'hff0000)
            $fatal(1, "set error block should be red");
        error_code[1] = 0;

        // The marker starts at x=8 and advances four pixels per frame.
        sample(8, 440);
        if ({red,green,blue} !== 24'hffffff)
            $fatal(1, "initial moving marker missing");
        @(negedge clk_pixel); frame_tick <= 1'b1;
        @(negedge clk_pixel); frame_tick <= 1'b0;
        sample(36, 440);
        if ({red,green,blue} !== 24'hffffff)
            $fatal(1, "moving marker did not advance");

        @(negedge clk_pixel); de <= 1'b0;
        @(posedge clk_pixel); #1;
        if ({red,green,blue} !== 24'h000000)
            $fatal(1, "blanking output is not black");

        $display("PASS: autonomous bars, status blocks, motion, RGB565 override, and force-bars mode");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "timeout");
    end
endmodule
