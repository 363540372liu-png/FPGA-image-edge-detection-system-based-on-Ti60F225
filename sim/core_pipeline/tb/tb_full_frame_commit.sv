`timescale 1ns/1ps
// This test targets the full-size write-side sample/pack/commit accounting.
// The reduced asynchronous RAM/read path is covered by the companion test,
// so a lightweight storage stub keeps this 307,200-pixel run practical.
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

module tb_full_frame_commit;
    logic wr_clk = 0, rd_clk = 0;
    logic wr_rst_n = 0, rd_rst_n = 0;
    logic [15:0] wr_pixel;
    logic wr_pixel_valid, wr_start_of_frame, wr_frame_end;
    logic wr_frame_good = 1'b1;
    logic [10:0] wr_frame_threshold = 11'd128;
    logic [11:0] wr_x, wr_y;
    logic buffer_error_wr, frame_committed_wr;
    logic [3:0] buffer_error_code_wr;
    logic [31:0] last_sampled_pixel_count_wr;
    logic [15:0] last_written_word_count_wr;
    logic [31:0] committed_frame_count_wr;
    logic [31:0] dropped_frame_count;
    logic [11:0] rd_x, rd_y;
    logic rd_de, rd_frame_tick;
    logic [15:0] rd_pixel;
    logic rd_pixel_valid, display_has_frame;
    logic [31:0] displayed_frame_count;
    logic [10:0] displayed_frame_threshold;

    always #2 wr_clk = ~wr_clk;
    always #3 rd_clk = ~rd_clk;

    packed_pingpong_framebuffer dut (.*);

    function automatic [15:0] pattern(input int x, input int y);
        pattern = {x[8:4], y[7:2], (x[4:0] ^ y[4:0])};
    endfunction

    initial begin : test
        integer x_i, y_i;
        wr_pixel = 0; wr_pixel_valid = 0; wr_start_of_frame = 0;
        wr_frame_end = 0; wr_x = 0; wr_y = 0;
        rd_x = 0; rd_y = 0; rd_de = 0; rd_frame_tick = 0;
        repeat (4) @(posedge wr_clk);
        wr_rst_n = 1; rd_rst_n = 1;

        // Feed all 640x480 coordinates. Only even x/even y are stored.
        for (y_i = 0; y_i < 480; y_i = y_i + 1) begin
            for (x_i = 0; x_i < 640; x_i = x_i + 1) begin
                @(negedge wr_clk);
                wr_pixel <= pattern(x_i, y_i);
                wr_x <= x_i; wr_y <= y_i;
                wr_pixel_valid <= 1'b1;
                wr_start_of_frame <= (x_i == 0 && y_i == 0);
                wr_frame_end <= 1'b0;
            end
        end
        @(negedge wr_clk);
        wr_pixel_valid <= 0; wr_start_of_frame <= 0; wr_frame_end <= 1;
        @(negedge wr_clk);
        wr_frame_end <= 0;
        #1;

        if (!frame_committed_wr)
            $fatal(1, "exact 640x480 frame did not commit");
        if ((last_sampled_pixel_count_wr != 76800) ||
            (last_written_word_count_wr != 15360) ||
            (buffer_error_code_wr != 0))
            $fatal(1, "bad full-frame snapshot samples=%0d words=%0d code=%h",
                   last_sampled_pixel_count_wr, last_written_word_count_wr,
                   buffer_error_code_wr);
        if (buffer_error_wr || dropped_frame_count != 0)
            $fatal(1, "unexpected frame-buffer error/drop");
        if (committed_frame_count_wr != 1)
            $fatal(1, "commit counter=%0d expected=1", committed_frame_count_wr);

        repeat (4) @(posedge rd_clk);
        @(negedge rd_clk); rd_frame_tick <= 1;
        @(negedge rd_clk); rd_frame_tick <= 0;
        repeat (3) @(posedge rd_clk);
        if (!display_has_frame || displayed_frame_count != 1)
            $fatal(1, "complete frame was not accepted at display boundary");

        $display("PASS: exact 640x480 input commits 320x240 RGB565 frame (15360 packed words)");
        $finish;
    end

    initial begin
        #10_000_000;
        $fatal(1, "timeout");
    end
endmodule
