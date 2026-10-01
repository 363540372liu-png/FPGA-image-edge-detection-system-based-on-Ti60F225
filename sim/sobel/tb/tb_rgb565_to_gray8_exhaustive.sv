`timescale 1ns/1ps

module tb_rgb565_to_gray8_exhaustive;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [15:0] rgb565 = 16'd0;
    logic pixel_valid = 1'b0;
    logic [11:0] pixel_x = 12'd0, pixel_y = 12'd0;
    logic start_of_frame = 1'b0, frame_end = 1'b0, frame_good = 1'b0;
    logic [7:0] gray;
    logic [15:0] gray_rgb565;
    logic gray_valid, gray_start_of_frame, gray_end_of_line;
    logic gray_frame_end, gray_frame_good;
    logic [11:0] gray_x, gray_y;

    logic [7:0] expected_mem [0:65535];
    logic exp_valid = 1'b0, exp_sof = 1'b0, exp_eof = 1'b0, exp_good = 1'b0;
    logic [15:0] exp_rgb = 16'd0;
    logic [11:0] exp_x = 12'd0, exp_y = 12'd0;
    integer checked_pixels = 0;

    always #5 clk = ~clk;

    rgb565_to_gray8 dut (.*);

    task automatic apply_cycle(
        input logic valid_i,
        input logic [15:0] rgb_i,
        input logic [11:0] x_i,
        input logic [11:0] y_i,
        input logic sof_i,
        input logic eof_i,
        input logic good_i
    );
        logic [7:0] expected_gray;
        logic [15:0] expected_rgb565;
        begin
            @(negedge clk);
            pixel_valid = valid_i;
            rgb565 = rgb_i;
            pixel_x = x_i;
            pixel_y = y_i;
            start_of_frame = sof_i;
            frame_end = eof_i;
            frame_good = good_i;
            @(posedge clk);
            #1;

            if (gray_valid !== exp_valid ||
                gray_start_of_frame !== exp_sof ||
                gray_frame_end !== exp_eof ||
                gray_frame_good !== exp_good ||
                gray_x !== exp_x || gray_y !== exp_y)
                $fatal(1, "control mismatch valid=%b/%b sof=%b/%b eof=%b/%b good=%b/%b xy=%0d,%0d/%0d,%0d",
                       gray_valid, exp_valid, gray_start_of_frame, exp_sof,
                       gray_frame_end, exp_eof, gray_frame_good, exp_good,
                       gray_x, gray_y, exp_x, exp_y);
            if (gray_end_of_line !== (exp_valid && (exp_x == 12'd639)))
                $fatal(1, "end-of-line mismatch at x=%0d valid=%b", exp_x, exp_valid);

            if (exp_valid) begin
                expected_gray = expected_mem[exp_rgb];
                expected_rgb565 = {expected_gray[7:3], expected_gray[7:2],
                                   expected_gray[7:3]};
                if (gray !== expected_gray)
                    $fatal(1, "gray mismatch rgb565=%04h got=%02h expected=%02h",
                           exp_rgb, gray, expected_gray);
                if (gray_rgb565 !== expected_rgb565)
                    $fatal(1, "preview RGB565 mismatch gray=%02h got=%04h expected=%04h",
                           gray, gray_rgb565, expected_rgb565);
                checked_pixels = checked_pixels + 1;
            end

            exp_valid = valid_i;
            exp_rgb = rgb_i;
            exp_x = x_i;
            exp_y = y_i;
            exp_sof = sof_i;
            exp_eof = eof_i;
            exp_good = good_i;
        end
    endtask

    integer i;
    initial begin
        $readmemh("vectors/rgb565_gray_expected.mem", expected_mem);
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        // Exhaustive, continuous one-pixel-per-clock stream. EOF deliberately
        // coincides with the final pixel to verify aligned boundary handling.
        for (i = 0; i < 65536; i = i + 1)
            apply_cycle(1'b1, i[15:0], i % 640, (i / 640) % 480,
                        (i == 0), (i == 65535), (i == 65535));
        apply_cycle(1'b0, 16'h0000, 12'd0, 12'd0, 1'b0, 1'b0, 1'b0);
        apply_cycle(1'b0, 16'h0000, 12'd0, 12'd0, 1'b0, 1'b0, 1'b0);
        if (checked_pixels != 65536)
            $fatal(1, "checked %0d pixels, expected 65536", checked_pixels);

        // Valid gaps must not duplicate or drop pixels.
        apply_cycle(1'b1, 16'hF800, 12'd638, 12'd9, 1'b0, 1'b0, 1'b0);
        apply_cycle(1'b0, 16'h1234, 12'd12, 12'd34, 1'b0, 1'b0, 1'b0);
        apply_cycle(1'b1, 16'h07E0, 12'd639, 12'd9, 1'b0, 1'b0, 1'b0);
        apply_cycle(1'b0, 16'h0000, 12'd0, 12'd0, 1'b0, 1'b0, 1'b0);
        apply_cycle(1'b0, 16'h0000, 12'd0, 12'd0, 1'b0, 1'b0, 1'b0);
        if (checked_pixels != 65538)
            $fatal(1, "valid-gap count=%0d expected=65538", checked_pixels);

        // Reset discards a pending pipeline item and clears all valid controls.
        @(negedge clk);
        pixel_valid = 1'b1;
        rgb565 = 16'h001F;
        pixel_x = 12'd7;
        pixel_y = 12'd8;
        @(posedge clk); #1;
        exp_valid = 1'b1;
        exp_rgb = 16'h001F;
        exp_x = 12'd7;
        exp_y = 12'd8;
        @(negedge clk); rst_n = 1'b0;
        exp_valid = 1'b0; exp_sof = 1'b0; exp_eof = 1'b0; exp_good = 1'b0;
        #1;
        if (gray_valid || gray_start_of_frame || gray_frame_end || gray_frame_good)
            $fatal(1, "pipeline controls did not clear during reset");
        repeat (2) @(posedge clk);
        @(negedge clk); rst_n = 1'b1; pixel_valid = 1'b0;
        apply_cycle(1'b1, 16'hFFFF, 12'd0, 12'd0, 1'b1, 1'b0, 1'b0);
        apply_cycle(1'b0, 16'h0000, 12'd0, 12'd0, 1'b0, 1'b1, 1'b1);
        apply_cycle(1'b0, 16'h0000, 12'd0, 12'd0, 1'b0, 1'b0, 1'b0);
        apply_cycle(1'b0, 16'h0000, 12'd0, 12'd0, 1'b0, 1'b0, 1'b0);

        $display("PASS: all 65536 RGB565 values, one-cycle controls, gaps, reset, line/frame boundaries, and RGB565 preview quantization");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "timeout");
    end
endmodule
