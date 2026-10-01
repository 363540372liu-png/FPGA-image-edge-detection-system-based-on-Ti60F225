`timescale 1ns/1ps

// This lightweight RAM model keeps the integration test focused on the
// algorithm output contract, 5-pixel packing, and frame commit accounting.
// Native RAM read/mapping remains covered by the accepted framebuffer tests.
module frame_ram20 #(
    parameter int DEPTH = 15360,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic wr_clk, wr_en,
    input logic [ADDR_WIDTH-1:0] wr_addr,
    input logic [19:0] wr_data,
    input logic rd_clk, rd_en,
    input logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [19:0] rd_data
);
    assign rd_data = 20'h0;
endmodule

module tb_sobel_framebuffer_integration;
    localparam integer WIDTH = 640;
    localparam integer HEIGHT = 480;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [7:0] gray_in = 8'd0;
    logic in_valid = 1'b0;
    logic [9:0] in_x = 10'd0;
    logic [8:0] in_y = 9'd0;
    logic in_sof = 1'b0;
    logic in_eof = 1'b0;

    logic window_valid;
    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    logic [9:0] window_x;
    logic [8:0] window_y;
    logic sobel_valid, sobel_edge;
    logic signed [10:0] sobel_gx, sobel_gy;
    logic [10:0] sobel_magnitude;
    logic [9:0] sobel_x;
    logic [8:0] sobel_y;
    logic full_valid, full_edge, full_sof, full_eof, full_good;
    logic [9:0] full_x;
    logic [8:0] full_y;
    logic fifo_overflow, full_coordinate_error, frame_queue_overflow, good_queue_overflow;
    logic [4:0] fifo_level, fifo_max_level;
    logic preview_valid, preview_sof, preview_eof, preview_good;
    logic [15:0] preview_pixel;
    logic [11:0] preview_x, preview_y;
    logic preview_coordinate_error;

    logic buffer_error_wr, frame_committed_wr;
    logic [3:0] buffer_error_code_wr;
    logic [31:0] last_sampled_pixel_count_wr;
    logic [15:0] last_written_word_count_wr;
    logic [31:0] committed_frame_count_wr, dropped_frame_count;
    logic rd_frame_tick = 1'b0;
    logic [15:0] rd_pixel;
    logic rd_pixel_valid, display_has_frame;
    logic [31:0] displayed_frame_count;
    integer preview_count;
    integer timeout_count;

    always #5 clk = ~clk;

    gray_window_3x3 u_window (
        .clk(clk), .rst_n(rst_n), .gray_in(gray_in), .in_valid(in_valid),
        .in_x(in_x), .in_y(in_y), .in_sof(in_sof), .in_frame_end(in_eof),
        .out_valid(window_valid),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .center_x(window_x), .center_y(window_y)
    );

    sobel_threshold u_sobel (
        .clk(clk), .rst_n(rst_n), .flush(in_valid && in_sof),
        .in_valid(window_valid),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .in_x(window_x), .in_y(window_y), .threshold_in(11'd128),
        .out_valid(sobel_valid), .edge_out(sobel_edge),
        .gx_out(sobel_gx), .gy_out(sobel_gy), .magnitude_out(sobel_magnitude),
        .out_x(sobel_x), .out_y(sobel_y)
    );

    edge_full_frame_stream u_full (
        .clk(clk), .rst_n(rst_n), .input_sof(in_valid && in_sof),
        .input_frame_end(in_eof), .input_frame_good(in_eof),
        .interior_valid(sobel_valid), .interior_edge(sobel_edge),
        .interior_x(sobel_x), .interior_y(sobel_y),
        .out_valid(full_valid), .out_edge(full_edge), .out_x(full_x), .out_y(full_y),
        .out_sof(full_sof), .out_frame_end(full_eof), .out_frame_good(full_good),
        .fifo_overflow(fifo_overflow), .coordinate_error(full_coordinate_error),
        .frame_queue_overflow(frame_queue_overflow),
        .good_queue_overflow(good_queue_overflow),
        .fifo_level_dbg(fifo_level), .fifo_max_level_dbg(fifo_max_level)
    );

    edge_preview_2x2_or u_preview (
        .clk(clk), .rst_n(rst_n), .in_valid(full_valid), .edge_in(full_edge),
        .in_x(full_x), .in_y(full_y), .in_sof(full_sof),
        .in_frame_end(full_eof), .in_frame_good(full_good),
        .out_valid(preview_valid), .out_pixel565(preview_pixel),
        .out_x(preview_x), .out_y(preview_y), .out_sof(preview_sof),
        .out_frame_end(preview_eof), .out_frame_good(preview_good),
        .coordinate_error(preview_coordinate_error)
    );

    packed_pingpong_framebuffer #(
        .SOURCE_WIDTH(320), .SOURCE_HEIGHT(240),
        .SAMPLE_X_STEP(1), .SAMPLE_Y_STEP(1),
        .IMAGE_WIDTH(320), .IMAGE_HEIGHT(240),
        .DISPLAY_WIDTH(640), .DISPLAY_HEIGHT(480),
        .DISPLAY_SCALE(1), .ROTATE_CCW_FOR_CW_PANEL(1'b1)
    ) u_framebuffer (
        .wr_clk(clk), .wr_rst_n(rst_n),
        .wr_pixel(preview_pixel), .wr_pixel_valid(preview_valid),
        .wr_start_of_frame(preview_sof), .wr_frame_end(preview_eof),
        .wr_frame_good(preview_good), .wr_x(preview_x), .wr_y(preview_y),
        .buffer_error_wr(buffer_error_wr), .buffer_error_code_wr(buffer_error_code_wr),
        .frame_committed_wr(frame_committed_wr),
        .last_sampled_pixel_count_wr(last_sampled_pixel_count_wr),
        .last_written_word_count_wr(last_written_word_count_wr),
        .committed_frame_count_wr(committed_frame_count_wr),
        .dropped_frame_count(dropped_frame_count),
        .rd_clk(clk), .rd_rst_n(rst_n), .rd_x(12'd0), .rd_y(12'd0),
        .rd_de(1'b0), .rd_frame_tick(rd_frame_tick),
        .rd_pixel(rd_pixel), .rd_pixel_valid(rd_pixel_valid),
        .display_has_frame(display_has_frame), .displayed_frame_count(displayed_frame_count)
    );

    function automatic [7:0] pattern(input integer x, input integer y);
        pattern = ((x[5:0] ^ y[5:0]) << 2) | (x[1:0] ^ y[1:0]);
    endfunction

    always @(posedge clk) begin
        #1;
        if (preview_valid) begin
            if ((preview_x != (preview_count % 320)) ||
                (preview_y != (preview_count / 320)))
                $fatal(1, "preview order mismatch count=%0d coord=(%0d,%0d)",
                       preview_count, preview_x, preview_y);
            preview_count = preview_count + 1;
        end
    end

    integer index;
    integer x;
    integer y;
    initial begin
        preview_count = 0;
        timeout_count = 0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        for (index = 0; index < WIDTH*HEIGHT; index = index + 1) begin
            x = index % WIDTH;
            y = index / WIDTH;
            @(negedge clk);
            gray_in = pattern(x, y);
            in_x = x;
            in_y = y;
            in_valid = 1'b1;
            in_sof = (index == 0);
            in_eof = (index == WIDTH*HEIGHT-1);
        end
        @(negedge clk);
        in_valid = 1'b0;
        in_sof = 1'b0;
        in_eof = 1'b0;
        wait (frame_committed_wr);
        repeat (4) @(negedge clk);

        if (preview_count != 76800)
            $fatal(1, "preview count=%0d expected=76800", preview_count);
        if (committed_frame_count_wr != 1 || buffer_error_wr ||
            buffer_error_code_wr != 0 || dropped_frame_count != 0)
            $fatal(1, "commit result count=%0d error=%0b code=%h drop=%0d",
                   committed_frame_count_wr, buffer_error_wr,
                   buffer_error_code_wr, dropped_frame_count);
        if ((last_sampled_pixel_count_wr != 76800) ||
            (last_written_word_count_wr != 15360))
            $fatal(1, "pack accounting samples=%0d words=%0d",
                   last_sampled_pixel_count_wr, last_written_word_count_wr);
        if (fifo_overflow || full_coordinate_error || frame_queue_overflow ||
            good_queue_overflow || preview_coordinate_error)
            $fatal(1, "unexpected algorithm sticky error");

        @(negedge clk); rd_frame_tick = 1'b1;
        @(negedge clk); rd_frame_tick = 1'b0;
        repeat (5) @(negedge clk);
        if (!display_has_frame || displayed_frame_count != 1)
            $fatal(1, "display side did not accept committed frame");

        $display("PASS tb_sobel_framebuffer_integration: 307200 source -> 76800 OR preview -> 15360 packed words -> display accept");
        $finish;
    end

    always @(posedge clk) begin
        timeout_count <= timeout_count + 1;
        if (timeout_count > 1_000_000)
            $fatal(1, "tb_sobel_framebuffer_integration timeout");
    end
endmodule
