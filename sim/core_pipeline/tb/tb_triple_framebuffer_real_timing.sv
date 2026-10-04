`timescale 1ns/1ps
module tb_triple_framebuffer_real_timing;
    localparam int W = 320;
    localparam int H = 240;
    localparam int HTS = 1896;
    localparam int VTS = 984;
    localparam int ACTIVE_SOURCE_LINES = 480;
    localparam int LINE_PAIR_CYCLES = 2 * HTS;
    localparam int PAIRED_ACTIVE_CYCLES = W * 4;
    localparam int PAIR_BLANK_CYCLES = LINE_PAIR_CYCLES - PAIRED_ACTIVE_CYCLES;
    localparam int VERTICAL_BLANK_CYCLES = (VTS - ACTIVE_SOURCE_LINES) * HTS;
    localparam int HDMI_FRAME_CYCLES = 800 * 525;
    localparam int FRAMES = 12;

    logic wr_clk = 1'b0;
    logic rd_clk = 1'b0;
    logic wr_rst_n = 1'b0, rd_rst_n = 1'b0;
    logic [7:0] wr_gray = 0;
    logic wr_edge = 0, wr_valid = 0, wr_start_of_frame = 0;
    logic wr_frame_end = 0, wr_frame_good = 0;
    logic [10:0] wr_frame_threshold = 11'd128;
    logic [11:0] wr_x = 0, wr_y = 0;
    logic [11:0] rd_x = 0, rd_y = 0;
    logic rd_de = 0, rd_frame_tick = 0;

    logic old_error, old_committed, old_rd_edge, old_gray_view;
    logic old_edge_view, old_pixel_valid, old_has_frame;
    logic [3:0] old_error_code;
    logic [7:0] old_rd_gray;
    logic [31:0] old_last_pixels, old_commits, old_drops, old_displays;
    logic [15:0] old_last_words;
    logic [10:0] old_display_threshold;

    logic new_error, new_committed, new_rd_edge, new_gray_view;
    logic new_edge_view, new_pixel_valid, new_has_frame;
    logic [3:0] new_error_code;
    logic [7:0] new_rd_gray;
    logic [31:0] new_last_pixels, new_commits, new_drops, new_displays;
    logic [15:0] new_last_words;
    logic [10:0] new_display_threshold;
    integer rd_count = 0;

    // 93.2832 MHz makes the official 1896*984 frame exactly 20 ms (50 fps).
    // Implementation remains constrained at the more conservative 100 MHz.
    always #5.36002195 wr_clk = ~wr_clk;
    always #19.84127 rd_clk = ~rd_clk;           // 25.2 MHz HDMI pixel clock

    split_pingpong_framebuffer #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H),
        .DISPLAY_WIDTH(640), .DISPLAY_HEIGHT(480),
        .SIM_BEHAVIORAL_RAM(1'b1)
    ) old_dut (
        .wr_clk, .wr_rst_n, .wr_gray, .wr_edge, .wr_valid,
        .wr_start_of_frame, .wr_frame_end, .wr_frame_good,
        .wr_frame_threshold, .wr_x, .wr_y,
        .buffer_error_wr(old_error), .buffer_error_code_wr(old_error_code),
        .frame_committed_wr(old_committed),
        .last_sampled_pixel_count_wr(old_last_pixels),
        .last_written_word_count_wr(old_last_words),
        .committed_frame_count_wr(old_commits),
        .dropped_frame_count(old_drops),
        .rd_clk, .rd_rst_n, .rd_x, .rd_y, .rd_de, .rd_frame_tick,
        .rd_gray(old_rd_gray), .rd_edge(old_rd_edge),
        .rd_gray_view(old_gray_view), .rd_edge_view(old_edge_view),
        .rd_pixel_valid(old_pixel_valid), .display_has_frame(old_has_frame),
        .displayed_frame_count(old_displays),
        .displayed_frame_threshold(old_display_threshold)
    );

    split_triple_framebuffer #(
        .IMAGE_WIDTH(W), .IMAGE_HEIGHT(H),
        .DISPLAY_WIDTH(640), .DISPLAY_HEIGHT(480),
        .SIM_BEHAVIORAL_RAM(1'b1)
    ) new_dut (
        .wr_clk, .wr_rst_n, .wr_gray, .wr_edge, .wr_valid,
        .wr_start_of_frame, .wr_frame_end, .wr_frame_good,
        .wr_frame_threshold, .wr_x, .wr_y,
        .buffer_error_wr(new_error), .buffer_error_code_wr(new_error_code),
        .frame_committed_wr(new_committed),
        .last_sampled_pixel_count_wr(new_last_pixels),
        .last_written_word_count_wr(new_last_words),
        .committed_frame_count_wr(new_commits),
        .dropped_frame_count(new_drops),
        .rd_clk, .rd_rst_n, .rd_x, .rd_y, .rd_de, .rd_frame_tick,
        .rd_gray(new_rd_gray), .rd_edge(new_rd_edge),
        .rd_gray_view(new_gray_view), .rd_edge_view(new_edge_view),
        .rd_pixel_valid(new_pixel_valid), .display_has_frame(new_has_frame),
        .displayed_frame_count(new_displays),
        .displayed_frame_threshold(new_display_threshold)
    );

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_count <= 137000; // deliberately non-aligned starting phase
            rd_frame_tick <= 1'b0;
        end else if (rd_count == HDMI_FRAME_CYCLES-1) begin
            rd_count <= 0;
            rd_frame_tick <= 1'b1;
        end else begin
            rd_count <= rd_count + 1;
            rd_frame_tick <= 1'b0;
        end
    end

    task automatic idle_wr(input integer cycles);
        repeat (cycles) begin
            @(negedge wr_clk);
            wr_valid = 1'b0;
            wr_start_of_frame = 1'b0;
            wr_frame_end = 1'b0;
            wr_frame_good = 1'b0;
        end
    endtask

    task automatic send_sensor_timed_frame(input integer frame_id);
        integer x, y, gap;
        begin
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    @(negedge wr_clk);
                    wr_valid = 1'b1;
                    wr_start_of_frame = (x == 0) && (y == 0);
                    wr_frame_end = (x == W-1) && (y == H-1);
                    wr_frame_good = 1'b1;
                    wr_x = x;
                    wr_y = y;
                    wr_gray = frame_id + x + y;
                    wr_edge = (x ^ y) & 1;
                    idle_wr(3); // one 2x2 preview sample per four PCLKs
                end
                gap = PAIR_BLANK_CYCLES;
                idle_wr(gap);
            end
            // The algorithm EOF occurred with the final paired pixel above.
            // Preserve the official VGA table's remaining frame blanking.
            idle_wr(VERTICAL_BLANK_CYCLES);
        end
    endtask

    always @(posedge wr_clk) begin
        if (wr_rst_n && new_dut.capture_active) begin
            if (new_dut.write_bank == new_dut.active_bank_wr_sync)
                $fatal(1, "triple buffer writes the displayed bank");
            if (!new_dut.no_frame_pending &&
                (new_dut.write_bank == new_dut.ready_bank_wr))
                $fatal(1, "triple buffer writes the pending bank");
        end
    end

    initial begin
        repeat (8) @(posedge wr_clk);
        wr_rst_n = 1'b1;
        rd_rst_n = 1'b1;
        idle_wr(1000);

        for (integer frame = 0; frame < FRAMES; frame = frame + 1)
            send_sensor_timed_frame(frame);

        // Drain the last pending frame at an HDMI frame boundary.
        repeat (HDMI_FRAME_CYCLES + 20) @(posedge rd_clk);

        if (old_drops == 0)
            $fatal(1, "old SOF-gated double buffer did not reproduce busy drops");
        if ((old_commits + old_drops) != FRAMES)
            $fatal(1, "old accounting mismatch commit=%0d drop=%0d",
                   old_commits, old_drops);
        if (new_drops != 0 || new_commits != FRAMES || new_displays != FRAMES)
            $fatal(1, "triple mismatch commit=%0d drop=%0d display=%0d",
                   new_commits, new_drops, new_displays);
        if (new_error || (new_last_pixels != W*H) ||
            (new_last_words != (W*H/2)))
            $fatal(1, "triple completeness mismatch err=%0b pixels=%0d words=%0d",
                   new_error, new_last_pixels, new_last_words);

        $display("PASS: actual-duty 50fps/60Hz: old commit=%0d drop=%0d; triple commit=%0d drop=%0d display=%0d",
                 old_commits, old_drops, new_commits, new_drops, new_displays);
        $finish;
    end

    initial begin
        #400000000;
        $fatal(1, "timeout");
    end
endmodule
