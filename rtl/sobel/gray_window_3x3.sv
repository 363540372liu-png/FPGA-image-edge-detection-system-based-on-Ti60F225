`timescale 1ns/1ps

// Full-resolution grayscale stream to a valid-only 3x3 window stream.
// Two native-RAM line delays provide y-1 and y-2. Three horizontal shift
// chains form the columns. The window center is (input_x-1,input_y-1).
module gray_window_3x3 #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter integer X_WIDTH = (WIDTH <= 2) ? 1 : $clog2(WIDTH),
    parameter integer Y_WIDTH = (HEIGHT <= 2) ? 1 : $clog2(HEIGHT)
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [7:0]           gray_in,
    input  logic                 in_valid,
    input  logic [X_WIDTH-1:0]   in_x,
    input  logic [Y_WIDTH-1:0]   in_y,
    input  logic                 in_sof,
    input  logic                 in_frame_end,
    output logic                 out_valid,
    output logic [7:0]           p00, p01, p02,
    output logic [7:0]           p10, p11, p12,
    output logic [7:0]           p20, p21, p22,
    output logic [X_WIDTH-1:0]   center_x,
    output logic [Y_WIDTH-1:0]   center_y
);
    logic frame_active;
    wire accept_pixel = in_valid && (frame_active || in_sof);
    wire restart_line1 = accept_pixel && in_sof;

    logic [7:0] line1_data;
    logic [7:0] line2_data;
    logic valid_s1, sof_s1;
    logic [7:0] current_s1;
    logic [X_WIDTH-1:0] x_s1;
    logic [Y_WIDTH-1:0] y_s1;

    logic valid_s2;
    logic [7:0] top_s2, middle_s2, current_s2;
    logic [X_WIDTH-1:0] x_s2;
    logic [Y_WIDTH-1:0] y_s2;

    logic [7:0] top_m2, top_m1;
    logic [7:0] middle_m2, middle_m1;
    logic [7:0] bottom_m2, bottom_m1;

    // The first RAM output has one clock of observation latency before it can
    // enter the second RAM. DELAY_PIXELS=WIDTH-1 in the second stage compensates
    // that clock, so top/middle/current remain at the same column.
    line_delay_ram8 #(.DELAY_PIXELS(WIDTH)) u_line_y_minus_1 (
        .clk(clk), .rst_n(rst_n), .restart(restart_line1),
        .enable(accept_pixel), .data_in(gray_in), .data_out(line1_data)
    );

    line_delay_ram8 #(.DELAY_PIXELS(WIDTH-1)) u_line_y_minus_2 (
        .clk(clk), .rst_n(rst_n), .restart(valid_s1 && sof_s1),
        .enable(valid_s1), .data_in(line1_data), .data_out(line2_data)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_active <= 1'b0;
            valid_s1 <= 1'b0;
            sof_s1 <= 1'b0;
            current_s1 <= 8'd0;
            x_s1 <= '0;
            y_s1 <= '0;
            valid_s2 <= 1'b0;
            top_s2 <= 8'd0;
            middle_s2 <= 8'd0;
            current_s2 <= 8'd0;
            x_s2 <= '0;
            y_s2 <= '0;
            top_m2 <= 8'd0;
            top_m1 <= 8'd0;
            middle_m2 <= 8'd0;
            middle_m1 <= 8'd0;
            bottom_m2 <= 8'd0;
            bottom_m1 <= 8'd0;
            out_valid <= 1'b0;
            p00 <= 8'd0; p01 <= 8'd0; p02 <= 8'd0;
            p10 <= 8'd0; p11 <= 8'd0; p12 <= 8'd0;
            p20 <= 8'd0; p21 <= 8'd0; p22 <= 8'd0;
            center_x <= '0;
            center_y <= '0;
        end else begin
            out_valid <= 1'b0;

            if (accept_pixel && in_sof) begin
                // A new SOF abandons any partial pipeline state. RAM contents
                // remain untouched and are overwritten before becoming valid.
                frame_active <= 1'b1;
                valid_s1 <= 1'b1;
                sof_s1 <= 1'b1;
                current_s1 <= gray_in;
                x_s1 <= in_x;
                y_s1 <= in_y;
                valid_s2 <= 1'b0;
                top_m2 <= 8'd0; top_m1 <= 8'd0;
                middle_m2 <= 8'd0; middle_m1 <= 8'd0;
                bottom_m2 <= 8'd0; bottom_m1 <= 8'd0;
            end else begin
                valid_s1 <= accept_pixel;
                sof_s1 <= 1'b0;
                if (accept_pixel) begin
                    current_s1 <= gray_in;
                    x_s1 <= in_x;
                    y_s1 <= in_y;
                end

                valid_s2 <= valid_s1;
                if (valid_s1) begin
                    top_s2 <= line2_data;
                    middle_s2 <= line1_data;
                    current_s2 <= current_s1;
                    x_s2 <= x_s1;
                    y_s2 <= y_s1;
                end

                if (valid_s2) begin
                    if (x_s2 == 0) begin
                        top_m2 <= 8'd0;
                        top_m1 <= top_s2;
                        middle_m2 <= 8'd0;
                        middle_m1 <= middle_s2;
                        bottom_m2 <= 8'd0;
                        bottom_m1 <= current_s2;
                    end else begin
                        top_m2 <= top_m1;
                        top_m1 <= top_s2;
                        middle_m2 <= middle_m1;
                        middle_m1 <= middle_s2;
                        bottom_m2 <= bottom_m1;
                        bottom_m1 <= current_s2;
                    end

                    if ((x_s2 >= 2) && (y_s2 >= 2)) begin
                        p00 <= top_m2;
                        p01 <= top_m1;
                        p02 <= top_s2;
                        p10 <= middle_m2;
                        p11 <= middle_m1;
                        p12 <= middle_s2;
                        p20 <= bottom_m2;
                        p21 <= bottom_m1;
                        p22 <= current_s2;
                        center_x <= x_s2 - 1'b1;
                        center_y <= y_s2 - 1'b1;
                        out_valid <= 1'b1;
                    end
                end
            end

            if (in_frame_end)
                frame_active <= 1'b0;
        end
    end
endmodule
