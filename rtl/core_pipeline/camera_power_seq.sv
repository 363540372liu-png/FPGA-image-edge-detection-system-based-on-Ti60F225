`timescale 1ns/1ps
module camera_power_seq #(
    parameter int unsigned CLK_HZ = 24_000_000,
    parameter int unsigned PWDN_HOLD_MS = 6,
    parameter int unsigned POST_PWDN_MS = 25
) (
    input  logic clk,
    input  logic rst_n,
    output logic camera_pwdn,
    output logic init_enable
);
    localparam int unsigned PWDN_CYCLES = (CLK_HZ / 1000) * PWDN_HOLD_MS;
    localparam int unsigned WAIT_CYCLES = (CLK_HZ / 1000) * POST_PWDN_MS;
    localparam int unsigned TOTAL_CYCLES = PWDN_CYCLES + WAIT_CYCLES;
    localparam int unsigned COUNT_W = (TOTAL_CYCLES < 2) ? 1 : $clog2(TOTAL_CYCLES + 1);

    logic [COUNT_W-1:0] count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count       <= '0;
            camera_pwdn <= 1'b1;
            init_enable <= 1'b0;
        end else begin
            if (count < TOTAL_CYCLES[COUNT_W-1:0])
                count <= count + 1'b1;

            if (count >= PWDN_CYCLES[COUNT_W-1:0])
                camera_pwdn <= 1'b0;

            if (count >= TOTAL_CYCLES[COUNT_W-1:0] - 1'b1)
                init_enable <= 1'b1;
        end
    end
endmodule
