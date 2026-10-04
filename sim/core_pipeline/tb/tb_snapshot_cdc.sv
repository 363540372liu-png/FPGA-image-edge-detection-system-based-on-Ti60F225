`timescale 1ns/1ps
module tb_snapshot_cdc;
    logic src_clk = 0, dst_clk = 0;
    logic dst_rst_n = 0;
    logic src_toggle = 0;
    logic [31:0] src_data = 0;
    logic [31:0] dst_data;
    logic dst_valid, dst_update;

    always #3.5 src_clk = ~src_clk;
    always #5.5 dst_clk = ~dst_clk;

    snapshot_cdc #(.WIDTH(32)) dut (.*);

    task automatic publish(input logic [31:0] value);
        begin
            @(posedge src_clk);
            src_data <= value;
            src_toggle <= ~src_toggle;
        end
    endtask

    task automatic expect_update(input logic [31:0] value);
        integer timeout;
        begin
            timeout = 0;
            while (!dst_update && timeout < 12) begin
                @(posedge dst_clk); #1;
                timeout = timeout + 1;
            end
            if (!dst_update)
                $fatal(1, "snapshot update timeout");
            if (!dst_valid || dst_data !== value)
                $fatal(1, "snapshot=%h expected=%h", dst_data, value);
        end
    endtask

    initial begin
        repeat (3) @(posedge dst_clk);
        dst_rst_n = 1;
        publish(32'h0123_4567);
        expect_update(32'h0123_4567);
        repeat (4) @(posedge dst_clk);
        if (dst_update)
            $fatal(1, "dst_update was not a one-cycle pulse");
        publish(32'h89ab_cdef);
        expect_update(32'h89ab_cdef);
        $display("PASS: coherent held-data toggle snapshot CDC");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "timeout");
    end
endmodule
