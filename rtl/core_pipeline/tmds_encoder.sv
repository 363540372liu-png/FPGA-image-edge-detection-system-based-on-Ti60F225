`timescale 1ns/1ps

module tmds_encoder (
    input  logic       clk_pixel,
    input  logic       rst_n,
    input  logic [7:0] data,
    input  logic       de,
    input  logic [1:0] control,
    output logic [9:0] symbol
);
    logic [8:0] q_m;
    logic [9:0] next_symbol;
    logic signed [5:0] disparity;
    logic signed [5:0] next_disparity;
    logic [3:0] ones_data;
    logic [3:0] ones_qm;
    logic signed [5:0] balance;
    logic use_xnor;

    always @* begin
        ones_data = {3'd0, data[0]} + {3'd0, data[1]} +
                    {3'd0, data[2]} + {3'd0, data[3]} +
                    {3'd0, data[4]} + {3'd0, data[5]} +
                    {3'd0, data[6]} + {3'd0, data[7]};

        use_xnor = (ones_data > 4) || ((ones_data == 4) && !data[0]);
        q_m[0] = data[0];
        q_m[1] = use_xnor ? ~(q_m[0] ^ data[1]) : (q_m[0] ^ data[1]);
        q_m[2] = use_xnor ? ~(q_m[1] ^ data[2]) : (q_m[1] ^ data[2]);
        q_m[3] = use_xnor ? ~(q_m[2] ^ data[3]) : (q_m[2] ^ data[3]);
        q_m[4] = use_xnor ? ~(q_m[3] ^ data[4]) : (q_m[3] ^ data[4]);
        q_m[5] = use_xnor ? ~(q_m[4] ^ data[5]) : (q_m[4] ^ data[5]);
        q_m[6] = use_xnor ? ~(q_m[5] ^ data[6]) : (q_m[5] ^ data[6]);
        q_m[7] = use_xnor ? ~(q_m[6] ^ data[7]) : (q_m[6] ^ data[7]);
        q_m[8] = !use_xnor;

        ones_qm = {3'd0, q_m[0]} + {3'd0, q_m[1]} +
                  {3'd0, q_m[2]} + {3'd0, q_m[3]} +
                  {3'd0, q_m[4]} + {3'd0, q_m[5]} +
                  {3'd0, q_m[6]} + {3'd0, q_m[7]};
        balance = $signed({1'b0, ones_qm, 1'b0}) - 6'sd8;

        next_symbol = 10'b1101010100;
        next_disparity = disparity;
        if (!de) begin
            case (control)
                2'b00: next_symbol = 10'b1101010100;
                2'b01: next_symbol = 10'b0010101011;
                2'b10: next_symbol = 10'b0101010100;
                default: next_symbol = 10'b1010101011;
            endcase
            next_disparity = '0;
        end else if ((disparity == 0) || (balance == 0)) begin
            next_symbol = {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
            next_disparity = disparity + (q_m[8] ? balance : -balance);
        end else if (((disparity > 0) && (balance > 0)) ||
                     ((disparity < 0) && (balance < 0))) begin
            next_symbol = {1'b1, q_m[8], ~q_m[7:0]};
            next_disparity = disparity - balance + (q_m[8] ? 6'sd2 : 6'sd0);
        end else begin
            next_symbol = {1'b0, q_m[8], q_m[7:0]};
            next_disparity = disparity + balance - (q_m[8] ? 6'sd0 : 6'sd2);
        end
    end

    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            symbol    <= 10'b1101010100;
            disparity <= '0;
        end else begin
            symbol    <= next_symbol;
            disparity <= next_disparity;
        end
    end
endmodule
