`timescale 1ns/1ps

// Downsample a complete 8-bit grayscale frame by averaging each non-overlapping
// 2x2 source block.  Adding two before the shift implements round-to-nearest
// for the unsigned four-pixel sum.
module gray_preview_2x2_mean #(
    parameter integer SOURCE_WIDTH = 640,
    parameter integer SOURCE_HEIGHT = 480,
    parameter integer X_WIDTH = $clog2(SOURCE_WIDTH),
    parameter integer Y_WIDTH = $clog2(SOURCE_HEIGHT)
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic [7:0]         gray_in,
    input  logic [X_WIDTH-1:0] in_x,
    input  logic [Y_WIDTH-1:0] in_y,
    input  logic               in_sof,
    input  logic               in_frame_end,
    input  logic               in_frame_good,
    output logic               out_valid,
    output logic [7:0]         out_gray,
    output logic [11:0]        out_x,
    output logic [11:0]        out_y,
    output logic               out_sof,
    output logic               out_frame_end,
    output logic               out_frame_good,
    output logic               coordinate_error
);
    localparam integer PREVIEW_WIDTH = SOURCE_WIDTH / 2;

    logic [7:0] left_gray;
    logic [9:0] bottom_sum_d;
    logic [11:0] x_d, y_d;
    logic sof_d, end_d, good_d, bottom_pending;
    logic [X_WIDTH-1:0] expected_x;
    logic [Y_WIDTH-1:0] expected_y;
    logic frame_active;
    logic [19:0] top_sum_rdata;
    wire [9:0] horizontal_sum = {2'b0, left_gray} + {2'b0, gray_in};
    wire pair_complete = in_valid && in_x[0];
    wire top_write = pair_complete && !in_y[0];
    wire bottom_read = pair_complete && in_y[0];
    wire [8:0] pair_addr = in_x[X_WIDTH-1:1];
    wire [10:0] rounded_sum = {1'b0, top_sum_rdata[9:0]} +
                              {1'b0, bottom_sum_d} + 11'd2;

    initial begin
        if ((SOURCE_WIDTH % 2) || (SOURCE_HEIGHT % 2))
            $error("gray_preview_2x2_mean requires even source dimensions");
        if (PREVIEW_WIDTH > 512)
            $error("gray_preview_2x2_mean top-row store exceeds one RAM10");
    end

    EFX_RAM10 #(
        .READ_WIDTH(20), .WRITE_WIDTH(20), .OUTPUT_REG(1'b0),
        .WRITE_MODE("READ_FIRST"), .RESET_RAM("NONE"),
        .RESET_OUTREG("NONE")
    ) u_top_pair_sum (
        .WCLK(clk), .WCLKE(1'b1), .WADDREN(1'b1),
        .WE({2{top_write}}), .WDATA({10'd0, horizontal_sum}),
        .WADDR(pair_addr),
        .RCLK(clk), .RE(bottom_read), .RST(1'b0), .RADDREN(1'b1),
        .RDATA(top_sum_rdata), .RADDR(pair_addr)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            left_gray <= 8'd0;
            bottom_sum_d <= 10'd0;
            x_d <= 12'd0;
            y_d <= 12'd0;
            sof_d <= 1'b0;
            end_d <= 1'b0;
            good_d <= 1'b0;
            bottom_pending <= 1'b0;
            out_valid <= 1'b0;
            out_gray <= 8'd0;
            out_x <= 12'd0;
            out_y <= 12'd0;
            out_sof <= 1'b0;
            out_frame_end <= 1'b0;
            out_frame_good <= 1'b0;
            expected_x <= '0;
            expected_y <= '0;
            frame_active <= 1'b0;
            coordinate_error <= 1'b0;
        end else begin
            out_valid <= bottom_pending;
            out_sof <= bottom_pending && sof_d;
            out_frame_end <= bottom_pending && end_d;
            out_frame_good <= bottom_pending && end_d && good_d;
            if (bottom_pending) begin
                out_gray <= rounded_sum[9:2];
                out_x <= x_d;
                out_y <= y_d;
            end
            bottom_pending <= 1'b0;

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

                if (!in_x[0])
                    left_gray <= gray_in;

                if (bottom_read) begin
                    bottom_sum_d <= horizontal_sum;
                    x_d <= in_x >> 1;
                    y_d <= in_y >> 1;
                    sof_d <= (in_x == 1) && (in_y == 1);
                    end_d <= in_frame_end;
                    good_d <= in_frame_good;
                    bottom_pending <= 1'b1;
                end

                if (in_frame_end)
                    frame_active <= 1'b0;
            end
        end
    end
endmodule
