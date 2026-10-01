`timescale 1ns/1ps
module tb_video_timing_640x480;
    localparam int H_TOTAL = 800;
    localparam int V_TOTAL = 525;
    localparam int FRAME_CYCLES = H_TOTAL * V_TOTAL;

    logic clk_pixel = 1'b0;
    logic rst_n = 1'b0;
    logic [11:0] x, y;
    logic de, hsync, vsync, frame_tick;

    always #1 clk_pixel = ~clk_pixel;

    video_timing_gen #(
        .H_ACTIVE(640), .H_FP(16), .H_SYNC(96), .H_BP(48),
        .V_ACTIVE(480), .V_FP(10), .V_SYNC(2), .V_BP(33),
        .HS_ACTIVE_LEVEL(1'b0), .VS_ACTIVE_LEVEL(1'b0)
    ) dut (.*);

    task automatic check_frame;
        integer cycles, active_pixels, hs_low_cycles, vs_low_cycles;
        integer line_ends, frame_ticks;
        begin
            while (!((x == 0) && (y == 0))) @(negedge clk_pixel);
            active_pixels = 0;
            hs_low_cycles = 0;
            vs_low_cycles = 0;
            line_ends = 0;
            frame_ticks = 0;
            for (cycles = 0; cycles < FRAME_CYCLES; cycles = cycles + 1) begin
                if (de !== ((x < 640) && (y < 480)))
                    $fatal(1, "DE mismatch at x=%0d y=%0d", x, y);
                if (hsync !== ~((x >= 656) && (x < 752)))
                    $fatal(1, "HSYNC mismatch at x=%0d y=%0d", x, y);
                if (vsync !== ~((y >= 490) && (y < 492)))
                    $fatal(1, "VSYNC mismatch at x=%0d y=%0d", x, y);
                active_pixels = active_pixels + de;
                hs_low_cycles = hs_low_cycles + !hsync;
                vs_low_cycles = vs_low_cycles + !vsync;
                line_ends = line_ends + (x == 799);
                frame_ticks = frame_ticks + frame_tick;
                if ((cycles == FRAME_CYCLES - 1) && !frame_tick)
                    $fatal(1, "frame_tick absent on final pixel");
                @(negedge clk_pixel);
            end
            if (active_pixels != 307200)
                $fatal(1, "active pixels=%0d expected=307200", active_pixels);
            if (hs_low_cycles != 50400)
                $fatal(1, "HS low cycles=%0d expected=50400", hs_low_cycles);
            if (vs_low_cycles != 1600)
                $fatal(1, "VS low cycles=%0d expected=1600", vs_low_cycles);
            if ((line_ends != 525) || (frame_ticks != 1))
                $fatal(1, "lines=%0d frame_ticks=%0d", line_ends, frame_ticks);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk_pixel);
        rst_n = 1'b1;
        @(negedge clk_pixel);
        check_frame();

        rst_n = 1'b0;
        repeat (3) @(posedge clk_pixel);
        @(negedge clk_pixel);
        if ((x != 0) || (y != 0) || de || (hsync !== 1'b1) ||
            (vsync !== 1'b1) || frame_tick)
            $fatal(1, "timing outputs did not return to reset state");
        rst_n = 1'b1;
        @(negedge clk_pixel);
        check_frame();

        $display("PASS: 640x480, 800x525, negative sync timing and reset recovery");
        $finish;
    end

    initial begin
        #4_000_000;
        $fatal(1, "timeout");
    end
endmodule
