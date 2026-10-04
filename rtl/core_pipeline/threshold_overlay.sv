`timescale 1ns/1ps
// Small optional readout.  It is in the pixel domain and uses the threshold
// latched with the displayed framebuffer, never the live key request.
module threshold_overlay (
    input  logic        de,
    input  logic [11:0] x,
    input  logic [11:0] y,
    input  logic [10:0] threshold,
    input  logic        threshold_valid,
    input  logic [7:0]  base_red,
    input  logic [7:0]  base_green,
    input  logic [7:0]  base_blue,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue
);
    logic [3:0] d3, d2, d1, d0;
    logic [10:0] rem;
    logic glyph_on;
    logic [3:0] digit;
    logic [2:0] gx, gy;

    always_comb begin
        rem = threshold;
        if (rem >= 11'd1000) begin d3 = 4'd1; rem = rem - 11'd1000; end
        else d3 = 4'd0;
        if (rem >= 11'd900) begin d2 = 4'd9; rem = rem - 11'd900; end
        else if (rem >= 11'd800) begin d2 = 4'd8; rem = rem - 11'd800; end
        else if (rem >= 11'd700) begin d2 = 4'd7; rem = rem - 11'd700; end
        else if (rem >= 11'd600) begin d2 = 4'd6; rem = rem - 11'd600; end
        else if (rem >= 11'd500) begin d2 = 4'd5; rem = rem - 11'd500; end
        else if (rem >= 11'd400) begin d2 = 4'd4; rem = rem - 11'd400; end
        else if (rem >= 11'd300) begin d2 = 4'd3; rem = rem - 11'd300; end
        else if (rem >= 11'd200) begin d2 = 4'd2; rem = rem - 11'd200; end
        else if (rem >= 11'd100) begin d2 = 4'd1; rem = rem - 11'd100; end
        else d2 = 4'd0;
        if (rem >= 11'd90) begin d1 = 4'd9; rem = rem - 11'd90; end
        else if (rem >= 11'd80) begin d1 = 4'd8; rem = rem - 11'd80; end
        else if (rem >= 11'd70) begin d1 = 4'd7; rem = rem - 11'd70; end
        else if (rem >= 11'd60) begin d1 = 4'd6; rem = rem - 11'd60; end
        else if (rem >= 11'd50) begin d1 = 4'd5; rem = rem - 11'd50; end
        else if (rem >= 11'd40) begin d1 = 4'd4; rem = rem - 11'd40; end
        else if (rem >= 11'd30) begin d1 = 4'd3; rem = rem - 11'd30; end
        else if (rem >= 11'd20) begin d1 = 4'd2; rem = rem - 11'd20; end
        else if (rem >= 11'd10) begin d1 = 4'd1; rem = rem - 11'd10; end
        else d1 = 4'd0;
        d0 = rem[3:0];

        red = base_red; green = base_green; blue = base_blue;
        glyph_on = 1'b0; digit = 4'd0; gx = 3'd0; gy = 3'd0;
        if (de && threshold_valid && (y >= 12'd8) && (y < 12'd16) &&
            (x >= 12'd8) && (x < 12'd40)) begin
            gy = y[2:0];
            // Each glyph cell is eight pixels wide, so the low three x
            // bits are the local glyph column without a truncating subtract.
            gx = x[2:0];
            if (x < 12'd16) digit = d3;
            else if (x < 12'd24) digit = d2;
            else if (x < 12'd32) digit = d1;
            else digit = d0;
            case (digit)
                4'd0: glyph_on = (gx==0 || gx==4 || gy==0 || gy==7);
                4'd1: glyph_on = (gx==2 || (gy==7));
                4'd2: glyph_on = (gy==0 || gy==3 || gy==7 || (gy<3 && gx==4) || (gy>3 && gx==0));
                4'd3: glyph_on = (gy==0 || gy==3 || gy==7 || gx==4);
                4'd4: glyph_on = (gy==3 || gx==4 || (gy<4 && gx==0));
                4'd5: glyph_on = (gy==0 || gy==3 || gy==7 || (gy<3 && gx==0) || (gy>3 && gx==4));
                4'd6: glyph_on = (gy==0 || gy==3 || gy==7 || gx==0 || (gy>3 && gx==4));
                4'd7: glyph_on = (gy==0 || gx==4);
                4'd8: glyph_on = (gy==0 || gy==3 || gy==7 || gx==0 || gx==4);
                default: glyph_on = (gy==0 || gy==3 || gy==7 || gx==4 || (gy<4 && gx==0));
            endcase
            if (glyph_on) begin red = 8'hff; green = 8'hff; blue = 8'h00; end
        end
    end
endmodule
