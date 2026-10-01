`timescale 1ns/1ps

// One-pixel-per-clock RGB565 to 8-bit grayscale stream converter.
//
// RGB expansion:
//   R8 = {R5, R5[4:2]}
//   G8 = {G6, G6[5:4]}
//   B8 = {B5, B5[4:2]}
// Grayscale:
//   Y = (77*R8 + 150*G8 + 29*B8 + 128) >> 8
//
// The multipliers are written as shifts and adds. The output corresponding to
// an input sampled at clock edge N is registered at edge N+1. All stream
// controls, including frame_end/frame_good, use the same one-cycle latency.
module rgb565_to_gray8 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] rgb565,
    input  logic        pixel_valid,
    input  logic [11:0] pixel_x,
    input  logic [11:0] pixel_y,
    input  logic        start_of_frame,
    input  logic        frame_end,
    input  logic        frame_good,

    output logic [7:0]  gray,
    output logic [15:0] gray_rgb565,
    output logic        gray_valid,
    output logic [11:0] gray_x,
    output logic [11:0] gray_y,
    output logic        gray_start_of_frame,
    output logic        gray_end_of_line,
    output logic        gray_frame_end,
    output logic        gray_frame_good
);
    logic [7:0] r8, g8, b8;
    logic [15:0] r_product_comb, g_product_comb, b_product_comb;
    logic [15:0] r_product_s1, g_product_s1, b_product_s1;
    logic [16:0] weighted_sum_s1;
    logic valid_s1, sof_s1, eof_s1, good_s1;
    logic [11:0] x_s1, y_s1;

    assign r8 = {rgb565[15:11], rgb565[15:13]};
    assign g8 = {rgb565[10:5],  rgb565[10:9]};
    assign b8 = {rgb565[4:0],   rgb565[4:2]};

    // 77 = 64 + 8 + 4 + 1
    assign r_product_comb = ({8'd0, r8} << 6) +
                            ({8'd0, r8} << 3) +
                            ({8'd0, r8} << 2) +
                             {8'd0, r8};
    // 150 = 128 + 16 + 4 + 2
    assign g_product_comb = ({8'd0, g8} << 7) +
                            ({8'd0, g8} << 4) +
                            ({8'd0, g8} << 2) +
                            ({8'd0, g8} << 1);
    // 29 = 16 + 8 + 4 + 1
    assign b_product_comb = ({8'd0, b8} << 4) +
                            ({8'd0, b8} << 3) +
                            ({8'd0, b8} << 2) +
                             {8'd0, b8};

    // The maximum is 77*255 + 150*255 + 29*255 + 128 = 65408.
    // A 17-bit accumulator makes every extension explicit and prevents
    // expression-width truncation before the final right shift.
    assign weighted_sum_s1 = {1'b0, r_product_s1} +
                             {1'b0, g_product_s1} +
                             {1'b0, b_product_s1} + 17'd128;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_product_s1 <= 16'd0;
            g_product_s1 <= 16'd0;
            b_product_s1 <= 16'd0;
            valid_s1 <= 1'b0;
            sof_s1 <= 1'b0;
            eof_s1 <= 1'b0;
            good_s1 <= 1'b0;
            x_s1 <= 12'd0;
            y_s1 <= 12'd0;
            gray <= 8'd0;
            gray_valid <= 1'b0;
            gray_x <= 12'd0;
            gray_y <= 12'd0;
            gray_start_of_frame <= 1'b0;
            gray_frame_end <= 1'b0;
            gray_frame_good <= 1'b0;
        end else begin
            r_product_s1 <= r_product_comb;
            g_product_s1 <= g_product_comb;
            b_product_s1 <= b_product_comb;
            valid_s1 <= pixel_valid;
            sof_s1 <= start_of_frame;
            eof_s1 <= frame_end;
            good_s1 <= frame_good;
            x_s1 <= pixel_x;
            y_s1 <= pixel_y;

            gray <= weighted_sum_s1[15:8];
            gray_valid <= valid_s1;
            gray_x <= x_s1;
            gray_y <= y_s1;
            gray_start_of_frame <= sof_s1;
            gray_frame_end <= eof_s1;
            gray_frame_good <= good_s1;
        end
    end

    // The preview buffer remains RGB565. This quantization does not reduce
    // the precision of the independent 8-bit gray stream used by algorithms.
    assign gray_rgb565 = {gray[7:3], gray[7:2], gray[7:3]};
    assign gray_end_of_line = gray_valid && (gray_x == 12'd639);
endmodule
