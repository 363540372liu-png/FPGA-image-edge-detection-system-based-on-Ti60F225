`timescale 1ns/1ps
// Transfers a multi-bit snapshot that is held stable between source toggles.
module snapshot_cdc #(
    parameter int WIDTH = 8
) (
    input  logic             dst_clk,
    input  logic             dst_rst_n,
    input  logic             src_toggle,
    input  logic [WIDTH-1:0] src_data,
    output logic [WIDTH-1:0] dst_data,
    output logic             dst_valid,
    output logic             dst_update
);
    (* async_reg = "true" *) logic [1:0] toggle_sync;
    (* async_reg = "true" *) logic [WIDTH-1:0] data_sync_1;
    (* async_reg = "true" *) logic [WIDTH-1:0] data_sync_2;
    logic toggle_seen;

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            toggle_sync <= 2'b00;
            data_sync_1 <= '0;
            data_sync_2 <= '0;
            toggle_seen <= 1'b0;
            dst_data <= '0;
            dst_valid <= 1'b0;
            dst_update <= 1'b0;
        end else begin
            toggle_sync <= {toggle_sync[0], src_toggle};
            data_sync_1 <= src_data;
            data_sync_2 <= data_sync_1;
            dst_update <= 1'b0;
            if (toggle_sync[1] != toggle_seen) begin
                dst_data <= data_sync_2;
                dst_valid <= 1'b1;
                dst_update <= 1'b1;
                toggle_seen <= toggle_sync[1];
            end
        end
    end
endmodule
