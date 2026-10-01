`timescale 1ns/1ps

// Lightweight RAM stub: this test targets full-frame grayscale, sampling,
// packing, and commit accounting. RAM read/mapping remains covered by the
// accepted landscape framebuffer test.
module frame_ram20 #(
    parameter int DEPTH = 15360,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic wr_clk, wr_en,
    input logic [ADDR_WIDTH-1:0] wr_addr,
    input logic [19:0] wr_data,
    input logic rd_clk, rd_en,
    input logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [19:0] rd_data
);
    assign rd_data = 20'h0;
endmodule

module tb_gray_full_frame_integration;
    logic wr_clk = 1'b0, rd_clk = 1'b0;
    logic wr_rst_n = 1'b0, rd_rst_n = 1'b0;
    logic [15:0] raw_pixel = 16'd0;
    logic raw_valid = 1'b0, raw_sof = 1'b0, raw_eof = 1'b0;
    logic raw_good = 1'b0;
    logic [11:0] raw_x = 12'd0, raw_y = 12'd0;
    logic [7:0] gray;
    logic [15:0] gray_rgb565;
    logic gray_valid, gray_sof, gray_eol, gray_eof, gray_good;
    logic [11:0] gray_x, gray_y;

    logic buffer_error_wr, frame_committed_wr;
    logic [3:0] buffer_error_code_wr;
    logic [31:0] last_sampled_pixel_count_wr;
    logic [15:0] last_written_word_count_wr;
    logic [31:0] committed_frame_count_wr, dropped_frame_count;
    logic [11:0] rd_x = 12'd0, rd_y = 12'd0;
    logic rd_de = 1'b0, rd_frame_tick = 1'b0;
    logic [15:0] rd_pixel;
    logic rd_pixel_valid, display_has_frame;
    logic [31:0] displayed_frame_count;
    logic commit_seen = 1'b0;
    integer gray_count = 0;

    always #2 wr_clk = ~wr_clk;
    always #3 rd_clk = ~rd_clk;

    rgb565_to_gray8 u_gray (
        .clk(wr_clk), .rst_n(wr_rst_n), .rgb565(raw_pixel),
        .pixel_valid(raw_valid), .pixel_x(raw_x), .pixel_y(raw_y),
        .start_of_frame(raw_sof), .frame_end(raw_eof),
        .frame_good(raw_good), .gray(gray), .gray_rgb565(gray_rgb565),
        .gray_valid(gray_valid), .gray_x(gray_x), .gray_y(gray_y),
        .gray_start_of_frame(gray_sof), .gray_end_of_line(gray_eol),
        .gray_frame_end(gray_eof), .gray_frame_good(gray_good)
    );

    packed_pingpong_framebuffer u_framebuffer (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n),
        .wr_pixel(gray_rgb565), .wr_pixel_valid(gray_valid),
        .wr_start_of_frame(gray_sof), .wr_frame_end(gray_eof),
        .wr_frame_good(gray_good), .wr_x(gray_x), .wr_y(gray_y),
        .buffer_error_wr(buffer_error_wr),
        .buffer_error_code_wr(buffer_error_code_wr),
        .frame_committed_wr(frame_committed_wr),
        .last_sampled_pixel_count_wr(last_sampled_pixel_count_wr),
        .last_written_word_count_wr(last_written_word_count_wr),
        .committed_frame_count_wr(committed_frame_count_wr),
        .dropped_frame_count(dropped_frame_count),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n), .rd_x(rd_x), .rd_y(rd_y),
        .rd_de(rd_de), .rd_frame_tick(rd_frame_tick), .rd_pixel(rd_pixel),
        .rd_pixel_valid(rd_pixel_valid), .display_has_frame(display_has_frame),
        .displayed_frame_count(displayed_frame_count)
    );

    function automatic [15:0] pattern(input integer x, input integer y);
        pattern = {x[8:4], y[7:2], (x[4:0] ^ y[4:0])};
    endfunction

    function automatic [7:0] reference_gray(input [15:0] p);
        integer r8, g8, b8, sum;
        begin
            r8 = {p[15:11], p[15:13]};
            g8 = {p[10:5], p[10:9]};
            b8 = {p[4:0], p[4:2]};
            sum = 77*r8 + 150*g8 + 29*b8 + 128;
            reference_gray = sum >> 8;
        end
    endfunction

    always @(posedge wr_clk) begin
        #1;
        if (!wr_rst_n) begin
            gray_count = 0;
            commit_seen = 1'b0;
        end else begin
            if (gray_valid) begin
                if (gray !== reference_gray(pattern(gray_x, gray_y)))
                    $fatal(1, "full-frame gray mismatch at (%0d,%0d)", gray_x, gray_y);
                if (gray_count == 0 && (!gray_sof || gray_x != 0 || gray_y != 0))
                    $fatal(1, "bad first grayscale pixel/control");
                if (gray_count == 307199 &&
                    (!gray_eof || !gray_good || gray_x != 639 || gray_y != 479))
                    $fatal(1, "bad final grayscale pixel/control");
                if (gray_eol !== (gray_x == 639))
                    $fatal(1, "bad gray line boundary at (%0d,%0d)", gray_x, gray_y);
                gray_count = gray_count + 1;
            end
            if (frame_committed_wr)
                commit_seen = 1'b1;
        end
    end

    integer x_i, y_i;
    initial begin
        repeat (4) @(posedge wr_clk);
        @(negedge wr_clk); wr_rst_n = 1'b1; rd_rst_n = 1'b1;

        // A complete 640x480 frame with EOF coincident with the final pixel.
        // This specifically catches premature commit ahead of the gray pipe.
        for (y_i = 0; y_i < 480; y_i = y_i + 1) begin
            for (x_i = 0; x_i < 640; x_i = x_i + 1) begin
                @(negedge wr_clk);
                raw_pixel = pattern(x_i, y_i);
                raw_x = x_i;
                raw_y = y_i;
                raw_valid = 1'b1;
                raw_sof = (x_i == 0 && y_i == 0);
                raw_eof = (x_i == 639 && y_i == 479);
                raw_good = raw_eof;
            end
        end
        @(negedge wr_clk);
        raw_valid = 1'b0; raw_sof = 1'b0; raw_eof = 1'b0; raw_good = 1'b0;
        repeat (4) @(posedge wr_clk);

        if (gray_count != 307200)
            $fatal(1, "gray count=%0d expected=307200", gray_count);
        if (!commit_seen || committed_frame_count_wr != 1)
            $fatal(1, "complete grayscale frame did not commit");
        if (last_sampled_pixel_count_wr != 76800 ||
            last_written_word_count_wr != 15360)
            $fatal(1, "bad sample/pack count samples=%0d words=%0d",
                   last_sampled_pixel_count_wr, last_written_word_count_wr);
        if (buffer_error_wr || buffer_error_code_wr != 0 ||
            dropped_frame_count != 0)
            $fatal(1, "unexpected buffer result error=%b code=%h drop=%0d",
                   buffer_error_wr, buffer_error_code_wr, dropped_frame_count);

        repeat (4) @(posedge rd_clk);
        @(negedge rd_clk); rd_frame_tick = 1'b1;
        @(negedge rd_clk); rd_frame_tick = 1'b0;
        repeat (3) @(posedge rd_clk);
        if (!display_has_frame || displayed_frame_count != 1)
            $fatal(1, "display did not accept the complete grayscale frame");

        $display("PASS: 307200 gray pixels -> 76800 sampled pixels -> 15360 packed 80-bit words -> complete display frame");
        $finish;
    end

    initial begin
        #10_000_000;
        $fatal(1, "timeout");
    end
endmodule
