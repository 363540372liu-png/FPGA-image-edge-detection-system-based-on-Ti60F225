`timescale 1ns/1ps

module tb_clean_preview_output;
    logic        de;
    logic [15:0] pixel565;
    logic        pixel_valid;
    logic [7:0]  red;
    logic [7:0]  green;
    logic [7:0]  blue;

    clean_preview_output dut (.*);

    task automatic expect_rgb(
        input logic [15:0] pixel,
        input logic        valid,
        input logic        active,
        input logic [23:0] expected
    );
        begin
            pixel565   = pixel;
            pixel_valid = valid;
            de          = active;
            #1;
            if ({red, green, blue} !== expected)
                $fatal(1, "pixel=%04h valid=%0b de=%0b got=%06h expected=%06h",
                       pixel, valid, active, {red, green, blue}, expected);
        end
    endtask

    initial begin
        // No accepted frame / no RAM pixel: clean preview must stay black.
        expect_rgb(16'hffff, 1'b0, 1'b1, 24'h000000);
        // Blanking must stay black even if stale RAM data is present.
        expect_rgb(16'hffff, 1'b1, 1'b0, 24'h000000);
        expect_rgb(16'hf800, 1'b1, 1'b1, 24'hff0000);
        expect_rgb(16'h07e0, 1'b1, 1'b1, 24'h00ff00);
        expect_rgb(16'h001f, 1'b1, 1'b1, 24'h0000ff);
        expect_rgb(16'hffff, 1'b1, 1'b1, 24'hffffff);
        $display("PASS: clean preview is black until valid and converts RGB565 exactly");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "timeout");
    end
endmodule
