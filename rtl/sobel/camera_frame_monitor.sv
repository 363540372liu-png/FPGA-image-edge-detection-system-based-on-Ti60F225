`timescale 1ns/1ps
module camera_frame_monitor #(
    parameter int unsigned ACTIVE_WIDTH  = 640,
    parameter int unsigned ACTIVE_HEIGHT = 480
) (
    input  logic        pclk,
    input  logic        rst_n,
    input  logic        pixel_valid,
    input  logic        start_of_frame,
    input  logic        line_end,
    input  logic        frame_end,
    input  logic        odd_byte_error,
    output logic [31:0] frame_count,
    output logic [15:0] last_line_pixels,
    output logic [15:0] last_frame_lines,
    output logic [31:0] last_frame_pixels,
    output logic [15:0] last_min_line_pixels,
    output logic [15:0] last_max_line_pixels,
    output logic [3:0]  last_error_code,
    output logic        frame_good,
    output logic        snapshot_toggle,
    output logic [31:0] line_error_count,
    output logic [31:0] frame_error_count
);
    localparam int unsigned EXPECTED_PIXELS = ACTIVE_WIDTH * ACTIVE_HEIGHT;

    logic [15:0] line_pixels;
    logic [15:0] frame_lines;
    logic [31:0] frame_pixels;
    logic [15:0] min_line_pixels;
    logic [15:0] max_line_pixels;
    logic        line_error_in_frame;

    wire [16:0] line_pixels_now = {1'b0, line_pixels} + pixel_valid;
    wire [32:0] frame_pixels_now = {1'b0, frame_pixels} + pixel_valid;
    wire [16:0] frame_lines_now = {1'b0, frame_lines} + line_end;
    wire line_bad_now = line_end && (line_pixels_now != ACTIVE_WIDTH);
    assign frame_good = frame_end && !odd_byte_error &&
                        !line_error_in_frame && !line_bad_now &&
                        (frame_lines_now == ACTIVE_HEIGHT) &&
                        (frame_pixels_now == EXPECTED_PIXELS);
    wire [15:0] min_line_now = line_end &&
        (line_pixels_now[15:0] < min_line_pixels) ?
        line_pixels_now[15:0] : min_line_pixels;
    wire [15:0] max_line_now = line_end &&
        (line_pixels_now[15:0] > max_line_pixels) ?
        line_pixels_now[15:0] : max_line_pixels;

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count          <= 32'd0;
            line_pixels          <= 16'd0;
            frame_lines          <= 16'd0;
            frame_pixels         <= 32'd0;
            min_line_pixels      <= 16'hffff;
            max_line_pixels      <= 16'd0;
            line_error_in_frame  <= 1'b0;
            last_line_pixels     <= 16'd0;
            last_frame_lines     <= 16'd0;
            last_frame_pixels    <= 32'd0;
            last_min_line_pixels <= 16'd0;
            last_max_line_pixels <= 16'd0;
            last_error_code      <= 4'h0;
            snapshot_toggle      <= 1'b0;
            line_error_count     <= 32'd0;
            frame_error_count    <= 32'd0;
        end else begin
            if (start_of_frame) begin
                // start_of_frame is aligned with the first valid pixel.
                line_pixels         <= 16'd1;
                frame_lines         <= 16'd0;
                frame_pixels        <= 32'd1;
                min_line_pixels     <= 16'hffff;
                max_line_pixels     <= 16'd0;
                line_error_in_frame <= 1'b0;
            end else begin
                if (pixel_valid) begin
                    line_pixels  <= line_pixels + 1'b1;
                    frame_pixels <= frame_pixels + 1'b1;
                end

                if (line_end) begin
                    last_line_pixels <= line_pixels_now[15:0];
                    line_pixels <= 16'd0;
                    frame_lines <= frame_lines + 1'b1;
                    min_line_pixels <= min_line_now;
                    max_line_pixels <= max_line_now;
                    if (line_bad_now) begin
                        line_error_in_frame <= 1'b1;
                        line_error_count <= line_error_count + 1'b1;
                    end
                end
            end

            if (frame_end) begin
                frame_count          <= frame_count + 1'b1;
                last_frame_lines     <= frame_lines_now[15:0];
                last_frame_pixels    <= frame_pixels_now[31:0];
                last_min_line_pixels <= min_line_now;
                last_max_line_pixels <= max_line_now;
                last_error_code[0]   <= odd_byte_error;
                last_error_code[1]   <= line_error_in_frame || line_bad_now;
                last_error_code[2]   <= (frame_lines_now != ACTIVE_HEIGHT);
                last_error_code[3]   <= (frame_pixels_now != EXPECTED_PIXELS);
                snapshot_toggle      <= ~snapshot_toggle;

                if (odd_byte_error || line_error_in_frame || line_bad_now ||
                    (frame_lines_now != ACTIVE_HEIGHT) ||
                    (frame_pixels_now != EXPECTED_PIXELS))
                    frame_error_count <= frame_error_count + 1'b1;

                line_pixels         <= 16'd0;
                frame_lines         <= 16'd0;
                frame_pixels        <= 32'd0;
                min_line_pixels     <= 16'hffff;
                max_line_pixels     <= 16'd0;
                line_error_in_frame <= 1'b0;
            end
        end
    end
endmodule
