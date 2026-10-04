`timescale 1ns/1ps
module tb_dvp_capture;
    localparam int W = 4;
    localparam int H = 3;

    logic pclk = 0;
    logic rst_n = 0;
    logic vsync = 0;
    logic href = 0;
    logic [7:0] data = 0;
    logic [15:0] pixel;
    logic pixel_valid, sof, eol, line_end, frame_end, odd_byte_error;
    logic [11:0] x, y;
    logic [31:0] frame_count, line_errors, frame_errors;
    logic [15:0] last_line_pixels, last_frame_lines;
    logic [31:0] last_frame_pixels;
    logic [15:0] last_min_line_pixels, last_max_line_pixels;
    logic [3:0] last_error_code;
    logic snapshot_toggle;
    logic frame_good;
    integer expected_pixels = 0;
    integer observed_pixels = 0;
    integer sof_count = 0;
    logic checking = 1'b1;
    logic [15:0] expected [0:63];
    logic [11:0] expected_x [0:63];
    logic [11:0] expected_y [0:63];

    always #5 pclk = ~pclk;

    dvp_rgb565_capture #(.ACTIVE_WIDTH(W), .ACTIVE_HEIGHT(H)) dut (
        .pclk, .rst_n, .vsync, .href, .data, .pixel,
        .pixel_valid, .start_of_frame(sof), .end_of_line(eol),
        .line_end, .frame_end, .x, .y, .odd_byte_error
    );

    camera_frame_monitor #(.ACTIVE_WIDTH(W), .ACTIVE_HEIGHT(H)) monitor (
        .pclk, .rst_n, .pixel_valid, .start_of_frame(sof), .line_end,
        .frame_end, .odd_byte_error, .frame_count, .last_line_pixels,
        .last_frame_lines, .last_frame_pixels, .last_min_line_pixels,
        .last_max_line_pixels, .last_error_code, .frame_good,
        .snapshot_toggle,
        .line_error_count(line_errors), .frame_error_count(frame_errors)
    );

    always @(negedge pclk) begin
        if (pixel_valid && checking) begin
            if (observed_pixels >= expected_pixels)
                $fatal(1, "unexpected extra pixel %h", pixel);
            if (pixel !== expected[observed_pixels])
                $fatal(1, "pixel[%0d] got %h expected %h", observed_pixels, pixel, expected[observed_pixels]);
            if ((x !== expected_x[observed_pixels]) || (y !== expected_y[observed_pixels]))
                $fatal(1, "coordinate[%0d] got (%0d,%0d) expected (%0d,%0d)",
                       observed_pixels, x, y, expected_x[observed_pixels], expected_y[observed_pixels]);
            if (eol !== (x == W-1))
                $fatal(1, "EOL mismatch at x=%0d y=%0d", x, y);
            if (sof) begin
                sof_count = sof_count + 1;
                if ((x != 0) || (y != 0))
                    $fatal(1, "SOF not aligned to first pixel");
            end
            observed_pixels = observed_pixels + 1;
        end
    end

    task automatic drive_byte(input logic [7:0] value);
        data = value;
        @(negedge pclk);
    endtask

    task automatic begin_frame;
        @(negedge pclk); href = 0; vsync = 1;
        repeat (2) @(negedge pclk);
    endtask

    task automatic send_frame(input logic [7:0] base);
        logic [7:0] b;
        integer line, col;
        begin
            @(negedge pclk); href = 0; vsync = 0;
            repeat (2) @(negedge pclk);
            begin_frame();
            for (line = 0; line < H; line = line + 1) begin
                @(negedge pclk); href = 1;
                for (col = 0; col < W; col = col + 1) begin
                    b = base + line*W + col;
                    expected[expected_pixels] = {b, ~b};
                    expected_x[expected_pixels] = col;
                    expected_y[expected_pixels] = line;
                    expected_pixels = expected_pixels + 1;
                    drive_byte(b);
                    drive_byte(~b);
                end
                href = 0; data = 0;
                repeat (3) @(negedge pclk);
            end
            vsync = 0;
            repeat (3) @(negedge pclk);
        end
    endtask

    initial begin
        #2000000 $fatal(1, "timeout");
    end

    initial begin
        repeat (4) @(negedge pclk);
        rst_n = 1;
        send_frame(8'h10);
        send_frame(8'h40);
        repeat (8) @(negedge pclk);

        if (observed_pixels != expected_pixels)
            $fatal(1, "pixel count got %0d expected %0d", observed_pixels, expected_pixels);
        if (sof_count != 2)
            $fatal(1, "SOF count got %0d expected 2", sof_count);
        if (frame_count != 2 || last_frame_lines != H)
            $fatal(1, "frame monitor got count=%0d lines=%0d", frame_count, last_frame_lines);
        if ((last_frame_pixels != W*H) ||
            (last_min_line_pixels != W) || (last_max_line_pixels != W) ||
            (last_error_code != 0))
            $fatal(1, "bad snapshot pixels=%0d min=%0d max=%0d code=%h",
                   last_frame_pixels, last_min_line_pixels,
                   last_max_line_pixels, last_error_code);
        if (line_errors != 0 || frame_errors != 0 || odd_byte_error)
            $fatal(1, "unexpected errors line=%0d frame=%0d odd=%0b", line_errors, frame_errors, odd_byte_error);

        // Reset recovery, then deliberately end a line with one unpaired byte.
        checking = 1'b0;
        @(negedge pclk); rst_n = 0; href = 0; vsync = 0;
        repeat (3) @(negedge pclk);
        rst_n = 1;
        repeat (2) @(negedge pclk);
        begin_frame();
        @(negedge pclk); href = 1;
        drive_byte(8'haa);
        href = 0;
        repeat (2) @(negedge pclk);
        vsync = 0;
        repeat (5) @(negedge pclk);
        if (!odd_byte_error || !last_error_code[0])
            $fatal(1, "odd-byte line/frame was not detected");

        $display("PASS tb_dvp_capture pixels=%0d frames=2 reset_recovery=ok odd_byte_detection=ok", observed_pixels);
        $finish;
    end
endmodule
