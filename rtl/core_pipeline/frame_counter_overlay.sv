`timescale 1ns/1ps

// Font-independent frame diagnostics in the physical landscape top black bar.
// Each row contains a colored tag followed by 32 binary cells, LSB first.
module frame_counter_overlay (
    input  logic        de,
    input  logic [11:0] hdmi_x,
    input  logic [11:0] hdmi_y,
    input  logic        counters_valid,
    input  logic [31:0] input_sof_count,
    input  logic [31:0] capture_good_count,
    input  logic [31:0] capture_bad_count,
    input  logic [31:0] algorithm_good_count,
    input  logic [31:0] committed_frame_count,
    input  logic [31:0] busy_drop_count,
    input  logic [31:0] displayed_frame_count,
    input  logic [7:0]  base_red,
    input  logic [7:0]  base_green,
    input  logic [7:0]  base_blue,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue
);
    logic [11:0] panel_x, panel_y;
    logic [12:0] panel_x_numer, panel_x_scaled;
    logic [13:0] panel_y_numer;
    logic row_active, tag_active, bit_active;
    logic [2:0] row_index;
    logic [5:0] bit_index;
    logic [11:0] row_delta, bit_delta;
    logic [31:0] row_value;

    always_comb begin
        panel_x_numer = (13'd480 - {1'b0, hdmi_y}) << 2;
        panel_x_scaled = panel_x_numer / 13'd3;
        panel_x = panel_x_scaled[11:0] - 12'd1;
        panel_y_numer = ({2'b00, hdmi_x} << 1) + {2'b00, hdmi_x};
        panel_y = panel_y_numer >> 2;

        red = base_red;
        green = base_green;
        blue = base_blue;
        row_active = 1'b0;
        tag_active = 1'b0;
        bit_active = 1'b0;
        row_index = 3'd0;
        bit_index = 6'd0;
        row_delta = 12'd0;
        bit_delta = 12'd0;
        row_value = 32'd0;

        // Seven 12-pixel-high rows on a 16-pixel pitch at physical y=4..111.
        if ((panel_y >= 12'd4) && (panel_y < 12'd116)) begin
            row_delta = panel_y - 12'd4;
            row_index = row_delta[6:4];
            row_active = (row_delta[3:0] < 4'd12) &&
                         (row_index < 3'd7);
        end

        case (row_index)
            3'd0: row_value = input_sof_count;
            3'd1: row_value = capture_good_count;
            3'd2: row_value = capture_bad_count;
            3'd3: row_value = algorithm_good_count;
            3'd4: row_value = committed_frame_count;
            3'd5: row_value = busy_drop_count;
            default: row_value = displayed_frame_count;
        endcase

        tag_active = row_active && (panel_x >= 12'd8) && (panel_x < 12'd72);
        if (row_active && (panel_x >= 12'd96) && (panel_x < 12'd608)) begin
            bit_delta = panel_x - 12'd96;
            bit_index = {1'b0, bit_delta[8:4]};
            bit_active = (bit_delta[3:0] < 4'd12) &&
                         (bit_index < 6'd32);
        end

        if (de && tag_active) begin
            case (row_index)
                3'd0: begin red = 8'h20; green = 8'h60; blue = 8'hff; end
                3'd1: begin red = 8'h00; green = 8'hff; blue = 8'h20; end
                3'd2: begin red = 8'hff; green = 8'h20; blue = 8'h20; end
                3'd3: begin red = 8'h00; green = 8'hff; blue = 8'hff; end
                3'd4: begin red = 8'hff; green = 8'hd0; blue = 8'h00; end
                3'd5: begin red = 8'hff; green = 8'h20; blue = 8'hff; end
                default: begin red = 8'hff; green = 8'hff; blue = 8'hff; end
            endcase
        end else if (de && bit_active) begin
            if (!counters_valid) begin
                red = 8'h90; green = 8'h60; blue = 8'h00;
            end else if (row_value[bit_index]) begin
                red = 8'hff; green = 8'hff; blue = 8'hff;
            end else begin
                red = 8'h18; green = 8'h18; blue = 8'h18;
            end
        end

        if (!de) begin
            red = 8'h00;
            green = 8'h00;
            blue = 8'h00;
        end
    end
endmodule
