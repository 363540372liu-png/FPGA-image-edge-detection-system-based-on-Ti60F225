`timescale 1ns/1ps

module reset_release_sync (
    input  logic clk,
    input  logic async_ready,
    output logic reset_n
);
    (* async_reg = "true" *) logic [2:0] sync_pipe = '0;

    always_ff @(posedge clk or negedge async_ready) begin
        if (!async_ready)
            sync_pipe <= '0;
        else
            sync_pipe <= {sync_pipe[1:0], 1'b1};
    end

    assign reset_n = sync_pipe[2];
endmodule
