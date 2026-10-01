`timescale 1ns/1ps

module tb_gray_window_3x3;
    localparam integer WIDTH = 7;
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
    logic out_valid;
    logic [7:0] p00, p01, p02;
    logic [7:0] p10, p11, p12;
    logic [7:0] p20, p21, p22;
    logic [X_WIDTH-1:0] center_x;
    logic [Y_WIDTH-1:0] center_y;

    integer expected_frame;
    integer observed_windows;
    integer errors;
    integer timeout_count;

    always #5 clk = ~clk;

    gray_window_3x3 #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .gray_in(gray_in), .in_valid(in_valid),
        .in_x(in_x), .in_y(in_y),
        .in_sof(in_sof), .in_frame_end(in_frame_end),
        .out_valid(out_valid),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .center_x(center_x), .center_y(center_y)
    );

    function automatic [7:0] pixel_value(
        input integer frame_id,
        input integer x,
        input integer y
    );
        pixel_value = frame_id * 64 + y * WIDTH + x;
    endfunction

    task automatic check_pixel(
        input [7:0] actual,
        input integer dx,
        input integer dy,
        input string label_text
    );
        reg [7:0] expected;
        begin
            expected = pixel_value(expected_frame, center_x + dx, center_y + dy);
            if (actual !== expected) begin
                $error("%s mismatch center=(%0d,%0d) actual=%0d expected=%0d frame=%0d",
                       label_text, center_x, center_y, actual, expected, expected_frame);
                errors = errors + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (out_valid) begin
            observed_windows = observed_windows + 1;
            if ((center_x < 1) || (center_x > WIDTH-2) ||
                (center_y < 1) || (center_y > HEIGHT-2)) begin
                $error("invalid center coordinate (%0d,%0d)", center_x, center_y);
                errors = errors + 1;
            end
            check_pixel(p00, -1, -1, "p00");
            check_pixel(p01,  0, -1, "p01");
            check_pixel(p02,  1, -1, "p02");
            check_pixel(p10, -1,  0, "p10");
            check_pixel(p11,  0,  0, "p11");
            check_pixel(p12,  1,  0, "p12");
            check_pixel(p20, -1,  1, "p20");
            check_pixel(p21,  0,  1, "p21");
            check_pixel(p22,  1,  1, "p22");
        end
    end

    task automatic drive_idle(input integer cycles);
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(negedge clk);
                in_valid = 1'b0;
                in_sof = 1'b0;
                in_frame_end = 1'b0;
            end
        end
    endtask

    task automatic drive_frame(
        input integer frame_id,
        input integer gap_interval
    );
        integer x;
        integer y;
        integer index;
        integer start_count;
        begin
            expected_frame = frame_id;
            start_count = observed_windows;
            index = 0;
            for (y = 0; y < HEIGHT; y = y + 1) begin
                for (x = 0; x < WIDTH; x = x + 1) begin
                    if ((gap_interval > 0) && (index > 0) && ((index % gap_interval) == 0))
                        drive_idle(1);
                    @(negedge clk);
                    in_valid = 1'b1;
                    in_x = x[X_WIDTH-1:0];
                    in_y = y[Y_WIDTH-1:0];
                    gray_in = pixel_value(frame_id, x, y);
                    in_sof = (index == 0);
                    in_frame_end = (index == (WIDTH * HEIGHT - 1));
                    index = index + 1;
                end
            end
            drive_idle(8);
            if ((observed_windows - start_count) != ((WIDTH-2) * (HEIGHT-2))) begin
                $error("frame %0d window count=%0d expected=%0d", frame_id,
                       observed_windows - start_count, (WIDTH-2) * (HEIGHT-2));
                errors = errors + 1;
            end
        end
    endtask

    task automatic drive_partial_then_reset;
        integer index;
        integer x;
        integer y;
        begin
            expected_frame = 3;
            for (index = 0; index < 17; index = index + 1) begin
                x = index % WIDTH;
                y = index / WIDTH;
                @(negedge clk);
                in_valid = 1'b1;
                in_x = x[X_WIDTH-1:0];
                in_y = y[Y_WIDTH-1:0];
                gray_in = pixel_value(3, x, y);
                in_sof = (index == 0);
                in_frame_end = 1'b0;
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            rst_n = 1'b0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
            drive_idle(2);
        end
    endtask

    initial begin
        errors = 0;
        observed_windows = 0;
        expected_frame = 0;
        timeout_count = 0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        drive_idle(2);

        drive_frame(0, 0);
        drive_frame(1, 3);
        drive_partial_then_reset();
        observed_windows = 0;
        drive_frame(2, 2);

        if (errors != 0)
            $fatal(1, "tb_gray_window_3x3 failed with %0d errors", errors);
        $display("PASS tb_gray_window_3x3: numbered windows, gaps, frame restart, and reset recovery");
        $finish;
    end

    always @(posedge clk) begin
        timeout_count <= timeout_count + 1;
        if (timeout_count > 5000)
            $fatal(1, "tb_gray_window_3x3 timeout");
    end
endmodule
