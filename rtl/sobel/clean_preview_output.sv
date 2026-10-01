`timescale 1ns/1ps

// Clean preview pixel selection. The framebuffer has already delayed
// pixel_valid by one RAM-read cycle; de is delayed by the same cycle in top.
module clean_preview_output (
    input  logic        de,
    input  logic [15:0] pixel565,
    input  logic        pixel_valid,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue
);
    always_comb begin
        red   = 8'h00;
        green = 8'h00;
        blue  = 8'h00;
        if (de && pixel_valid) begin
            red   = {pixel565[15:11], pixel565[15:13]};
            green = {pixel565[10:5],  pixel565[10:9]};
            blue  = {pixel565[4:0],   pixel565[4:2]};
        end
    end
endmodule
