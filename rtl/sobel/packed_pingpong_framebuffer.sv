`timescale 1ns/1ps
module packed_pingpong_framebuffer #(
    parameter int SOURCE_WIDTH  = 640,
    parameter int SOURCE_HEIGHT = 480,
    parameter int SAMPLE_X_STEP = 2,
    parameter int SAMPLE_Y_STEP = 2,
    parameter int IMAGE_WIDTH   = 320,
    parameter int IMAGE_HEIGHT  = 240,
    parameter int DISPLAY_WIDTH = 640,
    parameter int DISPLAY_HEIGHT = 480,
    parameter int DISPLAY_SCALE = 1,
    parameter bit ROTATE_CCW_FOR_CW_PANEL = 1'b0
) (
    input  logic        wr_clk,
    input  logic        wr_rst_n,
    input  logic [15:0] wr_pixel,
    input  logic        wr_pixel_valid,
    input  logic        wr_start_of_frame,
    input  logic        wr_frame_end,
    input  logic        wr_frame_good,
    input  logic [11:0] wr_x,
    input  logic [11:0] wr_y,
    output logic        buffer_error_wr,
    output logic [3:0]  buffer_error_code_wr,
    output logic        frame_committed_wr,
    output logic [31:0] last_sampled_pixel_count_wr,
    output logic [15:0] last_written_word_count_wr,
    output logic [31:0] committed_frame_count_wr,
    output logic [31:0] dropped_frame_count,

    input  logic        rd_clk,
    input  logic        rd_rst_n,
    input  logic [11:0] rd_x,
    input  logic [11:0] rd_y,
    input  logic        rd_de,
    input  logic        rd_frame_tick,
    output logic [15:0] rd_pixel,
    output logic        rd_pixel_valid,
    output logic        display_has_frame,
    output logic [31:0] displayed_frame_count
);
    localparam int PIXELS_PER_WORD = 5;
    localparam int WORDS_PER_LINE  = IMAGE_WIDTH / PIXELS_PER_WORD;
    localparam int WORDS_PER_FRAME = WORDS_PER_LINE * IMAGE_HEIGHT;
    localparam int SAMPLED_PIXELS_PER_FRAME = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam int ADDR_WIDTH      = $clog2(WORDS_PER_FRAME);
    localparam int SCALED_WIDTH    = IMAGE_WIDTH * DISPLAY_SCALE;
    localparam int SCALED_HEIGHT   = IMAGE_HEIGHT * DISPLAY_SCALE;
    localparam int X_OFFSET        = (DISPLAY_WIDTH - SCALED_WIDTH) / 2;
    localparam int Y_OFFSET        = (DISPLAY_HEIGHT - SCALED_HEIGHT) / 2;
    localparam logic [11:0] X_OFFSET_12 = X_OFFSET;
    localparam logic [11:0] Y_OFFSET_12 = Y_OFFSET;
    localparam logic [11:0] X_LIMIT_12 = X_OFFSET + SCALED_WIDTH;
    localparam logic [11:0] Y_LIMIT_12 = Y_OFFSET + SCALED_HEIGHT;

    logic capture_active;
    logic write_bank;
    logic [ADDR_WIDTH:0] write_word_count;
    logic [2:0] pack_count;
    logic [79:0] pack_data;
    logic [31:0] sampled_pixel_count;
    logic ready_toggle_wr, ready_bank_wr;
    logic mem_we0, mem_we1;
    logic [ADDR_WIDTH-1:0] mem_waddr;
    logic [79:0] mem_wdata;
    (* async_reg = "true" *) logic [1:0] ack_toggle_wr_sync;
    (* async_reg = "true" *) logic [1:0] active_bank_wr_sync;

    logic ack_toggle_rd, active_bank_rd;
    (* async_reg = "true" *) logic [1:0] ready_toggle_rd_sync;
    (* async_reg = "true" *) logic [1:0] ready_bank_rd_sync;

    logic rd_request;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [2:0] rd_select;
    logic [2:0] rd_select_d;
    logic [19:0] rd0_lane0, rd0_lane1, rd0_lane2, rd0_lane3;
    logic [19:0] rd1_lane0, rd1_lane1, rd1_lane2, rd1_lane3;
    logic [79:0] rd_word0, rd_word1, rd_word;
    logic [11:0] image_x, image_y;
    logic [18:0] rd_addr_full;
    logic [12:0] rotate_x_numer, rotate_x_scaled;
    logic [13:0] rotate_y_numer, rotate_y_scaled;
    localparam logic [11:0] IMAGE_X_MAX_12 = IMAGE_WIDTH - 1;

    wire no_frame_pending = (ack_toggle_wr_sync[1] == ready_toggle_wr);
    wire sample_pixel = wr_pixel_valid &&
                        ((wr_x % SAMPLE_X_STEP) == 0) &&
                        ((wr_y % SAMPLE_Y_STEP) == 0);
    wire same_cycle_sample = sample_pixel && capture_active &&
                             !wr_start_of_frame;
    wire [ADDR_WIDTH:0] final_word_count = write_word_count +
        ((same_cycle_sample && (pack_count == 3'd4)) ? 1'b1 : 1'b0);
    wire [2:0] final_pack_count = same_cycle_sample ?
        ((pack_count == 3'd4) ? 3'd0 : pack_count + 1'b1) : pack_count;
    wire [31:0] final_sample_count = sampled_pixel_count + same_cycle_sample;

    // Four native 20-bit RAM lanes per frame preserve all RGB565 bits while
    // using the Titanium RAM10 native 512x20 aspect ratio.
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME)) u_f0_l0
        (wr_clk, mem_we0, mem_waddr, mem_wdata[19:0], rd_clk, rd_request, rd_addr, rd0_lane0);
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME)) u_f0_l1
        (wr_clk, mem_we0, mem_waddr, mem_wdata[39:20], rd_clk, rd_request, rd_addr, rd0_lane1);
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME)) u_f0_l2
        (wr_clk, mem_we0, mem_waddr, mem_wdata[59:40], rd_clk, rd_request, rd_addr, rd0_lane2);
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME)) u_f0_l3
        (wr_clk, mem_we0, mem_waddr, mem_wdata[79:60], rd_clk, rd_request, rd_addr, rd0_lane3);
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME)) u_f1_l0
        (wr_clk, mem_we1, mem_waddr, mem_wdata[19:0], rd_clk, rd_request, rd_addr, rd1_lane0);
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME)) u_f1_l1
        (wr_clk, mem_we1, mem_waddr, mem_wdata[39:20], rd_clk, rd_request, rd_addr, rd1_lane1);
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME)) u_f1_l2
        (wr_clk, mem_we1, mem_waddr, mem_wdata[59:40], rd_clk, rd_request, rd_addr, rd1_lane2);
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME)) u_f1_l3
        (wr_clk, mem_we1, mem_waddr, mem_wdata[79:60], rd_clk, rd_request, rd_addr, rd1_lane3);

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            ack_toggle_wr_sync <= 2'b00;
            active_bank_wr_sync <= 2'b00;
        end else begin
            ack_toggle_wr_sync <= {ack_toggle_wr_sync[0], ack_toggle_rd};
            active_bank_wr_sync <= {active_bank_wr_sync[0], active_bank_rd};
        end
    end

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            capture_active <= 1'b0;
            write_bank <= 1'b1;
            write_word_count <= '0;
            pack_count <= '0;
            pack_data <= '0;
            sampled_pixel_count <= 32'd0;
            ready_toggle_wr <= 1'b0;
            ready_bank_wr <= 1'b0;
            buffer_error_wr <= 1'b0;
            buffer_error_code_wr <= 4'h0;
            frame_committed_wr <= 1'b0;
            last_sampled_pixel_count_wr <= 32'd0;
            last_written_word_count_wr <= 16'd0;
            committed_frame_count_wr <= 32'd0;
            dropped_frame_count <= '0;
            mem_we0 <= 1'b0;
            mem_we1 <= 1'b0;
            mem_waddr <= '0;
            mem_wdata <= '0;
        end else begin
            mem_we0 <= 1'b0;
            mem_we1 <= 1'b0;
            if (wr_start_of_frame) begin
                write_word_count <= '0;
                pack_count <= '0;
                pack_data <= '0;
                sampled_pixel_count <= 32'd0;
                if (no_frame_pending) begin
                    capture_active <= 1'b1;
                    write_bank <= ~active_bank_wr_sync[1];
                    if (sample_pixel) begin
                        // The admitted first pixel should be coordinate (0,0).
                        pack_data[15:0] <= wr_pixel;
                        pack_count <= 3'd1;
                        sampled_pixel_count <= 32'd1;
                    end
                end else begin
                    capture_active <= 1'b0;
                    dropped_frame_count <= dropped_frame_count + 1'b1;
                end
            end else if (sample_pixel && capture_active) begin
                sampled_pixel_count <= sampled_pixel_count + 1'b1;
                case (pack_count)
                    3'd0: pack_data[15:0]  <= wr_pixel;
                    3'd1: pack_data[31:16] <= wr_pixel;
                    3'd2: pack_data[47:32] <= wr_pixel;
                    3'd3: pack_data[63:48] <= wr_pixel;
                    default: begin
                        mem_waddr <= write_word_count[ADDR_WIDTH-1:0];
                        mem_wdata <= {wr_pixel, pack_data[63:0]};
                        mem_we1 <= write_bank;
                        mem_we0 <= ~write_bank;
                        write_word_count <= write_word_count + 1'b1;
                    end
                endcase
                pack_count <= (pack_count == 3'd4) ? 3'd0 : pack_count + 1'b1;
            end

            if (wr_frame_end && capture_active) begin
                capture_active <= 1'b0;
                last_sampled_pixel_count_wr <= final_sample_count;
                last_written_word_count_wr <= final_word_count;
                if (wr_frame_good &&
                    (final_sample_count == SAMPLED_PIXELS_PER_FRAME) &&
                    (final_word_count == WORDS_PER_FRAME) &&
                    (final_pack_count == 0)) begin
                    ready_bank_wr <= write_bank;
                    ready_toggle_wr <= ~ready_toggle_wr;
                    frame_committed_wr <= 1'b1;
                    committed_frame_count_wr <= committed_frame_count_wr + 1'b1;
                    buffer_error_wr <= 1'b0;
                    buffer_error_code_wr <= 4'h0;
                end else begin
                    buffer_error_wr <= 1'b1;
                    buffer_error_code_wr[0] <=
                        (final_sample_count != SAMPLED_PIXELS_PER_FRAME);
                    buffer_error_code_wr[1] <=
                        (final_word_count != WORDS_PER_FRAME);
                    buffer_error_code_wr[2] <= (final_pack_count != 0);
                    buffer_error_code_wr[3] <= !wr_frame_good;
                end
            end
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            ready_toggle_rd_sync <= 2'b00;
            ready_bank_rd_sync <= 2'b00;
        end else begin
            ready_toggle_rd_sync <= {ready_toggle_rd_sync[0], ready_toggle_wr};
            ready_bank_rd_sync <= {ready_bank_rd_sync[0], ready_bank_wr};
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            ack_toggle_rd <= 1'b0;
            active_bank_rd <= 1'b0;
            display_has_frame <= 1'b0;
            displayed_frame_count <= '0;
        end else if (rd_frame_tick &&
                     (ready_toggle_rd_sync[1] != ack_toggle_rd)) begin
            active_bank_rd <= ready_bank_rd_sync[1];
            display_has_frame <= 1'b1;
            displayed_frame_count <= displayed_frame_count + 1'b1;
            ack_toggle_rd <= ready_toggle_rd_sync[1];
        end
    end

    always_comb begin
        rotate_x_numer  = {1'b0, rd_y} << 1;
        rotate_x_scaled = rotate_x_numer / 3;
        rotate_y_numer  = ({2'b00, rd_x} << 1) + {2'b00, rd_x};
        rotate_y_scaled = rotate_y_numer >> 3;
        if (ROTATE_CCW_FOR_CW_PANEL) begin
            // The 640x480 HDMI raster is assumed to be stretched by the
            // controller onto its native 480x640 portrait panel. Pre-rotate
            // CCW and compensate both scale axes so a physical CW turn makes
            // the final 640x480 landscape view upright with square 2x pixels.
            // Fixed current geometry reduces exactly to 320/480 = 2/3 and
            // 240/640 = 3/8. Explicit widths avoid silent truncation, while
            // shift/add replaces the general constant multiplier.
            image_x = IMAGE_X_MAX_12 - rotate_x_scaled[11:0];
            image_y = rotate_y_scaled[11:0];
            rd_request = display_has_frame && rd_de &&
                         (rd_x < DISPLAY_WIDTH) &&
                         (rd_y < DISPLAY_HEIGHT);
        end else begin
            image_x = (rd_x - X_OFFSET_12) / DISPLAY_SCALE;
            image_y = (rd_y - Y_OFFSET_12) / DISPLAY_SCALE;
            rd_request = display_has_frame && rd_de &&
                         (rd_x >= X_OFFSET_12) && (rd_x < X_LIMIT_12) &&
                         (rd_y >= Y_OFFSET_12) && (rd_y < Y_LIMIT_12);
        end
        rd_addr_full = (image_y * WORDS_PER_LINE) +
                       (image_x / PIXELS_PER_WORD);
        rd_addr = rd_addr_full[ADDR_WIDTH-1:0];
        rd_select = image_x % PIXELS_PER_WORD;
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_select_d <= '0;
            rd_pixel_valid <= 1'b0;
        end else begin
            rd_pixel_valid <= rd_request;
            rd_select_d <= rd_select;
        end
    end

    assign rd_word0 = {rd0_lane3, rd0_lane2, rd0_lane1, rd0_lane0};
    assign rd_word1 = {rd1_lane3, rd1_lane2, rd1_lane1, rd1_lane0};
    assign rd_word = active_bank_rd ? rd_word1 : rd_word0;

    always_comb begin
        case (rd_select_d)
            3'd0: rd_pixel = rd_word[15:0];
            3'd1: rd_pixel = rd_word[31:16];
            3'd2: rd_pixel = rd_word[47:32];
            3'd3: rd_pixel = rd_word[63:48];
            default: rd_pixel = rd_word[79:64];
        endcase
    end
endmodule
