`timescale 1ns/1ps
module tb_threshold_control;
    logic clk = 0, rst_n = 0;
    logic [1:0] key_n = 2'b11;
    logic inc_press, dec_press, default_press;
    logic direct_inc=0, direct_dec=0, direct_default=0;
    logic [1:0] debounced;
    logic [10:0] requested;
    logic toggle;
    always #5 clk = ~clk;

    button_sync_debounce #(.CLK_HZ(1000), .DEBOUNCE_MS(2), .DEFAULT_HOLD_MS(10)) u_keys (
        .clk(clk), .rst_n(rst_n), .key_n(key_n),
        .inc_press(inc_press), .dec_press(dec_press),
        .default_press(default_press), .debounced_key_n(debounced)
    );
    threshold_control u_control (
        .clk(clk), .rst_n(rst_n), .inc_press(inc_press | direct_inc),
        .dec_press(dec_press | direct_dec), .default_press(default_press | direct_default), .requested_threshold(requested),
        .request_toggle(toggle)
    );

    task automatic wait_cycles(input integer n);
        repeat (n) @(posedge clk);
    endtask
    task automatic key_press(input logic [1:0] value);
        key_n = value; wait_cycles(5); key_n = 2'b11; wait_cycles(4);
    endtask

    initial begin
        wait_cycles(3); rst_n = 1'b1;
        wait_cycles(3);
        if (requested !== 11'd128) $fatal(1, "default reset threshold wrong: %0d", requested);
        // key[1] increases and key[0] decreases; a short press is one event.
        key_press(2'b01);
        if (requested !== 11'd144) $fatal(1, "increase failed: %0d", requested);
        key_press(2'b10);
        if (requested !== 11'd128) $fatal(1, "decrease failed: %0d", requested);
        // Contact bounce must not create a second event.
        key_n = 2'b01; wait_cycles(1); key_n = 2'b11; wait_cycles(1);
        key_n = 2'b01; wait_cycles(5); key_n = 2'b11; wait_cycles(4);
        if (requested !== 11'd144) $fatal(1, "bounce handling failed: %0d", requested);
        // Both keys held past the qualified hold period restore 128 once.
        key_n = 2'b00; wait_cycles(16); key_n = 2'b11; wait_cycles(4);
        if (requested !== 11'd128) $fatal(1, "chord default failed: %0d", requested);
        // Saturation checks are applied directly to the one-shot controller.
        repeat (130) begin direct_inc = 1'b1; @(posedge clk); direct_inc = 1'b0; @(posedge clk); end
        if (requested !== 11'd2040) $fatal(1, "upper saturation failed: %0d", requested);
        repeat (130) begin direct_dec = 1'b1; @(posedge clk); direct_dec = 1'b0; @(posedge clk); end
        if (requested !== 11'd0) $fatal(1, "lower saturation failed: %0d", requested);
        $display("THRESHOLD_CONTROL_PASS default=128 step=16 range=0..2040");
        $finish;
    end
endmodule
