`timescale 1ns/1ps

// The grayscale 2x2 mean is available about one source row before the Sobel
// 2x2 OR result.  A one-RAM10 FIFO preserves the full 8-bit grayscale samples
// until the matching row-major edge sample arrives. Coordinates are carried by
// the later edge stream; both streams are independently checked for continuity.
module preview_pair_aligner (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        gray_valid,
    input  logic [7:0]  gray_value,
    input  logic [11:0] gray_x,
    input  logic [11:0] gray_y,
    input  logic        gray_sof,
    input  logic        gray_frame_end,
    input  logic [10:0] gray_frame_threshold,
    input  logic        edge_valid,
    input  logic        edge_value,
    input  logic [11:0] edge_x,
    input  logic [11:0] edge_y,
    input  logic        edge_sof,
    input  logic        edge_frame_end,
    input  logic        edge_frame_good,
    output logic        out_valid,
    output logic [7:0]  out_gray,
    output logic        out_edge,
    output logic [11:0] out_x,
    output logic [11:0] out_y,
    output logic        out_sof,
    output logic        out_frame_end,
    output logic        out_frame_good,
    output logic [10:0] out_frame_threshold,
    output logic        alignment_error,
    output logic [10:0] fifo_max_level
);
    logic [9:0] wr_ptr, rd_ptr;
    logic [10:0] fifo_level;
    logic [7:0] fifo_rdata;
    logic read_pending;
    logic edge_d, sof_d, end_d, good_d;
    logic [10:0] pending_frame_threshold, threshold_d;
    logic [11:0] x_d, y_d;
    logic [8:0] gray_expected_x, edge_expected_x;
    logic [7:0] gray_expected_y, edge_expected_y;
    logic gray_frame_active, edge_frame_active;
    wire do_read = edge_valid && (fifo_level != 0);
    wire do_write = gray_valid;

    EFX_RAM10 #(
        .READ_WIDTH(8), .WRITE_WIDTH(8), .OUTPUT_REG(1'b0),
        .WRITE_MODE("READ_FIRST"), .RESET_RAM("NONE"),
        .RESET_OUTREG("NONE")
    ) u_gray_fifo (
        .WCLK(clk), .WCLKE(1'b1), .WADDREN(1'b1),
        .WE({2{do_write}}), .WDATA(gray_value), .WADDR(wr_ptr),
        .RCLK(clk), .RE(do_read), .RST(1'b0), .RADDREN(1'b1),
        .RDATA(fifo_rdata), .RADDR(rd_ptr)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 10'd0;
            rd_ptr <= 10'd0;
            fifo_level <= 11'd0;
            fifo_max_level <= 11'd0;
            read_pending <= 1'b0;
            out_valid <= 1'b0;
            out_gray <= 8'd0;
            out_edge <= 1'b0;
            out_x <= 12'd0;
            out_y <= 12'd0;
            out_sof <= 1'b0;
            out_frame_end <= 1'b0;
            out_frame_good <= 1'b0;
            out_frame_threshold <= 11'd128;
            alignment_error <= 1'b0;
            gray_expected_x <= 9'd0;
            gray_expected_y <= 8'd0;
            edge_expected_x <= 9'd0;
            edge_expected_y <= 8'd0;
            gray_frame_active <= 1'b0;
            edge_frame_active <= 1'b0;
            edge_d <= 1'b0;
            sof_d <= 1'b0;
            end_d <= 1'b0;
            good_d <= 1'b0;
            pending_frame_threshold <= 11'd128;
            threshold_d <= 11'd128;
            x_d <= 12'd0;
            y_d <= 12'd0;
        end else begin
            out_valid <= read_pending;
            out_sof <= read_pending && sof_d;
            out_frame_end <= read_pending && end_d;
            out_frame_good <= read_pending && end_d && good_d;
            if (read_pending) begin
                out_gray <= fifo_rdata;
                out_edge <= edge_d;
                out_x <= x_d;
                out_y <= y_d;
                if (sof_d)
                    out_frame_threshold <= threshold_d;
            end
            read_pending <= do_read;

            if (do_write)
                wr_ptr <= wr_ptr + 1'b1;
            if (do_read) begin
                rd_ptr <= rd_ptr + 1'b1;
                edge_d <= edge_value;
                x_d <= edge_x;
                y_d <= edge_y;
                sof_d <= edge_sof;
                end_d <= edge_frame_end;
                good_d <= edge_frame_good;
                if (edge_sof)
                    threshold_d <= pending_frame_threshold;
            end

            case ({do_write, do_read})
                2'b10: begin
                    fifo_level <= fifo_level + 1'b1;
                    if ((fifo_level + 1'b1) > fifo_max_level)
                        fifo_max_level <= fifo_level + 1'b1;
                    if (fifo_level == 11'd1024)
                        alignment_error <= 1'b1;
                end
                2'b01: fifo_level <= fifo_level - 1'b1;
                default: ;
            endcase
            if (edge_valid && !do_read)
                alignment_error <= 1'b1;

            if (gray_valid) begin
                if (gray_sof) begin
                    pending_frame_threshold <= gray_frame_threshold;
                    gray_frame_active <= 1'b1;
                    gray_expected_x <= 9'd1;
                    gray_expected_y <= 8'd0;
                    if ((gray_x != 0) || (gray_y != 0))
                        alignment_error <= 1'b1;
                end else if (gray_frame_active) begin
                    if ((gray_x != gray_expected_x) ||
                        (gray_y != gray_expected_y))
                        alignment_error <= 1'b1;
                    if (gray_expected_x == 319) begin
                        gray_expected_x <= 0;
                        gray_expected_y <= gray_expected_y + 1'b1;
                    end else begin
                        gray_expected_x <= gray_expected_x + 1'b1;
                    end
                end
                if (gray_frame_end)
                    gray_frame_active <= 1'b0;
            end

            if (edge_valid) begin
                if (edge_sof) begin
                    edge_frame_active <= 1'b1;
                    edge_expected_x <= 9'd1;
                    edge_expected_y <= 8'd0;
                    if ((edge_x != 0) || (edge_y != 0))
                        alignment_error <= 1'b1;
                end else if (edge_frame_active) begin
                    if ((edge_x != edge_expected_x) ||
                        (edge_y != edge_expected_y))
                        alignment_error <= 1'b1;
                    if (edge_expected_x == 319) begin
                        edge_expected_x <= 0;
                        edge_expected_y <= edge_expected_y + 1'b1;
                    end else begin
                        edge_expected_x <= edge_expected_x + 1'b1;
                    end
                end
                if (edge_frame_end)
                    edge_frame_active <= 1'b0;
            end
        end
    end
endmodule
