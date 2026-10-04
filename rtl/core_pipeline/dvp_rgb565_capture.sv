`timescale 1ns/1ps
module dvp_rgb565_capture #(
    parameter int unsigned ACTIVE_WIDTH  = 640,
    parameter int unsigned ACTIVE_HEIGHT = 480
) (
    input  logic        pclk,
    input  logic        rst_n,
    input  logic        vsync,
    input  logic        href,
    input  logic [7:0]  data,
    output logic [15:0] pixel,
    output logic        pixel_valid,
    output logic        start_of_frame,
    output logic        end_of_line,
    output logic        line_end,
    output logic        frame_end,
    output logic [11:0] x,
    output logic [11:0] y,
    output logic        odd_byte_error
);
    logic       href_d;
    logic       vsync_d;
    logic       byte_phase;
    logic [7:0] first_byte;
    logic       frame_pending;
    logic       frame_active;
    logic       sync_armed;
    logic [11:0] x_count;
    logic [11:0] y_count;

    wire href_fall  = href_d && !href;
    wire vsync_rise = !vsync_d && vsync;
    wire vsync_fall = vsync_d && !vsync;

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            href_d         <= 1'b0;
            vsync_d        <= 1'b0;
            byte_phase     <= 1'b0;
            first_byte     <= 8'h00;
            frame_pending  <= 1'b0;
            frame_active   <= 1'b0;
            sync_armed     <= 1'b0;
            pixel          <= 16'h0000;
            pixel_valid    <= 1'b0;
            start_of_frame <= 1'b0;
            end_of_line    <= 1'b0;
            line_end       <= 1'b0;
            frame_end      <= 1'b0;
            x              <= 12'd0;
            y              <= 12'd0;
            x_count        <= 12'd0;
            y_count        <= 12'd0;
            odd_byte_error <= 1'b0;
        end else begin
            href_d         <= href;
            vsync_d        <= vsync;
            pixel_valid    <= 1'b0;
            start_of_frame <= 1'b0;
            end_of_line    <= 1'b0;
            line_end       <= 1'b0;
            frame_end      <= 1'b0;

            // The merchant table programs 0x4740=0x21. Its official Ti60
            // demo treats VSYNC high as frame-valid and HREF high as line-valid.
            // Arm only after observing an inactive interval so reset release
            // in the middle of a frame cannot turn a residual frame into SOF.
            if (!vsync)
                sync_armed <= 1'b1;

            if (vsync_rise) begin
                byte_phase    <= 1'b0;
                frame_pending <= sync_armed;
                frame_active  <= sync_armed;
                if (sync_armed) begin
                    sync_armed <= 1'b0;
                    odd_byte_error <= 1'b0;
                end
                x_count       <= 12'd0;
                y_count       <= 12'd0;
            end

            if (vsync_fall) begin
                if (frame_active)
                    frame_end <= 1'b1;
                frame_pending <= 1'b0;
                frame_active  <= 1'b0;
                sync_armed    <= 1'b1;
                byte_phase    <= 1'b0;
                x_count       <= 12'd0;
                y_count       <= 12'd0;
            end

            if (href_fall && frame_active) begin
                line_end <= 1'b1;
                if (byte_phase)
                    odd_byte_error <= 1'b1;
                byte_phase <= 1'b0;
                x_count <= 12'd0;
                if (y_count < ACTIVE_HEIGHT)
                    y_count <= y_count + 1'b1;
            end

            if (href && frame_active) begin
                if (!byte_phase) begin
                    first_byte <= data;
                    byte_phase <= 1'b1;
                end else begin
                    // Official register 0x4300=0x61 emits RGB565 MS byte then LS byte.
                    pixel          <= {first_byte, data};
                    pixel_valid    <= 1'b1;
                    start_of_frame <= frame_pending;
                    end_of_line    <= (x_count == ACTIVE_WIDTH - 1);
                    frame_pending  <= 1'b0;
                    byte_phase     <= 1'b0;
                    x              <= x_count;
                    y              <= y_count;
                    x_count        <= x_count + 1'b1;
                end
            end
        end
    end
endmodule
