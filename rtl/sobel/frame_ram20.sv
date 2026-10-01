`timescale 1ns/1ps
// 20-bit-wide simple dual-port RAM built explicitly from Ti60 EFX_RAM10 blocks.
// One primitive stores 512 x 20 bits. DEPTH=15360 therefore uses 30 blocks.
module frame_ram20 #(
    parameter int DEPTH = 15360,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic                  wr_clk,
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [19:0]           wr_data,
    input  logic                  rd_clk,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [19:0]           rd_data
);
    localparam int BLOCKS = (DEPTH + 511) / 512;
    localparam int BLOCK_SEL_WIDTH = $clog2(BLOCKS);

    generate
        // Small-depth instance is used only by the reduced simulation fixture.
        if (DEPTH <= 512) begin : g_small_model
            logic [19:0] memory [0:DEPTH-1];
            always_ff @(posedge wr_clk)
                if (wr_en) memory[wr_addr] <= wr_data;
            always_ff @(posedge rd_clk)
                if (rd_en) rd_data <= memory[rd_addr];
        end else begin : g_native_blocks
            logic [BLOCK_SEL_WIDTH-1:0] rd_block_d;
            wire  [19:0] block_rdata [0:BLOCKS-1];
            wire  [BLOCK_SEL_WIDTH-1:0] wr_block = wr_addr[ADDR_WIDTH-1:9];
            wire  [BLOCK_SEL_WIDTH-1:0] rd_block = rd_addr[ADDR_WIDTH-1:9];

            always_ff @(posedge rd_clk)
                if (rd_en) rd_block_d <= rd_block;

            always_comb begin
                if (rd_block_d < BLOCKS)
                    rd_data = block_rdata[rd_block_d];
                else
                    rd_data = 20'h0;
            end

            for (genvar g = 0; g < BLOCKS; g = g + 1) begin : g_ram
                localparam int BLOCK_INDEX = g;
                EFX_RAM10 #(
                    .READ_WIDTH(20),
                    .WRITE_WIDTH(20),
                    .OUTPUT_REG(1'b0),
                    // The two ports are asynchronous. Concurrent access to the
                    // same physical buffer is prevented by the frame handshake,
                    // so collision data is intentionally unspecified.
                    .WRITE_MODE("READ_UNKNOWN"),
                    .RESET_RAM("NONE"),
                    .RESET_OUTREG("NONE")
                ) u_ram (
                    .WCLK(wr_clk),
                    .WCLKE(1'b1),
                    .WADDREN(1'b1),
                    .WE({2{wr_en && (wr_block == BLOCK_INDEX)}}),
                    .WDATA(wr_data),
                    .WADDR(wr_addr[8:0]),
                    .RCLK(rd_clk),
                    .RE(rd_en && (rd_block == BLOCK_INDEX)),
                    .RST(1'b0),
                    .RADDREN(1'b1),
                    .RDATA(block_rdata[g]),
                    .RADDR(rd_addr[8:0])
                );
            end
        end
    endgenerate
endmodule
