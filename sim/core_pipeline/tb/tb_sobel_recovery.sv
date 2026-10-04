`timescale 1ns/1ps

module tb_sobel_recovery;
    localparam integer WIDTH = 8;
    localparam integer HEIGHT = 6;
    localparam integer X_WIDTH = $clog2(WIDTH);
    localparam integer Y_WIDTH = $clog2(HEIGHT);

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [7:0] gray_in = 8'd0;
    logic in_valid = 1'b0;
    logic [X_WIDTH-1:0] in_x = '0;
    logic [Y_WIDTH-1:0] in_y = '0;
    logic in_sof = 1'b0;
    logic in_frame_end = 1'b0;
    logic in_frame_good = 1'b0;

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
    logic fifo_overflow, coordinate_error, frame_queue_overflow, good_queue_overflow;
    logic [4:0] fifo_level, fifo_max_level;

    integer errors;
    integer completed_frames;
    integer current_pixel_count;
    integer timeout_count;
    logic recovery_check_enable;

    always #5 clk = ~clk;

    gray_window_3x3 #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_window (
        .clk(clk), .rst_n(rst_n), .gray_in(gray_in), .in_valid(in_valid),
        .in_x(in_x), .in_y(in_y), .in_sof(in_sof), .in_frame_end(in_frame_end),
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
        .gx_out(sobel_gx), .gy_out(sobel_gy), .magnitude_out(sobel_magnitude),
        .out_x(sobel_x), .out_y(sobel_y)
    );

    edge_full_frame_stream #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_full (
        .clk(clk), .rst_n(rst_n), .input_sof(in_valid && in_sof),
        .input_frame_end(in_frame_end), .input_frame_good(in_frame_good),
        .interior_valid(sobel_valid), .interior_edge(sobel_edge),
        .interior_x(sobel_x), .interior_y(sobel_y),
        .out_valid(full_valid), .out_edge(full_edge), .out_x(full_x), .out_y(full_y),
        .out_sof(full_sof), .out_frame_end(full_eof), .out_frame_good(full_good),
        .fifo_overflow(fifo_overflow), .coordinate_error(coordinate_error),
        .frame_queue_overflow(frame_queue_overflow),
        .good_queue_overflow(good_queue_overflow),
        .fifo_level_dbg(fifo_level), .fifo_max_level_dbg(fifo_max_level)
    );

    function automatic [7:0] source_pixel(input integer kind, input integer x);
        if (kind == 0)
            source_pixel = 8'd73;
        else
            source_pixel = (x >= 4) ? 8'd255 : 8'd0;
    endfunction

    function automatic logic expected_edge(
        input integer kind,
        input integer x,
        input integer y
    );
        if (kind == 0)
            expected_edge = 1'b0;
        else
            expected_edge = ((x == 3) || (x == 4)) && (y >= 1) && (y <= HEIGHT-2);
    endfunction

    always @(posedge clk) begin
        integer expected_kind;
        #1;
        if (full_valid && recovery_check_enable) begin
            if (full_sof)
                current_pixel_count = 0;
            expected_kind = completed_frames;
            if ((full_x != (current_pixel_count % WIDTH)) ||
                (full_y != (current_pixel_count / WIDTH))) begin
                $error("recovery order mismatch frame=%0d count=%0d coord=(%0d,%0d)",
                       completed_frames, current_pixel_count, full_x, full_y);
                errors = errors + 1;
            end
            if (full_edge !== expected_edge(expected_kind, full_x, full_y)) begin
                $error("recovery data mismatch frame=%0d coord=(%0d,%0d) actual=%0b",
                       completed_frames, full_x, full_y, full_edge);
                errors = errors + 1;
            end
            current_pixel_count = current_pixel_count + 1;
            if (full_eof) begin
                if (!full_good) begin
                    $error("completed recovery frame not marked good");
                    errors = errors + 1;
                end
                if (current_pixel_count != WIDTH*HEIGHT) begin
                    $error("recovery frame size=%0d expected=%0d", current_pixel_count, WIDTH*HEIGHT);
                    errors = errors + 1;
                end
                completed_frames = completed_frames + 1;
            end
        end
    end

    task automatic idle(input integer cycles);
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(negedge clk);
                in_valid = 1'b0;
                in_sof = 1'b0;
                in_frame_end = 1'b0;
                in_frame_good = 1'b0;
            end
        end
    endtask

    task automatic send_partial_bad;
        integer index;
        begin
            for (index = 0; index < 19; index = index + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_x = index % WIDTH;
                in_y = index / WIDTH;
                gray_in = source_pixel(1, index % WIDTH);
                in_sof = (index == 0);
                in_frame_end = 1'b0;
                in_frame_good = 1'b0;
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_frame_end = 1'b1;
            in_frame_good = 1'b0;
            idle(8);
        end
    endtask

    task automatic send_good_frame(input integer kind, input integer gap_interval);
        integer index;
        integer x;
        integer y;
        begin
            for (index = 0; index < WIDTH*HEIGHT; index = index + 1) begin
                if ((gap_interval > 0) && (index > 0) && ((index % gap_interval) == 0))
                    idle(1);
                x = index % WIDTH;
                y = index / WIDTH;
                @(negedge clk);
                in_valid = 1'b1;
                in_x = x;
                in_y = y;
                gray_in = source_pixel(kind, x);
                in_sof = (index == 0);
                in_frame_end = (index == WIDTH*HEIGHT-1);
                in_frame_good = (index == WIDTH*HEIGHT-1);
            end
            idle(8);
        end
    endtask

    initial begin
        errors = 0;
        completed_frames = 0;
        current_pixel_count = 0;
        timeout_count = 0;
        recovery_check_enable = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        idle(2);

        send_partial_bad();
        recovery_check_enable = 1'b1;
        send_good_frame(0, 3);
        send_good_frame(1, 5);
        wait (completed_frames == 2);
        idle(5);

        if (fifo_overflow || coordinate_error || frame_queue_overflow || good_queue_overflow) begin
            $error("recovery sticky errors fifo=%0b coord=%0b frame_q=%0b good_q=%0b",
                   fifo_overflow, coordinate_error, frame_queue_overflow, good_queue_overflow);
            errors = errors + 1;
        end
        if (errors != 0)
            $fatal(1, "tb_sobel_recovery failed with %0d errors", errors);
        $display("PASS tb_sobel_recovery: partial frame rejected; two following frames completed");
        $finish;
    end

    always @(posedge clk) begin
        timeout_count <= timeout_count + 1;
        if (timeout_count > 10000)
            $fatal(1, "tb_sobel_recovery timeout");
    end
endmodule
