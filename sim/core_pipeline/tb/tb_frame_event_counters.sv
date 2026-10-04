`timescale 1ns/1ps
module tb_frame_event_counters;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic input_sof, capture_frame_end, capture_frame_good;
    logic algorithm_frame_end, algorithm_frame_good;
    logic [31:0] committed_frame_count, busy_drop_count;
    logic [31:0] input_sof_count, capture_good_count;
    logic [31:0] capture_bad_count, algorithm_good_count;
    logic [191:0] snapshot_data;
    logic snapshot_toggle;

    always #5 clk = ~clk;

    frame_event_counters dut (.*);

    task automatic pulse_events(
        input logic sof,
        input logic cap_end,
        input logic cap_good,
        input logic alg_end,
        input logic alg_good
    );
        @(negedge clk);
        input_sof = sof;
        capture_frame_end = cap_end;
        capture_frame_good = cap_good;
        algorithm_frame_end = alg_end;
        algorithm_frame_good = alg_good;
        @(negedge clk);
        input_sof = 1'b0;
        capture_frame_end = 1'b0;
        capture_frame_good = 1'b0;
        algorithm_frame_end = 1'b0;
        algorithm_frame_good = 1'b0;
    endtask

    initial begin
        input_sof = 0;
        capture_frame_end = 0;
        capture_frame_good = 0;
        algorithm_frame_end = 0;
        algorithm_frame_good = 0;
        committed_frame_count = 0;
        busy_drop_count = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        pulse_events(1, 0, 0, 0, 0);
        pulse_events(0, 1, 1, 1, 1);
        committed_frame_count = 1;
        repeat (4) @(posedge clk);

        pulse_events(1, 0, 0, 0, 0);
        pulse_events(0, 1, 0, 1, 0);
        busy_drop_count = 1;
        repeat (5) @(posedge clk);

        if (input_sof_count != 2 || capture_good_count != 1 ||
            capture_bad_count != 1 || algorithm_good_count != 1)
            $fatal(1, "counter mismatch: sof=%0d good=%0d bad=%0d alg=%0d",
                   input_sof_count, capture_good_count,
                   capture_bad_count, algorithm_good_count);

        if (snapshot_data !== {32'd2, 32'd1, 32'd1, 32'd1, 32'd1, 32'd1})
            $fatal(1, "snapshot mismatch: %h", snapshot_data);

        $display("PASS: frame event counters and coherent snapshot");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "timeout");
    end
endmodule
