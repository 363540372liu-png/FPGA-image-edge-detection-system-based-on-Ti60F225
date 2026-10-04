`timescale 1ns/1ps
module tb_split_frame_rate_phase;
    localparam int W = 4;
    localparam int H = 2;
    logic wr_clk = 1'b0, rd_clk = 1'b0;
    logic wr_rst_n = 1'b0, rd_rst_n = 1'b0;
    logic [7:0] wr_gray;
    logic wr_edge, wr_valid, wr_start_of_frame, wr_frame_end, wr_frame_good;
    logic [10:0] wr_frame_threshold;
    logic [11:0] wr_x, wr_y;
    logic buffer_error_wr;
    logic [3:0] buffer_error_code_wr;
    logic frame_committed_wr;
    logic [31:0] last_sampled_pixel_count_wr;
    logic [15:0] last_written_word_count_wr;
    logic [31:0] committed_frame_count_wr, dropped_frame_count;
    logic [11:0] rd_x, rd_y;
    logic rd_de, rd_frame_tick;
    logic [7:0] rd_gray;
    logic rd_edge, rd_gray_view, rd_edge_view, rd_pixel_valid;
    logic display_has_frame;
    logic [31:0] displayed_frame_count;
    logic [10:0] displayed_frame_threshold;
    integer tick_phase;
    integer tick_count;

    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    split_pingpong_framebuffer #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H),
        .DISPLAY_WIDTH(8), .DISPLAY_HEIGHT(4), .DISPLAY_MODE(0)
    ) dut (.*);

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            tick_count <= tick_phase;
            rd_frame_tick <= 1'b0;
        end else if (tick_count == 19) begin
            tick_count <= 0;
            rd_frame_tick <= 1'b1;
        end else begin
            tick_count <= tick_count + 1;
            rd_frame_tick <= 1'b0;
        end
    end

    task automatic reset_trial(input integer phase);
        tick_phase = phase;
        wr_rst_n = 1'b0;
        rd_rst_n = 1'b0;
        wr_valid = 1'b0;
        wr_start_of_frame = 1'b0;
        wr_frame_end = 1'b0;
        wr_frame_good = 1'b0;
        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1'b1;
        rd_rst_n = 1'b1;
        repeat (5) @(posedge wr_clk);
    endtask

    task automatic send_frame(
        input integer frame_id,
        input integer sof_period_wr_cycles,
        input logic good
    );
        integer i;
        for (i = 0; i < W*H; i = i + 1) begin
            @(negedge wr_clk);
            wr_valid = 1'b1;
            wr_start_of_frame = (i == 0);
            wr_frame_end = 1'b0;
            wr_frame_good = good;
            wr_x = i % W;
            wr_y = i / W;
            wr_gray = frame_id + i;
            wr_edge = i[0];
            wr_frame_threshold = 11'd128;
        end
        @(negedge wr_clk);
        wr_valid = 1'b0;
        wr_start_of_frame = 1'b0;
        wr_frame_end = 1'b1;
        wr_frame_good = good;
        @(negedge wr_clk);
        wr_frame_end = 1'b0;
        wr_frame_good = 1'b0;
        repeat (sof_period_wr_cycles - (W*H + 2)) @(negedge wr_clk);
    endtask

    initial begin
        wr_gray = 0;
        wr_edge = 0;
        wr_valid = 0;
        wr_start_of_frame = 0;
        wr_frame_end = 0;
        wr_frame_good = 0;
        wr_frame_threshold = 128;
        wr_x = 0;
        wr_y = 0;
        rd_x = 0;
        rd_y = 0;
        rd_de = 0;
        rd_frame_tick = 0;
        tick_phase = 0;

        // Scale 30 Hz producer / 60 Hz display to 560 ns / 280 ns and sweep
        // four display phases. No busy drop is permitted at this rate ratio.
        for (integer phase = 0; phase < 20; phase = phase + 5) begin
            reset_trial(phase);
            for (integer f = 0; f < 12; f = f + 1)
                send_frame(f, 56, 1'b1);
            repeat (80) @(posedge rd_clk);
            if (committed_frame_count_wr != 12 || dropped_frame_count != 0 ||
                displayed_frame_count != 12)
                $fatal(1, "30/60 phase %0d mismatch commit=%0d drop=%0d display=%0d",
                       phase, committed_frame_count_wr,
                       dropped_frame_count, displayed_frame_count);
        end

        // When the producer is intentionally faster than the display, the
        // existing ownership policy must count whole-frame drops explicitly.
        reset_trial(3);
        for (integer f = 0; f < 20; f = f + 1)
            send_frame(f, 20, 1'b1);
        repeat (100) @(posedge rd_clk);
        if (dropped_frame_count == 0)
            $fatal(1, "overload did not report a busy drop");
        if ((committed_frame_count_wr + dropped_frame_count) != 20)
            $fatal(1, "overload accounting mismatch commit=%0d drop=%0d",
                   committed_frame_count_wr, dropped_frame_count);
        if (displayed_frame_count != committed_frame_count_wr)
            $fatal(1, "display did not drain committed frames");

        // A rejected bad frame is not a busy drop and the following good frame
        // must still commit and display.
        reset_trial(9);
        send_frame(1, 56, 1'b1);
        send_frame(2, 56, 1'b0);
        send_frame(3, 56, 1'b1);
        repeat (80) @(posedge rd_clk);
        if (committed_frame_count_wr != 2 || dropped_frame_count != 0 ||
            displayed_frame_count != 2 || buffer_error_wr)
            $fatal(1, "bad-frame recovery mismatch commit=%0d drop=%0d display=%0d err=%0b",
                   committed_frame_count_wr, dropped_frame_count,
                   displayed_frame_count, buffer_error_wr);

        $display("PASS: 30/60 phase sweep, overload accounting, bad-frame recovery");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "timeout");
    end
endmodule
