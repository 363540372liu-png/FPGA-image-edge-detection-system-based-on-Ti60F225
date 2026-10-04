`timescale 1ns/1ps

// Reduce a complete binary edge frame by OR-ing each non-overlapping 2x2
// source block. This preserves thin lines better than point sampling, at the
// cost of making the preview edge up to one preview pixel thicker.
module edge_preview_2x2_or #(
    parameter integer SOURCE_WIDTH = 640,
    parameter integer SOURCE_HEIGHT = 480,
    parameter integer X_WIDTH = (SOURCE_WIDTH <= 2) ? 1 : $clog2(SOURCE_WIDTH),
    parameter integer Y_WIDTH = (SOURCE_HEIGHT <= 2) ? 1 : $clog2(SOURCE_HEIGHT)
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    input  logic                 edge_in,
    input  logic [X_WIDTH-1:0]   in_x,
    input  logic [Y_WIDTH-1:0]   in_y,
    input  logic                 in_sof,
    input  logic                 in_frame_end,
    input  logic                 in_frame_good,
    output logic                 out_valid,
    output logic [15:0]          out_pixel565,
    output logic [11:0]          out_x,
    output logic [11:0]          out_y,
    output logic                 out_sof,
    output logic                 out_frame_end,
    output logic                 out_frame_good,
    output logic                 coordinate_error
);
    localparam integer PREVIEW_WIDTH = SOURCE_WIDTH / 2;
    logic row_pair [0:PREVIEW_WIDTH-1];
    logic horizontal_left;
    logic [X_WIDTH-1:0] expected_x;
    logic [Y_WIDTH-1:0] expected_y;
    logic frame_active;
    wire horizontal_or = horizontal_left | edge_in;
    wire [X_WIDTH-2:0] preview_x = in_x[X_WIDTH-1:1];

    initial begin
        if ((SOURCE_WIDTH % 2) || (SOURCE_HEIGHT % 2))
            $error("edge_preview_2x2_or requires even source dimensions");
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            horizontal_left <= 1'b0;
            expected_x <= '0;
            expected_y <= '0;
            frame_active <= 1'b0;
            out_valid <= 1'b0;
            out_pixel565 <= 16'h0000;
            out_x <= 12'd0;
            out_y <= 12'd0;
            out_sof <= 1'b0;
            out_frame_end <= 1'b0;
            out_frame_good <= 1'b0;
            coordinate_error <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            out_sof <= 1'b0;
            out_frame_end <= 1'b0;
            out_frame_good <= 1'b0;

            if (in_valid) begin
                if (in_sof) begin
                    frame_active <= 1'b1;
                    expected_x <= 1;
                    expected_y <= 0;
                    if ((in_x != 0) || (in_y != 0))
                        coordinate_error <= 1'b1;
                end else if (frame_active) begin
                    if ((in_x != expected_x) || (in_y != expected_y))
                        coordinate_error <= 1'b1;
                    if (expected_x == SOURCE_WIDTH-1) begin
                        expected_x <= '0;
                        expected_y <= expected_y + 1'b1;
                    end else begin
                        expected_x <= expected_x + 1'b1;
                    end
                end

                if (!in_x[0]) begin
                    horizontal_left <= edge_in;
                end else if (!in_y[0]) begin
                    row_pair[preview_x] <= horizontal_or;
                end else begin
                    out_valid <= 1'b1;
                    out_pixel565 <= (row_pair[preview_x] | horizontal_or) ?
                                    16'hFFFF : 16'h0000;
                    out_x <= {{(12-(X_WIDTH-1)){1'b0}}, preview_x};
                    out_y <= in_y >> 1;
                    out_sof <= (in_x == 1) && (in_y == 1);
                    out_frame_end <= in_frame_end;
                    out_frame_good <= in_frame_end && in_frame_good;
                end

                if (in_frame_end)
                    frame_active <= 1'b0;
            end
        end
    end
endmodule
