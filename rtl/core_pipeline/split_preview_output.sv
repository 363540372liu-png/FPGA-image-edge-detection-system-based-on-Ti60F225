`timescale 1ns/1ps

module split_preview_output (
    input  logic       de,
    input  logic       pixel_valid,
    input  logic       gray_view,
    input  logic       edge_view,
    input  logic [7:0] gray,
    input  logic       edge_bit,
    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue
);
    always_comb begin
        red = 8'd0;
        green = 8'd0;
        blue = 8'd0;
        if (de && pixel_valid) begin
            if (gray_view) begin
                red = gray;
                green = gray;
                blue = gray;
            end else if (edge_view) begin
                red = {8{edge_bit}};
                green = {8{edge_bit}};
                blue = {8{edge_bit}};
            end
        end
    end
endmodule
