`timescale 1ns/1ps

// Reconstruct a complete row-major frame around the valid-only Sobel interior.
// Border pixels are emitted as zero. A bounded FIFO absorbs the timing offset
// between the input raster and the interior-result stream.
module edge_full_frame_stream #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter integer X_WIDTH = (WIDTH <= 2) ? 1 : $clog2(WIDTH),
    parameter integer Y_WIDTH = (HEIGHT <= 2) ? 1 : $clog2(HEIGHT),
    // The output scheduler stalls at an unavailable interior coordinate, so
    // the result stream cannot run a complete line ahead. Continuous-frame,
    // valid-gap, and full-size simulations observe a maximum occupancy of one;
    // 16 entries retain explicit implementation margin without inferring a
    // 25,920-bit asynchronous-read logic memory.
    parameter integer FIFO_DEPTH = 16,
    parameter integer FIFO_ADDR_WIDTH = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH),
    parameter integer FIFO_COUNT_WIDTH = $clog2(FIFO_DEPTH+1),
    parameter integer FRAME_QUEUE_DEPTH = 4,
    parameter integer FRAME_QUEUE_WIDTH = $clog2(FRAME_QUEUE_DEPTH+1)
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 input_sof,
    input  logic                 input_frame_end,
    input  logic                 input_frame_good,
    input  logic                 interior_valid,
    input  logic                 interior_edge,
    input  logic [X_WIDTH-1:0]   interior_x,
    input  logic [Y_WIDTH-1:0]   interior_y,
    output logic                 out_valid,
    output logic                 out_edge,
    output logic [X_WIDTH-1:0]   out_x,
    output logic [Y_WIDTH-1:0]   out_y,
    output logic                 out_sof,
    output logic                 out_frame_end,
    output logic                 out_frame_good,
    output logic                 fifo_overflow,
    output logic                 coordinate_error,
    output logic                 frame_queue_overflow,
    output logic                 good_queue_overflow,
    output logic [FIFO_COUNT_WIDTH-1:0] fifo_level_dbg,
    output logic [FIFO_COUNT_WIDTH-1:0] fifo_max_level_dbg
);
    localparam integer ENTRY_WIDTH = 1 + X_WIDTH + Y_WIDTH;

    logic [ENTRY_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [FIFO_ADDR_WIDTH-1:0] fifo_write_ptr, fifo_read_ptr;
    logic [FIFO_COUNT_WIDTH-1:0] fifo_count;
    wire [ENTRY_WIDTH-1:0] fifo_head = fifo_mem[fifo_read_ptr];
    wire fifo_head_edge = fifo_head[ENTRY_WIDTH-1];
    wire [X_WIDTH-1:0] fifo_head_x = fifo_head[Y_WIDTH +: X_WIDTH];
    wire [Y_WIDTH-1:0] fifo_head_y = fifo_head[Y_WIDTH-1:0];

    logic frame_active;
    logic [X_WIDTH-1:0] emit_x;
    logic [Y_WIDTH-1:0] emit_y;
    logic [FRAME_QUEUE_WIDTH-1:0] pending_frames;
    logic [FRAME_QUEUE_WIDTH-1:0] completed_good_frames;

    wire input_sof_event = input_sof;
    wire input_good_event = input_frame_end && input_frame_good;
    wire input_bad_event = input_frame_end && !input_frame_good;
    wire token_available = (pending_frames != 0) || input_sof_event;
    wire good_available = (completed_good_frames != 0) || input_good_event;
    wire border_position = (emit_x == 0) || (emit_x == WIDTH-1) ||
                           (emit_y == 0) || (emit_y == HEIGHT-1);
    wire eof_position = frame_active && border_position &&
                        (emit_x == WIDTH-1) && (emit_y == HEIGHT-1);
    wire emit_eof = eof_position && good_available;
    wire start_frame = !frame_active && token_available;
    wire chain_frame = emit_eof && token_available;
    wire consume_frame_token = start_frame || chain_frame;
    wire push_fifo = interior_valid && (frame_active || (pending_frames != 0));
    wire pop_fifo = frame_active && !border_position && (fifo_count != 0);
    wire push_accepted = push_fifo && ((fifo_count < FIFO_DEPTH) || pop_fifo);

    function automatic logic [FIFO_ADDR_WIDTH-1:0] increment_fifo_ptr(
        input logic [FIFO_ADDR_WIDTH-1:0] pointer
    );
        if (pointer == FIFO_DEPTH-1)
            increment_fifo_ptr = '0;
        else
            increment_fifo_ptr = pointer + 1'b1;
    endfunction

    assign fifo_level_dbg = fifo_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_write_ptr <= '0;
            fifo_read_ptr <= '0;
            fifo_count <= '0;
            fifo_max_level_dbg <= '0;
            pending_frames <= '0;
            completed_good_frames <= '0;
            frame_active <= 1'b0;
            emit_x <= '0;
            emit_y <= '0;
            out_valid <= 1'b0;
            out_edge <= 1'b0;
            out_x <= '0;
            out_y <= '0;
            out_sof <= 1'b0;
            out_frame_end <= 1'b0;
            out_frame_good <= 1'b0;
            fifo_overflow <= 1'b0;
            coordinate_error <= 1'b0;
            frame_queue_overflow <= 1'b0;
            good_queue_overflow <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            out_sof <= 1'b0;
            out_frame_end <= 1'b0;
            out_frame_good <= 1'b0;

            if (input_bad_event) begin
                // Reject the partial/bad frame. The next SOF restarts both the
                // window memories and this row-major output scheduler.
                fifo_write_ptr <= '0;
                fifo_read_ptr <= '0;
                fifo_count <= '0;
                pending_frames <= '0;
                completed_good_frames <= '0;
                frame_active <= 1'b0;
                emit_x <= '0;
                emit_y <= '0;
            end else begin
                if (push_fifo && !push_accepted)
                    fifo_overflow <= 1'b1;
                if (push_accepted) begin
                    fifo_mem[fifo_write_ptr] <=
                        {interior_edge, interior_x, interior_y};
                    fifo_write_ptr <= increment_fifo_ptr(fifo_write_ptr);
                end
                if (pop_fifo)
                    fifo_read_ptr <= increment_fifo_ptr(fifo_read_ptr);

                case ({push_accepted, pop_fifo})
                    2'b10: begin
                        fifo_count <= fifo_count + 1'b1;
                        if ((fifo_count + 1'b1) > fifo_max_level_dbg)
                            fifo_max_level_dbg <= fifo_count + 1'b1;
                    end
                    2'b01: fifo_count <= fifo_count - 1'b1;
                    default: fifo_count <= fifo_count;
                endcase

                case ({input_sof_event, consume_frame_token})
                    2'b10: begin
                        if (pending_frames < FRAME_QUEUE_DEPTH)
                            pending_frames <= pending_frames + 1'b1;
                        else
                            frame_queue_overflow <= 1'b1;
                    end
                    2'b01: pending_frames <= pending_frames - 1'b1;
                    default: pending_frames <= pending_frames;
                endcase

                case ({input_good_event, emit_eof})
                    2'b10: begin
                        if (completed_good_frames < FRAME_QUEUE_DEPTH)
                            completed_good_frames <= completed_good_frames + 1'b1;
                        else
                            good_queue_overflow <= 1'b1;
                    end
                    2'b01: completed_good_frames <= completed_good_frames - 1'b1;
                    default: completed_good_frames <= completed_good_frames;
                endcase

                if (start_frame) begin
                    frame_active <= 1'b1;
                    emit_x <= '0;
                    emit_y <= '0;
                end else if (frame_active) begin
                    if (border_position) begin
                        // The final border pixel waits until the corresponding
                        // input frame has been declared complete and good.
                        if (!eof_position || good_available) begin
                            out_valid <= 1'b1;
                            out_edge <= 1'b0;
                            out_x <= emit_x;
                            out_y <= emit_y;
                            out_sof <= (emit_x == 0) && (emit_y == 0);
                            out_frame_end <= eof_position;
                            out_frame_good <= emit_eof;
                            if (eof_position) begin
                                if (chain_frame) begin
                                    frame_active <= 1'b1;
                                    emit_x <= '0;
                                    emit_y <= '0;
                                end else begin
                                    frame_active <= 1'b0;
                                end
                            end else if (emit_x == WIDTH-1) begin
                                emit_x <= '0;
                                emit_y <= emit_y + 1'b1;
                            end else begin
                                emit_x <= emit_x + 1'b1;
                            end
                        end
                    end else if (fifo_count != 0) begin
                        out_valid <= 1'b1;
                        out_edge <= fifo_head_edge;
                        out_x <= emit_x;
                        out_y <= emit_y;
                        if ((fifo_head_x != emit_x) || (fifo_head_y != emit_y))
                            coordinate_error <= 1'b1;
                        if (emit_x == WIDTH-1) begin
                            emit_x <= '0;
                            emit_y <= emit_y + 1'b1;
                        end else begin
                            emit_x <= emit_x + 1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
