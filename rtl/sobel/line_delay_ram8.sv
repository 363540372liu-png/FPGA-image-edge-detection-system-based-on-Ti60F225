`timescale 1ns/1ps

// Accepted-pixel delay implemented with one native Ti60 RAM10 block.
// Separate circular read/write pointers avoid read/write access to the same
// address. RAM contents are never cleared; downstream row/column validity
// prevents stale data from becoming a valid window.
module line_delay_ram8 #(
    parameter integer DELAY_PIXELS = 640
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       restart,
    input  logic       enable,
    input  logic [7:0] data_in,
    output logic [7:0] data_out
);
    localparam integer RAM_DEPTH = 1024;
    localparam logic [9:0] WRITE_START = DELAY_PIXELS;

    logic [9:0] read_addr;
    logic [9:0] write_addr;
    wire [9:0] effective_read_addr  = restart ? 10'd0 : read_addr;
    wire [9:0] effective_write_addr = restart ? WRITE_START : write_addr;

    initial begin
        if ((DELAY_PIXELS <= 0) || (DELAY_PIXELS >= RAM_DEPTH))
            $error("line_delay_ram8 DELAY_PIXELS must be 1..1023");
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_addr <= 10'd0;
            write_addr <= WRITE_START;
        end else if (enable) begin
            read_addr <= effective_read_addr + 1'b1;
            write_addr <= effective_write_addr + 1'b1;
        end
    end

    EFX_RAM10 #(
        .READ_WIDTH(8),
        .WRITE_WIDTH(8),
        .OUTPUT_REG(1'b0),
        .WRITE_MODE("READ_FIRST"),
        .RESET_RAM("NONE"),
        .RESET_OUTREG("NONE")
    ) u_ram (
        .WCLK(clk), .WCLKE(1'b1), .WADDREN(1'b1),
        .WE({2{enable}}), .WDATA(data_in), .WADDR(effective_write_addr),
        .RCLK(clk), .RE(enable), .RST(1'b0), .RADDREN(1'b1),
        .RDATA(data_out), .RADDR(effective_read_addr)
    );
endmodule
