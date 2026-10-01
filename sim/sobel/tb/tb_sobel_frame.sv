`timescale 1ns/1ps

module tb_sobel_frame #(
    parameter integer WIDTH = 8,
    parameter integer HEIGHT = 6,
    parameter integer GAP_INTERVAL = 0
);
    localparam integer X_WIDTH = (WIDTH <= 2) ? 1 : $clog2(WIDTH);
    localparam integer Y_WIDTH = (HEIGHT <= 2) ? 1 : $clog2(HEIGHT);
    localparam integer PIXELS = WIDTH * HEIGHT;
    localparam integer PREVIEW_PIXELS = (WIDTH / 2) * (HEIGHT / 2);

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [7:0] gray_in = 8'd0;
    logic in_valid = 1'b0;
    logic [X_WIDTH-1:0] in_x = '0;
    logic [Y_WIDTH-1:0] in_y = '0;
    logic in_sof = 1'b0;
    logic in_frame_end = 1'b0;

    logic window_valid;
    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    logic [X_WIDTH-1:0] window_x;
    logic [Y_WIDTH-1:0] window_y;
    logic sobel_valid, sobel_edge;
    logic signed [10:0] sobel_gx, sobel_gy;
    logic [10:0] sobel_magnitude;
    logic [X_WIDTH-1:0] sobel_x;
    logic [Y_WIDTH-1:0] sobel_y;
    logic full_valid, full_edge, full_sof, full_eof, full_good;
    logic [X_WIDTH-1:0] full_x;
    logic [Y_WIDTH-1:0] full_y;
    logic fifo_overflow, full_coordinate_error;
    logic frame_queue_overflow, good_queue_overflow;
    logic [4:0] fifo_level, fifo_max_level;
    logic preview_valid, preview_sof, preview_eof, preview_good;
    logic [15:0] preview_pixel;
    logic [11:0] preview_x, preview_y;
    logic preview_coordinate_error;

    logic [7:0] gray_mem [0:PIXELS-1];
    logic [7:0] edge_mem [0:PIXELS-1];
    logic [7:0] preview_mem [0:PREVIEW_PIXELS-1];
    string gray_path;
    string edge_path;
    string preview_path;

    integer errors;
    integer window_count;
    integer sobel_count;
    integer full_count;
    integer preview_count;
    integer timeout_count;
    integer gap_interval_runtime;
    integer gap_arg_present;

    always #5 clk = ~clk;

    gray_window_3x3 #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_window (
        .clk(clk), .rst_n(rst_n),
        .gray_in(gray_in), .in_valid(in_valid), .in_x(in_x), .in_y(in_y),
        .in_sof(in_sof), .in_frame_end(in_frame_end),
        .out_valid(window_valid),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .center_x(window_x), .center_y(window_y)
    );

    sobel_threshold #(.X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH)) u_sobel (
        .clk(clk), .rst_n(rst_n), .flush(in_valid && in_sof),
        .in_valid(window_valid),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .in_x(window_x), .in_y(window_y), .threshold_in(11'd128),
        .out_valid(sobel_valid), .edge_out(sobel_edge),
        .gx_out(sobel_gx), .gy_out(sobel_gy),
        .magnitude_out(sobel_magnitude), .out_x(sobel_x), .out_y(sobel_y)
    );

    edge_full_frame_stream #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_full (
        .clk(clk), .rst_n(rst_n),
        .input_sof(in_valid && in_sof),
        .input_frame_end(in_frame_end), .input_frame_good(in_frame_end),
        .interior_valid(sobel_valid), .interior_edge(sobel_edge),
        .interior_x(sobel_x), .interior_y(sobel_y),
        .out_valid(full_valid), .out_edge(full_edge),
        .out_x(full_x), .out_y(full_y), .out_sof(full_sof),
        .out_frame_end(full_eof), .out_frame_good(full_good),
        .fifo_overflow(fifo_overflow), .coordinate_error(full_coordinate_error),
        .frame_queue_overflow(frame_queue_overflow),
        .good_queue_overflow(good_queue_overflow),
        .fifo_level_dbg(fifo_level), .fifo_max_level_dbg(fifo_max_level)
    );

    edge_preview_2x2_or #(.SOURCE_WIDTH(WIDTH), .SOURCE_HEIGHT(HEIGHT)) u_preview (
        .clk(clk), .rst_n(rst_n),
        .in_valid(full_valid), .edge_in(full_edge), .in_x(full_x), .in_y(full_y),
        .in_sof(full_sof), .in_frame_end(full_eof), .in_frame_good(full_good),
        .out_valid(preview_valid), .out_pixel565(preview_pixel),
        .out_x(preview_x), .out_y(preview_y), .out_sof(preview_sof),
        .out_frame_end(preview_eof), .out_frame_good(preview_good),
        .coordinate_error(preview_coordinate_error)
    );

    task automatic record_error(input string message_text);
        begin
            $error("%s", message_text);
            errors = errors + 1;
        end
    endtask

    always @(posedge clk) begin
        integer expected_index;
        reg expected_edge;
        #1;
        if (window_valid)
            window_count = window_count + 1;
        if (sobel_valid) begin
            sobel_count = sobel_count + 1;
            expected_index = sobel_y * WIDTH + sobel_x;
            expected_edge = (edge_mem[expected_index] != 0);
            if (sobel_edge !== expected_edge) begin
                $error("interior mismatch at (%0d,%0d): actual=%0b expected=%0b magnitude=%0d gx=%0d gy=%0d",
                       sobel_x, sobel_y, sobel_edge, expected_edge,
                       sobel_magnitude, sobel_gx, sobel_gy);
                errors = errors + 1;
            end
        end
        if (full_valid) begin
            expected_index = full_y * WIDTH + full_x;
            expected_edge = (edge_mem[expected_index] != 0);
            if (full_count != expected_index) begin
                $error("full output order mismatch count=%0d coord=(%0d,%0d)",
                       full_count, full_x, full_y);
                errors = errors + 1;
            end
            if (full_edge !== expected_edge) begin
                $error("full edge mismatch at (%0d,%0d): actual=%0b expected=%0b",
                       full_x, full_y, full_edge, expected_edge);
                errors = errors + 1;
            end
            if (full_sof !== (full_count == 0))
                record_error("full SOF is not aligned to the first output pixel");
            if (full_eof !== (full_count == PIXELS-1))
                record_error("full EOF is not aligned to the final output pixel");
            full_count = full_count + 1;
        end
        if (preview_valid) begin
            expected_index = preview_y * (WIDTH/2) + preview_x;
            expected_edge = (preview_mem[expected_index] != 0);
            if (preview_count != expected_index) begin
                $error("preview output order mismatch count=%0d coord=(%0d,%0d)",
                       preview_count, preview_x, preview_y);
                errors = errors + 1;
            end
            if ((preview_pixel == 16'hFFFF) !== expected_edge) begin
                $error("preview mismatch at (%0d,%0d): actual=%h expected=%0b",
                       preview_x, preview_y, preview_pixel, expected_edge);
                errors = errors + 1;
            end
            if ((preview_pixel != 16'h0000) && (preview_pixel != 16'hFFFF))
                record_error("preview emitted a non-binary RGB565 value");
            if (preview_sof !== (preview_count == 0))
                record_error("preview SOF is not aligned to first preview pixel");
            if (preview_eof !== (preview_count == PREVIEW_PIXELS-1))
                record_error("preview EOF is not aligned to final preview pixel");
            if (preview_eof && !preview_good)
                record_error("preview completed frame was not marked good");
            preview_count = preview_count + 1;
        end
    end

    task automatic drive_one_frame;
        integer index;
        integer x;
        integer y;
        begin
            for (index = 0; index < PIXELS; index = index + 1) begin
                if ((gap_interval_runtime > 0) && (index > 0) &&
                    ((index % gap_interval_runtime) == 0)) begin
                    @(negedge clk);
                    in_valid = 1'b0;
                    in_sof = 1'b0;
                    in_frame_end = 1'b0;
                end
                x = index % WIDTH;
                y = index / WIDTH;
                @(negedge clk);
                gray_in = gray_mem[index];
                in_x = x[X_WIDTH-1:0];
                in_y = y[Y_WIDTH-1:0];
                in_valid = 1'b1;
                in_sof = (index == 0);
                in_frame_end = (index == PIXELS-1);
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_frame_end = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        window_count = 0;
        sobel_count = 0;
        full_count = 0;
        preview_count = 0;
        timeout_count = 0;
        gap_interval_runtime = GAP_INTERVAL;
        if (!$value$plusargs("GRAY=%s", gray_path))
            $fatal(1, "missing +GRAY=<path>");
        if (!$value$plusargs("EDGE=%s", edge_path))
            $fatal(1, "missing +EDGE=<path>");
        if (!$value$plusargs("PREVIEW=%s", preview_path))
            $fatal(1, "missing +PREVIEW=<path>");
        gap_arg_present = $value$plusargs("GAP=%d", gap_interval_runtime);
        $readmemh(gray_path, gray_mem);
        $readmemh(edge_path, edge_mem);
        $readmemh(preview_path, preview_mem);

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        drive_one_frame();

        wait (preview_eof);
        repeat (4) @(negedge clk);
        if (window_count != ((WIDTH-2) * (HEIGHT-2))) begin
            $error("window count=%0d expected=%0d", window_count, (WIDTH-2)*(HEIGHT-2));
            errors = errors + 1;
        end
        if (sobel_count != ((WIDTH-2) * (HEIGHT-2))) begin
            $error("Sobel count=%0d expected=%0d", sobel_count, (WIDTH-2)*(HEIGHT-2));
            errors = errors + 1;
        end
        if (full_count != PIXELS) begin
            $error("full count=%0d expected=%0d", full_count, PIXELS);
            errors = errors + 1;
        end
        if (preview_count != PREVIEW_PIXELS) begin
            $error("preview count=%0d expected=%0d", preview_count, PREVIEW_PIXELS);
            errors = errors + 1;
        end
        if (fifo_overflow || full_coordinate_error || frame_queue_overflow ||
            good_queue_overflow || preview_coordinate_error) begin
            $error("sticky error flags fifo=%0b full_coord=%0b frame_q=%0b good_q=%0b preview_coord=%0b",
                   fifo_overflow, full_coordinate_error, frame_queue_overflow,
                   good_queue_overflow, preview_coordinate_error);
            errors = errors + 1;
        end
        if (errors != 0)
            $fatal(1, "tb_sobel_frame failed with %0d errors", errors);
        $display("PASS tb_sobel_frame %0dx%0d gap=%0d full=%0d preview=%0d fifo_max=%0d",
                 WIDTH, HEIGHT, gap_interval_runtime, full_count, preview_count, fifo_max_level);
        $finish;
    end

    always @(posedge clk) begin
        timeout_count <= timeout_count + 1;
        if (timeout_count > (PIXELS * 20 + 10000))
            $fatal(1, "tb_sobel_frame timeout");
    end
endmodule
