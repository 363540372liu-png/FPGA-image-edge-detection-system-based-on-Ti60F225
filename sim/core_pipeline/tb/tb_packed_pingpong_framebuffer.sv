`timescale 1ns/1ps
module tb_packed_pingpong_framebuffer;
    localparam int SW = 40;
    localparam int SH = 15;
    localparam int IW = 10;
    localparam int IH = 5;
    localparam int DW = 18;
    localparam int DH = 13;
    localparam int XO = 4;
    localparam int YO = 4;

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

    always #3.5 wr_clk = ~wr_clk;
    always #5.5 rd_clk = ~rd_clk;

    packed_pingpong_framebuffer #(
        .SOURCE_WIDTH(SW), .SOURCE_HEIGHT(SH),
        .SAMPLE_X_STEP(4), .SAMPLE_Y_STEP(3),
        .IMAGE_WIDTH(IW), .IMAGE_HEIGHT(IH),
        .DISPLAY_WIDTH(DW), .DISPLAY_HEIGHT(DH)
    ) dut (.*);

    function automatic [15:0] pattern(input int frame, input int x, input int y);
        logic [4:0] r, b;
        logic [5:0] g;
        integer sum;
        begin
            r = frame ? (5'h1f - x[4:0]) : x[4:0];
            g = y[5:0];
            sum = x + y + frame;
            b = sum[4:0];
            pattern = {r, g, b};
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

    task automatic check_pixel(input int frame, input int ix, input int iy);
        logic [15:0] expected;
        begin
            expected = pattern(frame, ix * 4, iy * 3);
            @(negedge rd_clk);
            rd_x <= XO + ix;
            rd_y <= YO + iy;
            rd_de <= 1'b1;
            @(posedge rd_clk); #1;
            if (!rd_pixel_valid)
                $fatal(1, "pixel (%0d,%0d) not valid", ix, iy);
            if (rd_pixel !== expected)
                $fatal(1, "frame%0d pixel(%0d,%0d)=%04h expected=%04h",
                       frame, ix, iy, rd_pixel, expected);
        end
    endtask

    initial begin
        wr_pixel = 0; wr_pixel_valid = 0; wr_start_of_frame = 0;
        wr_frame_end = 0; wr_x = 0; wr_y = 0;
        rd_x = 0; rd_y = 0; rd_de = 0; rd_frame_tick = 0;
        repeat (4) @(posedge wr_clk);
        wr_rst_n = 1;
        rd_rst_n = 1;

        if (display_has_frame !== 1'b0)
            $fatal(1, "background must remain selected before first frame");

        send_frame(0);
        if (!frame_committed_wr)
            $fatal(1, "first full frame did not assert frame_committed_wr");
        if ((last_sampled_pixel_count_wr != IW*IH) ||
            (last_written_word_count_wr != (IW*IH)/5) ||
            (buffer_error_code_wr != 0))
            $fatal(1, "bad write snapshot samples=%0d words=%0d code=%h",
                   last_sampled_pixel_count_wr, last_written_word_count_wr,
                   buffer_error_code_wr);
        repeat (4) @(posedge rd_clk);
        if (display_has_frame)
            $fatal(1, "frame changed before display boundary");
        display_boundary();
        if (!display_has_frame || displayed_frame_count != 1)
            $fatal(1, "first complete frame was not accepted");

        check_pixel(0, 0, 0);
        check_pixel(0, 4, 2);
        check_pixel(0, 9, 4);

        // Border is active video but must not request frame-memory data.
        @(negedge rd_clk); rd_x <= 0; rd_y <= 0; rd_de <= 1'b1;
        @(posedge rd_clk); #1;
        if (rd_pixel_valid)
            $fatal(1, "black border incorrectly marked as image data");

        repeat (4) @(posedge wr_clk);
        send_frame(1);
        repeat (4) @(posedge rd_clk);
        // New frame is complete, but old frame remains active until boundary.
        check_pixel(0, 4, 2);
        display_boundary();
        if (displayed_frame_count != 2)
            $fatal(1, "second frame was not switched at boundary");
        check_pixel(1, 0, 0);
        check_pixel(1, 4, 2);
        check_pixel(1, 9, 4);

        if (buffer_error_wr)
            $fatal(1, "unexpected buffer format error");
        $display("PASS: 1280x720-style 4x3 subsample, centered window, async full-frame switch, no tear");
        $finish;
    end

    initial begin
        #5_000_000;
        $fatal(1, "timeout");
    end
endmodule
