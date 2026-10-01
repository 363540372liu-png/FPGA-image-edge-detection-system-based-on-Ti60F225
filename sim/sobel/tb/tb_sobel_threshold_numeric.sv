`timescale 1ns/1ps

module tb_sobel_threshold_numeric;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic flush = 1'b0;
    logic in_valid = 1'b0;
    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    logic [3:0] in_x;
    logic [3:0] in_y;
    logic out_valid, edge_out;
    logic signed [10:0] gx_out, gy_out;
    logic [10:0] magnitude_out;
    logic [3:0] out_x, out_y;
    integer output_index;
    integer errors;
    integer timeout_count;

    always #5 clk = ~clk;

    sobel_threshold #(.X_WIDTH(4), .Y_WIDTH(4)) dut (
        .clk(clk), .rst_n(rst_n), .flush(flush), .in_valid(in_valid),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .in_x(in_x), .in_y(in_y), .threshold_in(11'd128),
        .out_valid(out_valid), .edge_out(edge_out),
        .gx_out(gx_out), .gy_out(gy_out), .magnitude_out(magnitude_out),
        .out_x(out_x), .out_y(out_y)
    );

    task automatic drive_columns(input [7:0] left_value, input [7:0] right_value,
                                 input [3:0] tag);
        begin
            @(negedge clk);
            p00 = left_value; p10 = left_value; p20 = left_value;
            p01 = 0; p11 = 0; p21 = 0;
            p02 = right_value; p12 = right_value; p22 = right_value;
            in_x = tag;
            in_y = 4'd5;
            in_valid = 1'b1;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (out_valid) begin
            case (output_index)
                0: begin
                    if ((gx_out !== 128) || (gy_out !== 0) ||
                        (magnitude_out !== 128) || (edge_out !== 1'b0)) begin
                        $error("strict threshold case failed gx=%0d gy=%0d mag=%0d edge=%0b",
                               gx_out, gy_out, magnitude_out, edge_out);
                        errors = errors + 1;
                    end
                end
                1: begin
                    if ((gx_out !== 132) || (gy_out !== 0) ||
                        (magnitude_out !== 132) || (edge_out !== 1'b1)) begin
                        $error("positive case failed gx=%0d gy=%0d mag=%0d edge=%0b",
                               gx_out, gy_out, magnitude_out, edge_out);
                        errors = errors + 1;
                    end
                end
                2: begin
                    if ((gx_out !== -132) || (gy_out !== 0) ||
                        (magnitude_out !== 132) || (edge_out !== 1'b1)) begin
                        $error("negative absolute case failed gx=%0d gy=%0d mag=%0d edge=%0b",
                               gx_out, gy_out, magnitude_out, edge_out);
                        errors = errors + 1;
                    end
                end
                default: begin
                    $error("unexpected extra output");
                    errors = errors + 1;
                end
            endcase
            if ((out_x !== output_index[3:0]) || (out_y !== 5)) begin
                $error("coordinate latency mismatch output_index=%0d coord=(%0d,%0d)",
                       output_index, out_x, out_y);
                errors = errors + 1;
            end
            output_index = output_index + 1;
        end
    end

    initial begin
        errors = 0;
        output_index = 0;
        timeout_count = 0;
        p00 = 0; p01 = 0; p02 = 0; p10 = 0; p11 = 0;
        p12 = 0; p20 = 0; p21 = 0; p22 = 0; in_x = 0; in_y = 0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        drive_columns(0, 32, 0);
        drive_columns(0, 33, 1);
        drive_columns(33, 0, 2);
        @(negedge clk);
        in_valid = 1'b0;
        repeat (5) @(negedge clk);
        if (output_index != 3) begin
            $error("output count=%0d expected=3", output_index);
            errors = errors + 1;
        end
        if (errors != 0)
            $fatal(1, "tb_sobel_threshold_numeric failed with %0d errors", errors);
        $display("PASS tb_sobel_threshold_numeric: strict >128 and signed absolute value");
        $finish;
    end

    always @(posedge clk) begin
        timeout_count <= timeout_count + 1;
        if (timeout_count > 1000)
            $fatal(1, "tb_sobel_threshold_numeric timeout");
    end
endmodule
