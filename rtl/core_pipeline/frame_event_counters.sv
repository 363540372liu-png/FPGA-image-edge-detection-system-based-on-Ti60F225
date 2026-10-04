`timescale 1ns/1ps

// Count frame-level events in the camera PCLK domain and publish a coherent
// held snapshot. The snapshot toggle changes only after the counters have had
// at least one source-clock cycle to settle.
module frame_event_counters (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         input_sof,
    input  logic         capture_frame_end,
    input  logic         capture_frame_good,
    input  logic         algorithm_frame_end,
    input  logic         algorithm_frame_good,
    input  logic [31:0]  committed_frame_count,
    input  logic [31:0]  busy_drop_count,
    output logic [31:0]  input_sof_count,
    output logic [31:0]  capture_good_count,
    output logic [31:0]  capture_bad_count,
    output logic [31:0]  algorithm_good_count,
    output logic [191:0] snapshot_data,
    output logic         snapshot_toggle
);
    logic [31:0] committed_count_d;
    logic [31:0] busy_drop_count_d;
    logic snapshot_pending;

    wire local_event = input_sof || capture_frame_end || algorithm_frame_end;
    wire external_event = (committed_frame_count != committed_count_d) ||
                          (busy_drop_count != busy_drop_count_d);
    wire any_event = local_event || external_event;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_sof_count <= 32'd0;
            capture_good_count <= 32'd0;
            capture_bad_count <= 32'd0;
            algorithm_good_count <= 32'd0;
            committed_count_d <= 32'd0;
            busy_drop_count_d <= 32'd0;
            snapshot_data <= 192'd0;
            snapshot_toggle <= 1'b0;
            snapshot_pending <= 1'b0;
        end else begin
            committed_count_d <= committed_frame_count;
            busy_drop_count_d <= busy_drop_count;

            if (input_sof)
                input_sof_count <= input_sof_count + 1'b1;

            if (capture_frame_end) begin
                if (capture_frame_good)
                    capture_good_count <= capture_good_count + 1'b1;
                else
                    capture_bad_count <= capture_bad_count + 1'b1;
            end

            if (algorithm_frame_end && algorithm_frame_good)
                algorithm_good_count <= algorithm_good_count + 1'b1;

            if (snapshot_pending) begin
                snapshot_data <= {
                    input_sof_count,
                    capture_good_count,
                    capture_bad_count,
                    algorithm_good_count,
                    committed_frame_count,
                    busy_drop_count
                };
                snapshot_toggle <= ~snapshot_toggle;
                // Preserve a request that arrived while this snapshot was
                // being published; it will be captured on the next cycle.
                snapshot_pending <= any_event;
            end else if (any_event) begin
                snapshot_pending <= 1'b1;
            end
        end
    end
endmodule
