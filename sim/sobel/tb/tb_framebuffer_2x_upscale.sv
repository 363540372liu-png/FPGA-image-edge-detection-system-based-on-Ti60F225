`timescale 1ns/1ps

module tb_framebuffer_2x_upscale;
    localparam int SW = 10;
    localparam int SH = 4;
    localparam int IW = 5;
    localparam int IH = 2;
    localparam int DW = 10;
    localparam int DH = 4;

    logic wr_clk = 0, rd_clk = 0;
    logic wr_rst_n = 0, rd_rst_n = 0;
    logic [15:0] wr_pixel = 0;
    logic wr_pixel_valid = 0, wr_start_of_frame = 0, wr_frame_end = 0;
    logic wr_frame_good = 1;
    logic [11:0] wr_x = 0, wr_y = 0;
    logic buffer_error_wr, frame_committed_wr;
    logic [3:0] buffer_error_code_wr;
    logic [31:0] last_sampled_pixel_count_wr;
    logic [15:0] last_written_word_count_wr;
    logic [31:0] committed_frame_count_wr, dropped_frame_count;
    logic [11:0] rd_x = 0, rd_y = 0;
    logic rd_de = 0, rd_frame_tick = 0;
    logic [15:0] rd_pixel;
    logic rd_pixel_valid, display_has_frame;
    logic [31:0] displayed_frame_count;

    always #3.5 wr_clk = ~wr_clk;
    always #5.5 rd_clk = ~rd_clk;

    packed_pingpong_framebuffer #(
        .SOURCE_WIDTH(SW), .SOURCE_HEIGHT(SH),
        .SAMPLE_X_STEP(2), .SAMPLE_Y_STEP(2),
        .IMAGE_WIDTH(IW), .IMAGE_HEIGHT(IH),
        .DISPLAY_WIDTH(DW), .DISPLAY_HEIGHT(DH),
        .DISPLAY_SCALE(2)
    ) dut (.*);

    function automatic [15:0] pattern(input int frame, input int x, input int y);
        integer sum;
        begin
            sum = x + y;
            pattern = {frame[0], x[4:0], y[4:0], sum[4:0]};
        end
    endfunction

    task automatic send_frame(input int frame);
        int x, y;
        begin
            for (y = 0; y < SH; y++) begin
                for (x = 0; x < SW; x++) begin
                    @(negedge wr_clk);
                    wr_pixel <= pattern(frame, x, y);
                    wr_x <= x;
                    wr_y <= y;
                    wr_pixel_valid <= 1'b1;
                    wr_start_of_frame <= (x == 0 && y == 0);
                    wr_frame_end <= 1'b0;
                end
            end
            @(negedge wr_clk);
            wr_pixel_valid <= 1'b0;
            wr_start_of_frame <= 1'b0;
            wr_frame_end <= 1'b1;
            @(negedge wr_clk);
            wr_frame_end <= 1'b0;
        end
    endtask

    task automatic display_boundary;
        begin
            @(negedge rd_clk);
            rd_frame_tick <= 1'b1;
            @(negedge rd_clk);
            rd_frame_tick <= 1'b0;
            repeat (3) @(posedge rd_clk);
        end
    endtask

    task automatic check_output_pixel(input int frame, input int ox, input int oy);
        logic [15:0] expected;
        begin
            expected = pattern(frame, (ox >> 1) * 2, (oy >> 1) * 2);
            @(negedge rd_clk);
            rd_x <= ox;
            rd_y <= oy;
            rd_de <= 1'b1;
            @(posedge rd_clk); #1;
            if (!rd_pixel_valid)
                $fatal(1, "output (%0d,%0d) not valid", ox, oy);
            if (rd_pixel !== expected)
                $fatal(1, "frame%0d output(%0d,%0d)=%04h expected=%04h",
                       frame, ox, oy, rd_pixel, expected);
        end
    endtask

    initial begin
        repeat (4) @(posedge wr_clk);
        wr_rst_n = 1;
        rd_rst_n = 1;

        // Before the first complete frame is accepted, no display read is valid.
        @(negedge rd_clk); rd_de <= 1'b1; rd_x <= 0; rd_y <= 0;
        @(posedge rd_clk); #1;
        if (rd_pixel_valid || display_has_frame)
            $fatal(1, "framebuffer became visible before first frame boundary");

        send_frame(0);
        if (!frame_committed_wr || buffer_error_wr ||
            last_sampled_pixel_count_wr != IW*IH ||
            last_written_word_count_wr != (IW*IH)/5)
            $fatal(1, "bad first commit samples=%0d words=%0d code=%h",
                   last_sampled_pixel_count_wr, last_written_word_count_wr,
                   buffer_error_code_wr);
        repeat (4) @(posedge rd_clk);
        display_boundary();

        // All four corners and both pixels in each 2x2 replication block.
        check_output_pixel(0, 0, 0);
        check_output_pixel(0, 1, 0);
        check_output_pixel(0, 0, 1);
        check_output_pixel(0, 1, 1);
        check_output_pixel(0, 8, 2);
        check_output_pixel(0, 9, 2);
        check_output_pixel(0, 8, 3);
        check_output_pixel(0, 9, 3);

        // Commit frame 1, but the display must retain frame 0 until its boundary.
        repeat (4) @(posedge wr_clk);
        send_frame(1);
        repeat (4) @(posedge rd_clk);
        check_output_pixel(0, 4, 2);
        display_boundary();
        check_output_pixel(1, 4, 2);
        if (committed_frame_count_wr != 2 || displayed_frame_count != 2 ||
            dropped_frame_count != 0 || buffer_error_wr)
            $fatal(1, "bad frame accounting commit=%0d display=%0d drop=%0d code=%h",
                   committed_frame_count_wr, displayed_frame_count,
                   dropped_frame_count, buffer_error_code_wr);

        $display("PASS: 2x nearest-neighbor corners, repeated pixels/rows, and boundary-only bank switch");
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "timeout");
    end
endmodule
