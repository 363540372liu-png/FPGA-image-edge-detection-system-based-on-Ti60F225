`timescale 1ns/1ps
// Requested threshold lives in clk_sys.  The toggle changes only after the
// stable data bus changes, forming a bundled-data CDC transaction.
module threshold_control (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        inc_press,
    input  logic        dec_press,
    input  logic        default_press,
    output logic [10:0] requested_threshold,
    output logic        request_toggle
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            requested_threshold <= 11'd128;
            request_toggle <= 1'b0;
        end else if (default_press) begin
            if (requested_threshold != 11'd128) begin
                requested_threshold <= 11'd128;
                request_toggle <= ~request_toggle;
            end
        end else if (inc_press) begin
            if (requested_threshold < 11'd2024) begin
                requested_threshold <= requested_threshold + 11'd16;
                request_toggle <= ~request_toggle;
            end else if (requested_threshold != 11'd2040) begin
                requested_threshold <= 11'd2040;
                request_toggle <= ~request_toggle;
            end
        end else if (dec_press) begin
            if (requested_threshold > 11'd16) begin
                requested_threshold <= requested_threshold - 11'd16;
                request_toggle <= ~request_toggle;
            end else if (requested_threshold != 11'd0) begin
                requested_threshold <= 11'd0;
                request_toggle <= ~request_toggle;
            end
        end
    end
endmodule

module threshold_bus_cdc #(
    parameter int WIDTH = 11
) (
    input  logic             dst_clk,
    input  logic             dst_rst_n,
    input  logic [WIDTH-1:0] src_data,
    input  logic             src_toggle,
    output logic [WIDTH-1:0] dst_data,
    output logic             dst_update
);
    (* async_reg = "true" *) logic [WIDTH-1:0] data_meta, data_sync;
    (* async_reg = "true" *) logic [2:0] toggle_sync;

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            data_meta <= '0;
            data_sync <= '0;
            toggle_sync <= 3'b000;
            dst_data <= 11'd128;
            dst_update <= 1'b0;
        end else begin
            data_meta <= src_data;
            data_sync <= data_meta;
            toggle_sync <= {toggle_sync[1:0], src_toggle};
            dst_update <= 1'b0;
            if (toggle_sync[2] != toggle_sync[1]) begin
                dst_data <= data_sync;
                dst_update <= 1'b1;
            end
        end
    end
endmodule
