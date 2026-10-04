`timescale 1ns/1ps
module tb_threshold_bus_cdc;
    logic src_clk=0, dst_clk=0, rst_n=0;
    logic [10:0] src_data=11'd128, dst_data;
    logic src_toggle=0, dst_update;
    always #5 src_clk=~src_clk;
    always #7 dst_clk=~dst_clk;
    threshold_bus_cdc #(.WIDTH(11)) dut (
        .dst_clk(dst_clk), .dst_rst_n(rst_n), .src_data(src_data),
        .src_toggle(src_toggle), .dst_data(dst_data), .dst_update(dst_update)
    );
    initial begin
        repeat (3) @(posedge dst_clk); rst_n=1;
        repeat (3) @(posedge dst_clk);
        src_data=11'd2040; src_toggle=~src_toggle;
        wait(dst_update); if (dst_data!==11'd2040) $fatal(1,"CDC coherent sample failed");
        @(negedge dst_update);
        @(posedge src_clk); src_data=11'd0; src_toggle=~src_toggle;
        wait(dst_update); if (dst_data!==11'd0) $fatal(1,"CDC second sample failed");
        $display("THRESHOLD_CDC_PASS bundled_data_toggle"); $finish;
    end
endmodule
