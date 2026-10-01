`timescale 1ns/1ps
module tb_dvp_to_framebuffer_recovery;
    localparam int SW = 20;
    localparam int SH = 6;
    localparam int IW = 5;
    localparam int IH = 2;

    logic pclk = 0, rd_clk = 0;
    logic rst_n = 0, rd_rst_n = 0;
    logic vsync = 0, href = 0;
    logic [7:0] data = 0;
    logic [15:0] pixel;
    logic pixel_valid, start_of_frame, end_of_line, line_end, frame_end;
    logic [11:0] x, y;
    logic odd_byte_error;
    logic [31:0] frame_count, line_error_count, frame_error_count;
    logic [15:0] last_line_pixels, last_frame_lines;
    logic [31:0] last_frame_pixels;
    logic [15:0] last_min_line_pixels, last_max_line_pixels;
    logic [3:0] capture_error_code;
    logic snapshot_toggle;
    logic frame_good;

    logic buffer_error_wr, frame_committed_wr;
    logic [3:0] buffer_error_code_wr;
    logic [31:0] last_sampled_pixel_count_wr;
    logic [15:0] last_written_word_count_wr;
    logic [31:0] committed_frame_count_wr;
    logic [31:0] dropped_frame_count;
    logic [11:0] rd_x = 0, rd_y = 0;
    logic rd_de = 0, rd_frame_tick = 0;
    logic [15:0] rd_pixel;
    logic rd_pixel_valid, display_has_frame;
    logic [31:0] displayed_frame_count;

    always #5 pclk = ~pclk;
    always #7 rd_clk = ~rd_clk;

    dvp_rgb565_capture #(.ACTIVE_WIDTH(SW), .ACTIVE_HEIGHT(SH)) u_capture (
        .pclk, .rst_n, .vsync, .href, .data, .pixel, .pixel_valid,
        .start_of_frame, .end_of_line, .line_end, .frame_end, .x, .y,
        .odd_byte_error
    );

    camera_frame_monitor #(.ACTIVE_WIDTH(SW), .ACTIVE_HEIGHT(SH)) u_monitor (
        .pclk, .rst_n, .pixel_valid, .start_of_frame, .line_end,
        .frame_end, .odd_byte_error, .frame_count, .last_line_pixels,
        .last_frame_lines, .last_frame_pixels, .last_min_line_pixels,
        .last_max_line_pixels, .last_error_code(capture_error_code),
        .frame_good,
        .snapshot_toggle, .line_error_count, .frame_error_count
    );

    packed_pingpong_framebuffer #(
        .SOURCE_WIDTH(SW), .SOURCE_HEIGHT(SH),
        .SAMPLE_X_STEP(4), .SAMPLE_Y_STEP(3),
        .IMAGE_WIDTH(IW), .IMAGE_HEIGHT(IH),
        .DISPLAY_WIDTH(9), .DISPLAY_HEIGHT(6)
    ) u_buffer (
        .wr_clk(pclk), .wr_rst_n(rst_n), .wr_pixel(pixel),
        .wr_pixel_valid(pixel_valid), .wr_start_of_frame(start_of_frame),
        .wr_frame_end(frame_end), .wr_frame_good(frame_good),
        .wr_x(x), .wr_y(y),
        .buffer_error_wr, .buffer_error_code_wr, .frame_committed_wr,
        .last_sampled_pixel_count_wr, .last_written_word_count_wr,
        .committed_frame_count_wr,
        .dropped_frame_count,
        .rd_clk, .rd_rst_n, .rd_x, .rd_y, .rd_de, .rd_frame_tick,
        .rd_pixel, .rd_pixel_valid, .display_has_frame,
        .displayed_frame_count
    );

    task automatic put_byte(input logic [7:0] value);
        begin
            data = value;
            @(negedge pclk);
        end
    endtask

    task automatic put_pixel(input int frame_id, input int px, input int py);
        logic [15:0] value;
        begin
            value = {frame_id[3:0], py[3:0], px[7:0]};
            put_byte(value[15:8]);
            put_byte(value[7:0]);
        end
    endtask

    task automatic send_frame(input int frame_id, input int lines,
                              input int pixels_per_line,
                              input bit adjacent_end);
        integer px, py;
        begin
            @(negedge pclk); vsync = 1'b1; href = 1'b0;
            repeat (2) @(negedge pclk);
            for (py = 0; py < lines; py = py + 1) begin
                href = 1'b1;
                for (px = 0; px < pixels_per_line; px = px + 1)
                    put_pixel(frame_id, px, py);
                href = 1'b0;
                if (py != lines-1)
                    repeat (2) @(negedge pclk);
            end
            if (adjacent_end) begin
                // HREF and active-high frame-valid fall together immediately
                // after the last low byte.
                vsync = 1'b0;
            end else begin
                repeat (2) @(negedge pclk);
                vsync = 1'b0;
            end
            repeat (3) @(negedge pclk);
        end
    endtask

    task automatic display_boundary;
        begin
            repeat (4) @(posedge rd_clk);
            @(negedge rd_clk); rd_frame_tick = 1;
            @(negedge rd_clk); rd_frame_tick = 0;
            repeat (4) @(posedge rd_clk);
            repeat (4) @(posedge pclk);
        end
    endtask

    initial begin
        // Release reset in the middle of an already-active frame. This data
        // must be discarded until a low VSYNC interval arms the next frame.
        vsync = 1; href = 1; data = 8'h5a;
        repeat (4) @(negedge pclk);
        rst_n = 1; rd_rst_n = 1;
        repeat (7) begin
            put_byte(8'ha5);
        end
        @(negedge pclk); href = 0; vsync = 0;
        repeat (3) @(negedge pclk);

        // A normal complete frame with the final HREF and VSYNC falling on
        // the same external edge must still include its final line/pixel.
        send_frame(1, SH, SW, 1'b1);
        repeat (6) @(posedge rd_clk);
        if (!frame_committed_wr)
            $fatal(1, "official active-high VSYNC frame was not committed");
        if (buffer_error_wr || odd_byte_error || dropped_frame_count != 0)
            $fatal(1, "unexpected error buffer=%0b odd=%0b dropped=%0d",
                   buffer_error_wr, odd_byte_error, dropped_frame_count);
        if ((last_frame_lines != SH) || (last_frame_pixels != SW*SH) ||
            (last_min_line_pixels != SW) || (last_max_line_pixels != SW) ||
            (capture_error_code != 0) ||
            (last_sampled_pixel_count_wr != IW*IH) ||
            (last_written_word_count_wr != (IW*IH)/5) ||
            (buffer_error_code_wr != 0))
            $fatal(1, "bad clean-frame diagnostics");

        display_boundary();
        if (!display_has_frame || displayed_frame_count != 1)
            $fatal(1, "first complete frame was not accepted");

        // Reject a residual frame with one short line and too few lines.
        send_frame(2, SH-1, SW-1, 1'b0);
        repeat (4) @(posedge pclk);
        if (!buffer_error_wr || (buffer_error_code_wr == 0) ||
            (capture_error_code == 0))
            $fatal(1, "partial frame diagnose buffer=%0b bcode=%h ccode=%h samples=%0d words=%0d lines=%0d pixels=%0d dropped=%0d",
                   buffer_error_wr, buffer_error_code_wr,
                   capture_error_code, last_sampled_pixel_count_wr,
                   last_written_word_count_wr, last_frame_lines,
                   last_frame_pixels, dropped_frame_count);
        display_boundary();
        if (displayed_frame_count != 1)
            $fatal(1, "partial frame was incorrectly displayed");

        // A complete frame after the residual must recover and clear the
        // per-frame errors instead of leaving a startup/stale sticky failure.
        send_frame(3, SH, SW, 1'b0);
        repeat (4) @(posedge pclk);
        if (buffer_error_wr || buffer_error_code_wr != 0 ||
            capture_error_code != 0)
            $fatal(1, "clean frame did not recover from prior residual");
        display_boundary();
        if (displayed_frame_count != 2)
            $fatal(1, "recovery frame was not displayed");

        // A further continuous good frame verifies bank/ready/ack reuse.
        send_frame(4, SH, SW, 1'b0);
        display_boundary();
        if (displayed_frame_count != 3 || dropped_frame_count != 0)
            $fatal(1, "continuous frame/bank reuse failed");

        $display("PASS: official VSYNC/HREF, mid-frame reset discard, adjacent EOF, residual reject/recovery, continuous bank reuse");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "timeout");
    end
endmodule
