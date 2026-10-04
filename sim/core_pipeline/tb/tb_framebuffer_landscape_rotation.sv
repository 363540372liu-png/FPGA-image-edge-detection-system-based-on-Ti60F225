`timescale 1ns/1ps

module tb_framebuffer_landscape_rotation;
    // Exact 1:16 model of all three coordinate spaces, preserving the real
    // 2/3 and 3/8 inverse-scale ratios:
    // buffer 20x15, HDMI 40x30, native portrait panel 30x40.
    localparam int BW = 20;
    localparam int BH = 15;
    localparam int DW = 40;
    localparam int DH = 30;
    localparam int PW = 30;
    localparam int PH = 40;
    localparam int SW = BW * 2;
    localparam int SH = BH * 2;

    logic wr_clk = 0, rd_clk = 0;
    logic wr_rst_n = 0, rd_rst_n = 0;
    logic [15:0] wr_pixel = 0;
    logic wr_pixel_valid = 0, wr_start_of_frame = 0, wr_frame_end = 0;
    logic wr_frame_good = 1;
    logic [10:0] wr_frame_threshold = 11'd128;
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
    logic [10:0] displayed_frame_threshold;

    always #3.5 wr_clk = ~wr_clk;
    always #5.5 rd_clk = ~rd_clk;

    packed_pingpong_framebuffer #(
        .SOURCE_WIDTH(SW), .SOURCE_HEIGHT(SH),
        .SAMPLE_X_STEP(2), .SAMPLE_Y_STEP(2),
        .IMAGE_WIDTH(BW), .IMAGE_HEIGHT(BH),
        .DISPLAY_WIDTH(DW), .DISPLAY_HEIGHT(DH),
        .DISPLAY_SCALE(2),
        .ROTATE_CCW_FOR_CW_PANEL(1'b1)
    ) dut (.*);

    function automatic [15:0] asymmetric_pattern(
        input int frame, input int x, input int y
    );
        logic [15:0] base;
        integer sum;
        begin
            sum = x + y;
            // Unique corners, coordinate grid, and an upward magenta arrow.
            if (x == 0 && y == 0)             base = 16'hf800; // red TL
            else if (x == BW-1 && y == 0)     base = 16'h07e0; // green TR
            else if (x == 0 && y == BH-1)     base = 16'h001f; // blue BL
            else if (x == BW-1 && y == BH-1)  base = 16'hffff; // white BR
            else if ((y == 2 && x >= 7 && x <= 13) ||
                     (x == 10 && y >= 2 && y <= 12))
                                                    base = 16'hf81f;
            else if ((x % 5) == 0 || (y % 3) == 0) base = 16'h7bef;
            else base = {x[4:0], y[5:0], sum[4:0]};
            asymmetric_pattern = frame ? (base ^ 16'h0841) : base;
        end
    endfunction

    task automatic send_frame(input int frame);
        int x, y;
        begin
            for (y = 0; y < SH; y++) begin
                for (x = 0; x < SW; x++) begin
                    @(negedge wr_clk);
                    wr_pixel <= asymmetric_pattern(frame, x >> 1, y >> 1);
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
            @(negedge rd_clk); rd_frame_tick <= 1'b1;
            @(negedge rd_clk); rd_frame_tick <= 1'b0;
            repeat (3) @(posedge rd_clk);
        end
    endtask

    task automatic check_hdmi_pixel(input int frame, input int hx, input int hy);
        int bx, by, expected_addr, expected_lane;
        logic [15:0] expected_pixel;
        begin
            // CCW pre-rotation plus inverse compensation for 20x12 -> 12x20.
            bx = BW - 1 - ((hy * 2) / 3);
            by = (hx * 3) / 8;
            expected_addr = by * (BW/5) + bx/5;
            expected_lane = bx % 5;
            expected_pixel = asymmetric_pattern(frame, bx, by);

            @(negedge rd_clk);
            rd_x <= hx;
            rd_y <= hy;
            rd_de <= 1'b1;
            #1;
            if (dut.image_x !== bx || dut.image_y !== by)
                $fatal(1, "map H(%0d,%0d)->B(%0d,%0d), expected B(%0d,%0d)",
                       hx, hy, dut.image_x, dut.image_y, bx, by);
            if (dut.rd_addr !== expected_addr || dut.rd_select !== expected_lane)
                $fatal(1, "address/lane H(%0d,%0d): addr=%0d lane=%0d expected=%0d/%0d",
                       hx, hy, dut.rd_addr, dut.rd_select,
                       expected_addr, expected_lane);
            @(posedge rd_clk); #1;
            if (!rd_pixel_valid || rd_pixel !== expected_pixel)
                $fatal(1, "pixel H(%0d,%0d)=%04h valid=%0b expected=%04h",
                       hx, hy, rd_pixel, rd_pixel_valid, expected_pixel);
        end
    endtask

    task automatic check_assumed_panel_model;
        int lx, ly, native_u, native_v, hx, hy;
        int seen_bx, seen_by, target_bx, target_by;
        int dx, dy;
        begin
            // Model: HDMI 20x12 is center-sampled onto native portrait 12x20;
            // then the physical panel is rotated clockwise. The final view is
            // landscape 20x12. Quantization may move a scaler boundary by one
            // source sample, but orientation and two-axis scale must agree.
            for (ly = 0; ly < PW; ly++) begin
                for (lx = 0; lx < PH; lx++) begin
                    native_u = ly;
                    native_v = PH - 1 - lx;
                    hx = ((2*native_u + 1) * DW) / (2*PW);
                    hy = ((2*native_v + 1) * DH) / (2*PH);
                    if (hx >= DW) hx = DW-1;
                    if (hy >= DH) hy = DH-1;

                    seen_bx = BW - 1 - ((hy * 2) / 3);
                    seen_by = (hx * 3) / 8;
                    target_bx = (lx * BW) / PH;
                    target_by = (ly * BH) / PW;
                    dx = (seen_bx > target_bx) ?
                         (seen_bx-target_bx) : (target_bx-seen_bx);
                    dy = (seen_by > target_by) ?
                         (seen_by-target_by) : (target_by-seen_by);
                    if (dx > 1 || dy > 1)
                        $fatal(1, "panel model L(%0d,%0d) sees B(%0d,%0d), target B(%0d,%0d)",
                               lx, ly, seen_bx, seen_by, target_bx, target_by);
                    if ((lx == 0 || lx == PH-1) &&
                        (ly == 0 || ly == PW-1) &&
                        (dx != 0 || dy != 0))
                        $fatal(1, "final landscape corner mismatch at L(%0d,%0d)",
                               lx, ly);
                end
            end

        end
    endtask

    integer x, y;
    initial begin
        repeat (4) @(posedge wr_clk);
        wr_rst_n = 1;
        rd_rst_n = 1;

        @(negedge rd_clk); rd_de <= 1'b1;
        @(posedge rd_clk); #1;
        if (rd_pixel_valid || display_has_frame)
            $fatal(1, "image became visible before first complete frame");

        send_frame(0);
        if (!frame_committed_wr || buffer_error_wr ||
            last_sampled_pixel_count_wr != BW*BH ||
            last_written_word_count_wr != (BW*BH)/5)
            $fatal(1, "bad commit samples=%0d words=%0d code=%h",
                   last_sampled_pixel_count_wr, last_written_word_count_wr,
                   buffer_error_code_wr);
        repeat (4) @(posedge rd_clk);
        display_boundary();

        // Exhaustively check rotated, non-contiguous RAM reads and every lane.
        for (y = 0; y < DH; y++)
            for (x = 0; x < DW; x++)
                check_hdmi_pixel(0, x, y);

        // HDMI corners are deliberately CCW; physical CW rotation restores them.
        check_hdmi_pixel(0, 0,    0);
        check_hdmi_pixel(0, DW-1, 0);
        check_hdmi_pixel(0, 0,    DH-1);
        check_hdmi_pixel(0, DW-1, DH-1);
        check_assumed_panel_model();

        // Preserve ping-pong protection with non-sequential read addressing.
        repeat (4) @(posedge wr_clk);
        send_frame(1);
        repeat (4) @(posedge rd_clk);
        check_hdmi_pixel(0, 7, 5);
        display_boundary();
        check_hdmi_pixel(1, 7, 5);
        if (committed_frame_count_wr != 2 || displayed_frame_count != 2 ||
            dropped_frame_count != 0 || buffer_error_wr)
            $fatal(1, "bad accounting commit=%0d display=%0d drop=%0d code=%h",
                   committed_frame_count_wr, displayed_frame_count,
                   dropped_frame_count, buffer_error_code_wr);

        $display("PASS: asymmetric corners/arrow/grid, CCW HDMI map, assumed panel stretch + physical CW view, address/lane bounds, and tear-free bank switch");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "timeout");
    end
endmodule
