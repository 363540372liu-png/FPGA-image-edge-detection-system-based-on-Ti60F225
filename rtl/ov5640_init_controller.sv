`timescale 1ns/1ps
module ov5640_init_controller #(
    parameter int unsigned CLK_HZ = 24_000_000,
    parameter int unsigned RESET_DELAY_MS = 5,
    parameter int unsigned INIT_COUNT = 252
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    output logic        txn_start,
    output logic        txn_read,
    output logic [15:0] txn_reg_addr,
    output logic [7:0]  txn_write_data,
    input  logic        txn_done,
    input  logic        txn_ack_error,
    input  logic [7:0]  txn_read_data,
    output logic [15:0] chip_id,
    output logic        chip_id_ok,
    output logic        init_done,
    output logic        init_failed,
    output logic [7:0]  failed_index,
    output logic [3:0]  fail_code,
    output logic [7:0]  lut_index,
    input  logic [23:0] lut_data
);
    localparam int unsigned DELAY_CYCLES = (CLK_HZ / 1000) * RESET_DELAY_MS;
    localparam int unsigned DELAY_W = (DELAY_CYCLES < 2) ? 1 : $clog2(DELAY_CYCLES + 1);

    typedef enum logic [3:0] {
        ST_WAIT_ENABLE, ST_ID_H_START, ST_ID_H_WAIT,
        ST_ID_L_START, ST_ID_L_WAIT, ST_CHECK_ID,
        ST_WRITE_START, ST_WRITE_WAIT, ST_RESET_DELAY,
        ST_DONE, ST_FAILED
    } state_t;

    state_t state;
    logic [DELAY_W-1:0] delay_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_WAIT_ENABLE;
            txn_start      <= 1'b0;
            txn_read       <= 1'b0;
            txn_reg_addr   <= 16'h0000;
            txn_write_data <= 8'h00;
            chip_id        <= 16'h0000;
            chip_id_ok     <= 1'b0;
            init_done      <= 1'b0;
            init_failed    <= 1'b0;
            failed_index   <= 8'hff;
            fail_code      <= 4'h0;
            lut_index      <= 8'd0;
            delay_count    <= '0;
        end else begin
            txn_start <= 1'b0;
            case (state)
                ST_WAIT_ENABLE: if (enable) state <= ST_ID_H_START;

                ST_ID_H_START: begin
                    txn_read     <= 1'b1;
                    txn_reg_addr <= 16'h300a;
                    txn_start    <= 1'b1;
                    state        <= ST_ID_H_WAIT;
                end
                ST_ID_H_WAIT: if (txn_done) begin
                    if (txn_ack_error) begin fail_code <= 4'h1; state <= ST_FAILED; end
                    else begin chip_id[15:8] <= txn_read_data; state <= ST_ID_L_START; end
                end
                ST_ID_L_START: begin
                    txn_read     <= 1'b1;
                    txn_reg_addr <= 16'h300b;
                    txn_start    <= 1'b1;
                    state        <= ST_ID_L_WAIT;
                end
                ST_ID_L_WAIT: if (txn_done) begin
                    if (txn_ack_error) begin fail_code <= 4'h2; state <= ST_FAILED; end
                    else begin chip_id[7:0] <= txn_read_data; state <= ST_CHECK_ID; end
                end
                ST_CHECK_ID: begin
                    if (chip_id == 16'h5640) begin
                        chip_id_ok <= 1'b1;
                        lut_index  <= 8'd0;
                        state      <= ST_WRITE_START;
                    end else begin
                        fail_code <= 4'h3;
                        state <= ST_FAILED;
                    end
                end
                ST_WRITE_START: begin
                    txn_read       <= 1'b0;
                    txn_reg_addr   <= lut_data[23:8];
                    txn_write_data <= lut_data[7:0];
                    txn_start      <= 1'b1;
                    state          <= ST_WRITE_WAIT;
                end
                ST_WRITE_WAIT: if (txn_done) begin
                    if (txn_ack_error) begin
                        failed_index <= lut_index;
                        fail_code    <= 4'h4;
                        state        <= ST_FAILED;
                    end else if (lut_index == INIT_COUNT - 1) begin
                        state <= ST_DONE;
                    end else if ((lut_data[23:8] == 16'h3008) && (lut_data[7:0] == 8'h82)) begin
                        delay_count <= '0;
                        state <= ST_RESET_DELAY;
                    end else begin
                        lut_index <= lut_index + 1'b1;
                        state <= ST_WRITE_START;
                    end
                end
                ST_RESET_DELAY: begin
                    if (delay_count == DELAY_CYCLES - 1) begin
                        lut_index <= lut_index + 1'b1;
                        state <= ST_WRITE_START;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end
                ST_DONE: begin init_done <= 1'b1; end
                ST_FAILED: begin init_failed <= 1'b1; end
                default: state <= ST_FAILED;
            endcase
        end
    end
endmodule
