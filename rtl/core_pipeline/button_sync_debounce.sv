`timescale 1ns/1ps
// Two active-low board keys.  The synchronizer is followed by a vector
// debounce so a chord is treated as one gesture and releases never retrigger.
module button_sync_debounce #(
    parameter int CLK_HZ = 96_000_000,
    parameter int DEBOUNCE_MS = 20,
    parameter int DEFAULT_HOLD_MS = 1000
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [1:0] key_n,
    output logic       inc_press,
    output logic       dec_press,
    output logic       default_press,
    output logic [1:0] debounced_key_n
);
    localparam int DEBOUNCE_CYCLES = (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam int HOLD_CYCLES = (CLK_HZ / 1000) * DEFAULT_HOLD_MS;
    localparam int DB_W = (DEBOUNCE_CYCLES < 2) ? 1 : $clog2(DEBOUNCE_CYCLES + 1);
    localparam int HOLD_W = (HOLD_CYCLES < 2) ? 1 : $clog2(HOLD_CYCLES + 1);
    localparam logic [DB_W-1:0] DEBOUNCE_LIMIT = DEBOUNCE_CYCLES;
    localparam logic [HOLD_W-1:0] HOLD_LIMIT = HOLD_CYCLES;

    (* async_reg = "true" *) logic [1:0] key_meta, key_sync;
    logic [1:0] candidate_n;
    logic [DB_W-1:0] debounce_count;
    logic [HOLD_W-1:0] both_hold_count;
    logic both_reported;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 2'b11;
            key_sync <= 2'b11;
            candidate_n <= 2'b11;
            debounced_key_n <= 2'b11;
            debounce_count <= '0;
            both_hold_count <= '0;
            both_reported <= 1'b0;
            inc_press <= 1'b0;
            dec_press <= 1'b0;
            default_press <= 1'b0;
        end else begin
            key_meta <= key_n;
            key_sync <= key_meta;
            inc_press <= 1'b0;
            dec_press <= 1'b0;
            default_press <= 1'b0;

            if (key_sync != candidate_n) begin
                candidate_n <= key_sync;
                debounce_count <= '0;
            end else if (debounce_count < DEBOUNCE_LIMIT) begin
                debounce_count <= debounce_count + 1'b1;
            end else if (debounced_key_n != candidate_n) begin
                // key_data[0] (N2) is the decrease key; key_data[1] (M2)
                // is the increase key.  A simultaneous press is a chord.
                if (candidate_n == 2'b01)
                    inc_press <= 1'b1;
                else if (candidate_n == 2'b10)
                    dec_press <= 1'b1;
                debounced_key_n <= candidate_n;
            end

            if (debounced_key_n == 2'b00) begin
                if (both_hold_count < HOLD_LIMIT)
                    both_hold_count <= both_hold_count + 1'b1;
                if ((both_hold_count >= HOLD_CYCLES-1) && !both_reported) begin
                    default_press <= 1'b1;
                    both_reported <= 1'b1;
                end
            end else begin
                both_hold_count <= '0;
                both_reported <= 1'b0;
            end
        end
    end
endmodule
