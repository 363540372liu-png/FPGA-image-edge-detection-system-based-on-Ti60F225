`timescale 1ns/1ps
module display_diagnostic_overlay #(
    parameter bit FORCE_COLOR_BARS = 1'b0
) (
    input  logic        clk_pixel,
    input  logic        rst_n,
    input  logic [11:0] x,
    input  logic [11:0] y,
    input  logic        de,
    input  logic        frame_tick,
    input  logic [15:0] camera_pixel565,
    input  logic        camera_pixel_valid,
    // [0] chip ID, [1] init, [2] PCLK, [3] input frame,
    // [4] buffer commit, [5] display accept, [6] any error.
    input  logic [6:0]  status,
    input  logic        frame_diag_valid,
    // [0] init, [4:1] capture, [8:5] frame-buffer error fields.
    input  logic [8:0]  error_code,
    input  logic [15:0] last_frame_lines,
    input  logic [15:0] last_min_line_bytes,
    input  logic [15:0] last_max_line_bytes,
    input  logic [31:0] last_sampled_pixels,
    input  logic [15:0] last_written_words,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue
);
    logic [11:0] moving_x;
    logic [2:0] status_index;
    logic [11:0] status_x_delta;
    logic [5:0] status_x_local;
    logic status_block;
    logic status_good;
    logic counter_row, counter_cell;
    logic [4:0] counter_index, counter_width;
    logic [3:0] counter_x_local;
    logic [11:0] counter_x_delta;
    logic [31:0] counter_value;
    logic error_block;
    logic [3:0] error_index;

    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n)
            moving_x <= 12'd8;
        else if (frame_tick)
            moving_x <= (moving_x >= 12'd444) ? 12'd8 : moving_x + 12'd4;
    end

    always_comb begin
        status_index = 3'd0;
        status_x_delta = 12'd0;
        status_x_local = 6'd0;
        status_block = 1'b0;
        status_good = 1'b0;
        counter_row = 1'b0;
        counter_cell = 1'b0;
        counter_index = 5'd0;
        counter_width = 5'd0;
        counter_x_local = 4'd0;
        counter_x_delta = 12'd0;
        counter_value = 32'd0;
        error_block = 1'b0;
        error_index = 4'd0;

        if (x < 12'd60) begin
            red = 8'hff; green = 8'hff; blue = 8'hff;
        end else if (x < 12'd120) begin
            red = 8'hff; green = 8'hff; blue = 8'h00;
        end else if (x < 12'd180) begin
            red = 8'h00; green = 8'hff; blue = 8'hff;
        end else if (x < 12'd240) begin
            red = 8'h00; green = 8'hff; blue = 8'h00;
        end else if (x < 12'd300) begin
            red = 8'hff; green = 8'h00; blue = 8'hff;
        end else if (x < 12'd360) begin
            red = 8'hff; green = 8'h00; blue = 8'h00;
        end else if (x < 12'd420) begin
            red = 8'h00; green = 8'h00; blue = 8'hff;
        end else begin
            red = 8'h60; green = 8'h60; blue = 8'h60;
        end

        if (!FORCE_COLOR_BARS && camera_pixel_valid) begin
            red   = {camera_pixel565[15:11], camera_pixel565[15:13]};
            green = {camera_pixel565[10:5],  camera_pixel565[10:9]};
            blue  = {camera_pixel565[4:0],   camera_pixel565[4:2]};
        end

        if ((x < 12'd6) || (x >= 12'd474) ||
            (y < 12'd6) || (y >= 12'd634)) begin
            red = 8'hff; green = y[4] ? 8'hff : 8'h00; blue = 8'hff;
        end

        // Seven 48x32 blocks, left to right, separated by 16-pixel gaps.
        if ((x >= 12'd8) && (x < 12'd456) &&
            (y >= 12'd12) && (y < 12'd44)) begin
            status_x_delta = x - 12'd8;
            status_index = status_x_delta[8:6];
            status_x_local = status_x_delta[5:0];
            status_block = status_x_local < 6'd48;
            if (status_block) begin
                status_good = (status_index == 3'd6) ?
                              ~status[6] : status[status_index];
                if (status_good) begin
                    red = 8'h00; green = 8'hff; blue = 8'h20;
                end else begin
                    red = 8'h90; green = 8'h00; blue = 8'h00;
                end
            end
        end

        // Five binary snapshot rows, LSB at the left. Top to bottom:
        // completed lines, min line bytes, max line bytes, sampled pixels,
        // and written 80-bit words. A cell is 12 pixels wide on a 16-pixel
        // pitch. Amber means no complete-frame snapshot has arrived yet.
        if ((y >= 12'd52) && (y < 12'd64)) begin
            counter_row = 1'b1; counter_value = {16'd0, last_frame_lines};
            counter_width = 5'd10;
        end else if ((y >= 12'd68) && (y < 12'd80)) begin
            counter_row = 1'b1; counter_value = {16'd0, last_min_line_bytes};
            counter_width = 5'd12;
        end else if ((y >= 12'd84) && (y < 12'd96)) begin
            counter_row = 1'b1; counter_value = {16'd0, last_max_line_bytes};
            counter_width = 5'd12;
        end else if ((y >= 12'd100) && (y < 12'd112)) begin
            counter_row = 1'b1; counter_value = last_sampled_pixels;
            counter_width = 5'd17;
        end else if ((y >= 12'd116) && (y < 12'd128)) begin
            counter_row = 1'b1; counter_value = {16'd0, last_written_words};
            counter_width = 5'd14;
        end

        if (counter_row && (x >= 12'd8) && (x < 12'd280)) begin
            counter_x_delta = x - 12'd8;
            counter_index = counter_x_delta[8:4];
            counter_x_local = counter_x_delta[3:0];
            counter_cell = (counter_index < counter_width) &&
                           (counter_x_local < 4'd12);
            if (counter_cell) begin
                if (!frame_diag_valid) begin
                    red = 8'h90; green = 8'h60; blue = 8'h00;
                end else if (counter_value[counter_index]) begin
                    red = 8'h00; green = 8'hff; blue = 8'h20;
                end else begin
                    red = 8'h20; green = 8'h20; blue = 8'h20;
                end
            end
        end

        // Nine error blocks at y=144..175, left to right. Green means clear,
        // red means set; capture/buffer fields are amber before a snapshot.
        for (integer i = 0; i < 9; i = i + 1) begin
            if ((x >= (12'd8 + i * 48)) && (x < (12'd40 + i * 48)) &&
                (y >= 12'd144) && (y < 12'd176)) begin
                error_block = 1'b1;
                error_index = i[3:0];
            end
        end
        if (error_block) begin
            if ((error_index != 0) && !frame_diag_valid) begin
                red = 8'h90; green = 8'h60; blue = 8'h00;
            end else if (error_code[error_index]) begin
                red = 8'hff; green = 8'h00; blue = 8'h00;
            end else begin
                red = 8'h00; green = 8'hff; blue = 8'h20;
            end
        end

        if ((x >= moving_x) && (x < moving_x + 12'd28) &&
            (y >= 12'd590) && (y < 12'd610)) begin
            red = 8'hff; green = 8'hff; blue = 8'hff;
        end

        if (!de) begin
            red = 8'h00; green = 8'h00; blue = 8'h00;
        end
    end
endmodule
