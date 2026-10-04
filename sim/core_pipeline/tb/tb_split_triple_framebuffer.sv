`timescale 1ns/1ps
module tb_split_triple_framebuffer;
    localparam int W = 4;
    localparam int H = 2;
    logic wr_clk = 0, rd_clk = 0, wr_rst_n = 0, rd_rst_n = 0;
    logic [7:0] wr_gray = 0;
    logic wr_edge = 0, wr_valid = 0, wr_start_of_frame = 0;
    logic wr_frame_end = 0, wr_frame_good = 0;
    logic [10:0] wr_frame_threshold = 128;
    logic [11:0] wr_x = 0, wr_y = 0, rd_x = 0, rd_y = 0;
    logic rd_de = 0, rd_frame_tick = 0;
    logic buffer_error_wr, frame_committed_wr, rd_edge;
    logic [3:0] buffer_error_code_wr;
    logic [31:0] last_sampled_pixel_count_wr, committed_frame_count_wr;
    logic [31:0] dropped_frame_count, displayed_frame_count;
    logic [15:0] last_written_word_count_wr;
    logic [7:0] rd_gray;
    logic rd_gray_view, rd_edge_view, rd_pixel_valid, display_has_frame;
    logic [10:0] displayed_frame_threshold;
    integer rd_period = 30;
    integer rd_counter = 0;

    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    split_triple_framebuffer #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H),
        .DISPLAY_WIDTH(8), .DISPLAY_HEIGHT(4),
        .SIM_BEHAVIORAL_RAM(1'b1)
    ) dut (.*);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_counter <= 0;
            rd_frame_tick <= 0;
        end else if (rd_counter == rd_period-1) begin
            rd_counter <= 0;
            rd_frame_tick <= 1;
        end else begin
            rd_counter <= rd_counter + 1;
            rd_frame_tick <= 0;
        end
    end

    task automatic send_frame(input integer id, input logic good,
                              input integer interframe_cycles);
        for (integer i = 0; i < W*H; i = i + 1) begin
            @(negedge wr_clk);
            wr_valid = 1;
            wr_start_of_frame = (i == 0);
            wr_frame_end = (i == W*H-1);
            wr_frame_good = good;
            wr_x = i % W;
            wr_y = i / W;
            wr_gray = id + i;
            wr_edge = i[0];
        end
        @(negedge wr_clk);
        wr_valid = 0;
        wr_start_of_frame = 0;
        wr_frame_end = 0;
        wr_frame_good = 0;
        repeat (interframe_cycles) @(negedge wr_clk);
    endtask

    task automatic reset_dut;
        wr_rst_n = 0;
        rd_rst_n = 0;
        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1;
        rd_rst_n = 1;
        repeat (5) @(posedge wr_clk);
    endtask

    initial begin
        reset_dut();
        // A new frame starts while the prior frame is pending, but the prior
        // frame is acknowledged before this frame completes. Both must commit.
        rd_period = 18;
        for (integer f = 0; f < 10; f = f + 1)
            send_frame(f, 1'b1, 16);
        repeat (60) @(posedge rd_clk);
        if (committed_frame_count_wr != 10 || dropped_frame_count != 0 ||
            displayed_frame_count != 10)
            $fatal(1, "normal flow mismatch commit=%0d drop=%0d display=%0d",
                   committed_frame_count_wr, dropped_frame_count,
                   displayed_frame_count);

        // Deliberately make display acceptance slower than an entire new frame.
        reset_dut();
        rd_period = 200;
        for (integer f = 0; f < 8; f = f + 1)
            send_frame(f, 1'b1, 0);
        repeat (500) @(posedge rd_clk);
        if (dropped_frame_count == 0)
            $fatal(1, "true overload was not counted");
        if ((committed_frame_count_wr + dropped_frame_count) != 8)
            $fatal(1, "overload accounting mismatch commit=%0d drop=%0d",
                   committed_frame_count_wr, dropped_frame_count);

        // A malformed frame is rejected independently and the next good frame
        // can recover once the pending frame has drained.
        reset_dut();
        rd_period = 18;
        send_frame(1, 1'b1, 20);
        send_frame(2, 1'b0, 20);
        send_frame(3, 1'b1, 20);
        repeat (80) @(posedge rd_clk);
        if (committed_frame_count_wr != 2 || dropped_frame_count != 0 ||
            displayed_frame_count != 2 || buffer_error_wr)
            $fatal(1, "bad-frame recovery mismatch commit=%0d drop=%0d display=%0d err=%0b",
                   committed_frame_count_wr, dropped_frame_count,
                   displayed_frame_count, buffer_error_wr);

        $display("PASS: pending-at-SOF acceptance, true-overload accounting, and bad-frame recovery");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "timeout");
    end
endmodule
