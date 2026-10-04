`timescale 1ns/1ps

// Signed Sobel arithmetic and strict, unscaled magnitude threshold.
module sobel_threshold #(
    parameter integer X_WIDTH = 10,
    parameter integer Y_WIDTH = 9
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 flush,
    input  logic                 in_valid,
    input  logic [7:0]           p00, p01, p02,
    input  logic [7:0]           p10, p11, p12,
    input  logic [7:0]           p20, p21, p22,
    input  logic [X_WIDTH-1:0]   in_x,
    input  logic [Y_WIDTH-1:0]   in_y,
    input  logic [10:0]          threshold_in,
    output logic                 out_valid,
    output logic                 edge_out,
    output logic signed [10:0]   gx_out,
    output logic signed [10:0]   gy_out,
    output logic [10:0]          magnitude_out,
    output logic [X_WIDTH-1:0]   out_x,
    output logic [Y_WIDTH-1:0]   out_y
);
    logic signed [11:0] gx_comb, gy_comb;
    logic signed [11:0] gx_s1, gy_s1;
    logic valid_s1;
    logic [X_WIDTH-1:0] x_s1;
    logic [Y_WIDTH-1:0] y_s1;
    logic [10:0] threshold_s1;
    logic [11:0] abs_gx_s1, abs_gy_s1;
    logic [12:0] magnitude_s1;

    logic signed [11:0] p00e, p01e, p02e;
    logic signed [11:0] p10e, p12e;
    logic signed [11:0] p20e, p21e, p22e;

    assign p00e = $signed({4'b0, p00});
    assign p01e = $signed({4'b0, p01});
    assign p02e = $signed({4'b0, p02});
    assign p10e = $signed({4'b0, p10});
    assign p12e = $signed({4'b0, p12});
    assign p20e = $signed({4'b0, p20});
    assign p21e = $signed({4'b0, p21});
    assign p22e = $signed({4'b0, p22});

    assign gx_comb = (p02e - p00e) + ((p12e - p10e) <<< 1)
                   + (p22e - p20e);
    assign gy_comb = (p20e - p00e) + ((p21e - p01e) <<< 1)
                   + (p22e - p02e);
    assign abs_gx_s1 = gx_s1[11] ? $unsigned(-gx_s1) : $unsigned(gx_s1);
    assign abs_gy_s1 = gy_s1[11] ? $unsigned(-gy_s1) : $unsigned(gy_s1);
    assign magnitude_s1 = {1'b0, abs_gx_s1} + {1'b0, abs_gy_s1};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            gx_s1 <= 12'sd0;
            gy_s1 <= 12'sd0;
            x_s1 <= '0;
            y_s1 <= '0;
            threshold_s1 <= 11'd0;
            out_valid <= 1'b0;
            edge_out <= 1'b0;
            gx_out <= 11'sd0;
            gy_out <= 11'sd0;
            magnitude_out <= 11'd0;
            out_x <= '0;
            out_y <= '0;
        end else if (flush) begin
            valid_s1 <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            valid_s1 <= in_valid;
            if (in_valid) begin
                gx_s1 <= gx_comb;
                gy_s1 <= gy_comb;
                x_s1 <= in_x;
                y_s1 <= in_y;
                threshold_s1 <= threshold_in;
            end

            out_valid <= valid_s1;
            if (valid_s1) begin
                gx_out <= gx_s1[10:0];
                gy_out <= gy_s1[10:0];
                magnitude_out <= magnitude_s1[10:0];
                edge_out <= (magnitude_s1 > {2'b00, threshold_s1});
                out_x <= x_s1;
                out_y <= y_s1;
            end
        end
    end

    logic _unused_center;
    assign _unused_center = ^p11;
endmodule
