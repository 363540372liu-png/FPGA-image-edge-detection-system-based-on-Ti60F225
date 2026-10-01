`timescale 1ns/1ps
module sccb_master #(
    parameter int unsigned CLK_HZ  = 24_000_000,
    parameter int unsigned SCL_HZ  = 100_000,
    parameter logic [6:0]  DEV_ADDR = 7'h3c
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        read_not_write,
    input  logic [15:0] reg_addr,
    input  logic [7:0]  write_data,
    output logic [7:0]  read_data,
    output logic        busy,
    output logic        done,
    output logic        ack_error,
    output logic        scl,
    input  logic        sda_i,
    output logic        sda_o,
    output logic        sda_oe
);
    localparam int unsigned TICK_DIV = CLK_HZ / (SCL_HZ * 4);
    localparam int unsigned DIV_W = (TICK_DIV < 2) ? 1 : $clog2(TICK_DIV);

    typedef enum logic [4:0] {
        ST_IDLE, ST_START_A, ST_START_B, ST_START_C,
        ST_SEND_SETUP, ST_SEND_HIGH, ST_SEND_LOW,
        ST_ACK_SETUP, ST_ACK_HIGH, ST_ACK_LOW,
        ST_RESTART_A, ST_RESTART_B, ST_RESTART_C, ST_RESTART_D,
        ST_READ_SETUP, ST_READ_HIGH, ST_READ_LOW,
        ST_NACK_SETUP, ST_NACK_HIGH, ST_NACK_LOW,
        ST_STOP_A, ST_STOP_B, ST_STOP_C
    } state_t;

    state_t state;
    logic [DIV_W-1:0] div_count;
    logic tick;
    logic [7:0] tx_byte;
    logic [2:0] bit_index;
    logic [2:0] byte_step;
    logic       command_read;
    logic [15:0] command_addr;
    logic [7:0] command_data;

    assign sda_o = 1'b0; // SDA is open-drain: drive low or release.

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_count <= '0;
            tick      <= 1'b0;
        end else if (busy) begin
            if (div_count == TICK_DIV - 1) begin
                div_count <= '0;
                tick      <= 1'b1;
            end else begin
                div_count <= div_count + 1'b1;
                tick      <= 1'b0;
            end
        end else begin
            div_count <= '0;
            tick      <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            ack_error     <= 1'b0;
            scl           <= 1'b1;
            sda_oe        <= 1'b0;
            tx_byte       <= 8'h00;
            read_data     <= 8'h00;
            bit_index     <= 3'd7;
            byte_step     <= 3'd0;
            command_read  <= 1'b0;
            command_addr  <= 16'h0000;
            command_data  <= 8'h00;
        end else begin
            done <= 1'b0;

            if (state == ST_IDLE) begin
                scl    <= 1'b1;
                sda_oe <= 1'b0;
                if (start) begin
                    busy         <= 1'b1;
                    ack_error    <= 1'b0;
                    command_read <= read_not_write;
                    command_addr <= reg_addr;
                    command_data <= write_data;
                    byte_step    <= 3'd0;
                    tx_byte      <= {DEV_ADDR, 1'b0};
                    bit_index    <= 3'd7;
                    state        <= ST_START_A;
                end
            end else if (tick) begin
                case (state)
                    ST_START_A: begin scl <= 1'b1; sda_oe <= 1'b0; state <= ST_START_B; end
                    ST_START_B: begin scl <= 1'b1; sda_oe <= 1'b1; state <= ST_START_C; end
                    ST_START_C: begin scl <= 1'b0; sda_oe <= 1'b1; state <= ST_SEND_SETUP; end

                    ST_SEND_SETUP: begin
                        scl    <= 1'b0;
                        sda_oe <= ~tx_byte[bit_index];
                        state  <= ST_SEND_HIGH;
                    end
                    ST_SEND_HIGH: begin scl <= 1'b1; state <= ST_SEND_LOW; end
                    ST_SEND_LOW: begin
                        scl <= 1'b0;
                        if (bit_index == 0)
                            state <= ST_ACK_SETUP;
                        else begin
                            bit_index <= bit_index - 1'b1;
                            state <= ST_SEND_SETUP;
                        end
                    end
                    ST_ACK_SETUP: begin scl <= 1'b0; sda_oe <= 1'b0; state <= ST_ACK_HIGH; end
                    ST_ACK_HIGH: begin
                        scl       <= 1'b1;
                        ack_error <= ack_error | sda_i;
                        state     <= ST_ACK_LOW;
                    end
                    ST_ACK_LOW: begin
                        scl <= 1'b0;
                        bit_index <= 3'd7;
                        case (byte_step)
                            3'd0: begin byte_step <= 3'd1; tx_byte <= command_addr[15:8]; state <= ST_SEND_SETUP; end
                            3'd1: begin byte_step <= 3'd2; tx_byte <= command_addr[7:0];  state <= ST_SEND_SETUP; end
                            3'd2: begin
                                if (command_read)
                                    state <= ST_RESTART_A;
                                else begin byte_step <= 3'd3; tx_byte <= command_data; state <= ST_SEND_SETUP; end
                            end
                            3'd3: state <= ST_STOP_A;
                            3'd4: begin read_data <= 8'h00; state <= ST_READ_SETUP; end
                            default: state <= ST_STOP_A;
                        endcase
                    end

                    ST_RESTART_A: begin scl <= 1'b0; sda_oe <= 1'b0; state <= ST_RESTART_B; end
                    ST_RESTART_B: begin scl <= 1'b1; sda_oe <= 1'b0; state <= ST_RESTART_C; end
                    ST_RESTART_C: begin scl <= 1'b1; sda_oe <= 1'b1; state <= ST_RESTART_D; end
                    ST_RESTART_D: begin
                        scl       <= 1'b0;
                        sda_oe    <= 1'b1;
                        byte_step <= 3'd4;
                        tx_byte   <= {DEV_ADDR, 1'b1};
                        bit_index <= 3'd7;
                        state     <= ST_SEND_SETUP;
                    end

                    ST_READ_SETUP: begin scl <= 1'b0; sda_oe <= 1'b0; state <= ST_READ_HIGH; end
                    ST_READ_HIGH: begin
                        scl <= 1'b1;
                        read_data[bit_index] <= sda_i;
                        state <= ST_READ_LOW;
                    end
                    ST_READ_LOW: begin
                        scl <= 1'b0;
                        if (bit_index == 0)
                            state <= ST_NACK_SETUP;
                        else begin
                            bit_index <= bit_index - 1'b1;
                            state <= ST_READ_SETUP;
                        end
                    end
                    ST_NACK_SETUP: begin scl <= 1'b0; sda_oe <= 1'b0; state <= ST_NACK_HIGH; end
                    ST_NACK_HIGH:  begin scl <= 1'b1; state <= ST_NACK_LOW; end
                    ST_NACK_LOW:   begin scl <= 1'b0; state <= ST_STOP_A; end

                    ST_STOP_A: begin scl <= 1'b0; sda_oe <= 1'b1; state <= ST_STOP_B; end
                    ST_STOP_B: begin scl <= 1'b1; sda_oe <= 1'b1; state <= ST_STOP_C; end
                    ST_STOP_C: begin
                        scl    <= 1'b1;
                        sda_oe <= 1'b0;
                        busy   <= 1'b0;
                        done   <= 1'b1;
                        state  <= ST_IDLE;
                    end
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
