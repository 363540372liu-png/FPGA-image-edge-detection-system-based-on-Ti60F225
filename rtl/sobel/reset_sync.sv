`timescale 1ns/1ps
module reset_sync (
    input  logic clk,
    input  logic arst_n,
    output logic srst_n
);
    (* async_reg = "true" *) logic [2:0] sync_ff;

    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            sync_ff <= 3'b000;
        else
            sync_ff <= {sync_ff[1:0], 1'b1};
    end

    assign srst_n = sync_ff[2];
endmodule
