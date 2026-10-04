`timescale 1ns/1ps

// Double buffer for a 320x240 preview containing one 8-bit grayscale sample
// and one binary edge sample per location. Two 9-bit pixels are packed in each
// native 20-bit RAM word, reducing the two-frame store to 150 RAM10 blocks.
module split_pingpong_framebuffer #(
    parameter int IMAGE_WIDTH = 320,
    parameter int IMAGE_HEIGHT = 240,
    parameter int DISPLAY_WIDTH = 640,
    parameter int DISPLAY_HEIGHT = 480,
    parameter int DISPLAY_MODE = 0, // 0 split, 1 gray full, 2 edge full
    parameter bit SIM_BEHAVIORAL_RAM = 1'b0
) (
    input  logic        wr_clk,
    input  logic        wr_rst_n,
    input  logic [7:0]  wr_gray,
    input  logic        wr_edge,
    input  logic        wr_valid,
    input  logic        wr_start_of_frame,
    input  logic        wr_frame_end,
    input  logic        wr_frame_good,
    input  logic [10:0] wr_frame_threshold,
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
    output logic [7:0]  rd_gray,
    output logic        rd_edge,
    output logic        rd_gray_view,
    output logic        rd_edge_view,
    output logic        rd_pixel_valid,
    output logic        display_has_frame,
    output logic [31:0] displayed_frame_count,
    output logic [10:0] displayed_frame_threshold
);
    localparam int PIXELS_PER_WORD = 2;
    localparam int WORDS_PER_LINE = IMAGE_WIDTH / PIXELS_PER_WORD;
    localparam int WORDS_PER_FRAME = WORDS_PER_LINE * IMAGE_HEIGHT;
    localparam int PIXELS_PER_FRAME = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam int ADDR_WIDTH = $clog2(WORDS_PER_FRAME);

    logic capture_active, write_bank;
    logic [ADDR_WIDTH:0] write_word_count;
    logic pack_count;
    logic [8:0] pack_pixel0;
    logic [31:0] sampled_pixel_count;
    logic ready_toggle_wr, ready_bank_wr;
    logic [10:0] capture_threshold_wr, ready_threshold_wr;
    logic mem_we0, mem_we1;
    logic [ADDR_WIDTH-1:0] mem_waddr;
    logic [19:0] mem_wdata;
    (* async_reg = "true" *) logic [1:0] ack_toggle_wr_sync;
    (* async_reg = "true" *) logic [1:0] active_bank_wr_sync;

    logic ack_toggle_rd, active_bank_rd;
    (* async_reg = "true" *) logic [2:0] ready_toggle_rd_sync;
    (* async_reg = "true" *) logic [1:0] ready_bank_rd_sync;
    (* async_reg = "true" *) logic [10:0] ready_threshold_rd_meta;
    (* async_reg = "true" *) logic [10:0] ready_threshold_rd_sync;

    logic rd_request, rd_select, rd_select_d;
    logic gray_view_req, edge_view_req;
    logic gray_view_d, edge_view_d;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [19:0] rd_word0, rd_word1, rd_word;
    logic [8:0] rd_sample;
    logic [11:0] image_x, image_y;
    logic [11:0] panel_x, panel_y;
    logic [20:0] rd_addr_full;
    logic [12:0] panel_x_numer;
    logic [12:0] panel_x_scaled;
    logic [13:0] panel_y_numer;

    wire [8:0] wr_sample = {wr_edge, wr_gray};
    wire no_frame_pending = (ack_toggle_wr_sync[1] == ready_toggle_wr);
    wire same_cycle_sample = wr_valid && capture_active && !wr_start_of_frame;
    wire [ADDR_WIDTH:0] final_word_count = write_word_count +
        ((same_cycle_sample && pack_count) ? 1'b1 : 1'b0);
    wire final_pack_count = same_cycle_sample ? ~pack_count : pack_count;
    wire [31:0] final_sample_count = sampled_pixel_count + same_cycle_sample;

    frame_ram20 #(.DEPTH(WORDS_PER_FRAME),
                  .FORCE_BEHAVIORAL(SIM_BEHAVIORAL_RAM)) u_frame0 (
        wr_clk, mem_we0, mem_waddr, mem_wdata,
        rd_clk, rd_request, rd_addr, rd_word0
    );
    frame_ram20 #(.DEPTH(WORDS_PER_FRAME),
                  .FORCE_BEHAVIORAL(SIM_BEHAVIORAL_RAM)) u_frame1 (
        wr_clk, mem_we1, mem_waddr, mem_wdata,
        rd_clk, rd_request, rd_addr, rd_word1
    );

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
            pack_count <= 1'b0;
            pack_pixel0 <= 9'd0;
            sampled_pixel_count <= 32'd0;
            ready_toggle_wr <= 1'b0;
            ready_bank_wr <= 1'b0;
            capture_threshold_wr <= 11'd128;
            ready_threshold_wr <= 11'd128;
            buffer_error_wr <= 1'b0;
            buffer_error_code_wr <= 4'h0;
            frame_committed_wr <= 1'b0;
            last_sampled_pixel_count_wr <= 32'd0;
            last_written_word_count_wr <= 16'd0;
            committed_frame_count_wr <= 32'd0;
            dropped_frame_count <= 32'd0;
            mem_we0 <= 1'b0;
            mem_we1 <= 1'b0;
            mem_waddr <= '0;
            mem_wdata <= 20'd0;
        end else begin
            mem_we0 <= 1'b0;
            mem_we1 <= 1'b0;
            if (wr_start_of_frame) begin
                write_word_count <= '0;
                pack_count <= 1'b0;
                sampled_pixel_count <= 32'd0;
                if (no_frame_pending) begin
                    capture_active <= 1'b1;
                    write_bank <= ~active_bank_wr_sync[1];
                    capture_threshold_wr <= wr_frame_threshold;
                    pack_pixel0 <= wr_sample;
                    pack_count <= 1'b1;
                    sampled_pixel_count <= 32'd1;
                    if ((wr_x != 0) || (wr_y != 0)) begin
                        buffer_error_wr <= 1'b1;
                        buffer_error_code_wr <= 4'b0001;
                    end
                end else begin
                    capture_active <= 1'b0;
                    dropped_frame_count <= dropped_frame_count + 1'b1;
                end
            end else if (wr_valid && capture_active) begin
                sampled_pixel_count <= sampled_pixel_count + 1'b1;
                if (!pack_count) begin
                    pack_pixel0 <= wr_sample;
                end else begin
                    mem_waddr <= write_word_count[ADDR_WIDTH-1:0];
                    mem_wdata <= {2'b00, wr_sample, pack_pixel0};
                    mem_we1 <= write_bank;
                    mem_we0 <= ~write_bank;
                    write_word_count <= write_word_count + 1'b1;
                end
                pack_count <= ~pack_count;
            end

            if (wr_frame_end && capture_active) begin
                capture_active <= 1'b0;
                last_sampled_pixel_count_wr <= final_sample_count;
                last_written_word_count_wr <= final_word_count[15:0];
                if (wr_frame_good &&
                    (final_sample_count == PIXELS_PER_FRAME) &&
                    (final_word_count == WORDS_PER_FRAME) &&
                    !final_pack_count) begin
                    ready_bank_wr <= write_bank;
                    ready_threshold_wr <= capture_threshold_wr;
                    ready_toggle_wr <= ~ready_toggle_wr;
                    frame_committed_wr <= 1'b1;
                    committed_frame_count_wr <= committed_frame_count_wr + 1'b1;
                    buffer_error_wr <= 1'b0;
                    buffer_error_code_wr <= 4'h0;
                end else begin
                    buffer_error_wr <= 1'b1;
                    buffer_error_code_wr[0] <=
                        (final_sample_count != PIXELS_PER_FRAME);
                    buffer_error_code_wr[1] <=
                        (final_word_count != WORDS_PER_FRAME);
                    buffer_error_code_wr[2] <= final_pack_count;
                    buffer_error_code_wr[3] <= !wr_frame_good;
                end
            end
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            ready_toggle_rd_sync <= 3'b000;
            ready_bank_rd_sync <= 2'b00;
            ready_threshold_rd_meta <= 11'd128;
            ready_threshold_rd_sync <= 11'd128;
        end else begin
            ready_toggle_rd_sync <= {ready_toggle_rd_sync[1:0], ready_toggle_wr};
            ready_bank_rd_sync <= {ready_bank_rd_sync[0], ready_bank_wr};
            ready_threshold_rd_meta <= ready_threshold_wr;
            ready_threshold_rd_sync <= ready_threshold_rd_meta;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            ack_toggle_rd <= 1'b0;
            active_bank_rd <= 1'b0;
            display_has_frame <= 1'b0;
            displayed_frame_count <= 32'd0;
            displayed_frame_threshold <= 11'd128;
        end else if (rd_frame_tick &&
                     (ready_toggle_rd_sync[2] != ack_toggle_rd)) begin
            active_bank_rd <= ready_bank_rd_sync[1];
            display_has_frame <= 1'b1;
            displayed_frame_count <= displayed_frame_count + 1'b1;
            displayed_frame_threshold <= ready_threshold_rd_sync;
            ack_toggle_rd <= ready_toggle_rd_sync[2];
        end
    end

    always_comb begin
        // Reconstruct the final physical landscape coordinate under the
        // already hardware-accepted portrait-panel stretch plus clockwise
        // screen rotation. HDMI (x,y) -> physical landscape (panel_x,panel_y).
        panel_x_numer = (13'd480 - {1'b0, rd_y}) << 2;
        panel_x_scaled = panel_x_numer / 13'd3;
        panel_x = panel_x_scaled[11:0] - 12'd1;
        panel_y_numer = ({2'b00, rd_x} << 1) + {2'b00, rd_x};
        panel_y = panel_y_numer >> 2;
        image_x = 12'd0;
        image_y = 12'd0;
        gray_view_req = 1'b0;
        edge_view_req = 1'b0;

        if (DISPLAY_MODE == 1) begin
            image_x = panel_x >> 1;
            image_y = panel_y >> 1;
            gray_view_req = 1'b1;
        end else if (DISPLAY_MODE == 2) begin
            image_x = panel_x >> 1;
            image_y = panel_y >> 1;
            edge_view_req = 1'b1;
        end else if ((panel_y >= 12'd120) && (panel_y < 12'd360)) begin
            image_y = panel_y - 12'd120;
            if (panel_x < 12'd320) begin
                image_x = panel_x;
                gray_view_req = 1'b1;
            end else begin
                image_x = panel_x - 12'd320;
                edge_view_req = 1'b1;
            end
        end

        rd_request = display_has_frame && rd_de &&
                     (gray_view_req || edge_view_req) &&
                     (image_x < IMAGE_WIDTH) && (image_y < IMAGE_HEIGHT);
        rd_addr_full = image_y * WORDS_PER_LINE + (image_x >> 1);
        rd_addr = rd_addr_full[ADDR_WIDTH-1:0];
        rd_select = image_x[0];
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_select_d <= 1'b0;
            gray_view_d <= 1'b0;
            edge_view_d <= 1'b0;
            rd_pixel_valid <= 1'b0;
        end else begin
            rd_select_d <= rd_select;
            gray_view_d <= gray_view_req;
            edge_view_d <= edge_view_req;
            rd_pixel_valid <= rd_request;
        end
    end

    assign rd_word = active_bank_rd ? rd_word1 : rd_word0;
    assign rd_sample = rd_select_d ? rd_word[17:9] : rd_word[8:0];
    assign rd_gray = rd_sample[7:0];
    assign rd_edge = rd_sample[8];
    assign rd_gray_view = rd_pixel_valid && gray_view_d;
    assign rd_edge_view = rd_pixel_valid && edge_view_d;
endmodule
