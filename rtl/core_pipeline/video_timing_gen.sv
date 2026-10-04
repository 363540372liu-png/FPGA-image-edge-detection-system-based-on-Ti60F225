`timescale 1ns/1ps

module video_timing_gen #(
    parameter int H_ACTIVE = 480,
    parameter int H_FP     = 100,
    parameter int H_SYNC   = 16,
    parameter int H_BP     = 100,
    parameter int V_ACTIVE = 640,
    parameter int V_FP     = 100,
    parameter int V_SYNC   = 20,
    parameter int V_BP     = 100,
    parameter bit HS_ACTIVE_LEVEL = 1'b0,
    parameter bit VS_ACTIVE_LEVEL = 1'b0
)(
    input  logic        clk_pixel,
    input  logic        rst_n,
    output logic [11:0] x,
    output logic [11:0] y,
    output logic        de,
    output logic        hsync,
    output logic        vsync,
    output logic        frame_tick
);
    localparam int H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam int V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    logic [11:0] h_count;
    logic [11:0] v_count;
    logic        hsync_window;
    logic        vsync_window;

    always_ff @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= '0;
            v_count <= '0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= '0;
            if (v_count == V_TOTAL - 1)
                v_count <= '0;
            else
                v_count <= v_count + 1'b1;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end

    always @* begin
        x = h_count;
        y = v_count;
        de = rst_n && (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
        hsync_window = (h_count >= H_ACTIVE + H_FP) &&
                       (h_count <  H_ACTIVE + H_FP + H_SYNC);
        vsync_window = (v_count >= V_ACTIVE + V_FP) &&
                       (v_count <  V_ACTIVE + V_FP + V_SYNC);
        hsync = hsync_window ? HS_ACTIVE_LEVEL : ~HS_ACTIVE_LEVEL;
        vsync = vsync_window ? VS_ACTIVE_LEVEL : ~VS_ACTIVE_LEVEL;
        frame_tick = rst_n && (h_count == H_TOTAL - 1) &&
                                (v_count == V_TOTAL - 1);
    end
endmodule
