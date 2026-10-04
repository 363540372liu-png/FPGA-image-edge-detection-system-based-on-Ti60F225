`timescale 1ns/1ps
module tb_frame_counter_overlay;
    logic de;
    logic [11:0] hdmi_x, hdmi_y;
    logic counters_valid;
    logic [31:0] input_sof_count, capture_good_count, capture_bad_count;
    logic [31:0] algorithm_good_count, committed_frame_count;
    logic [31:0] busy_drop_count, displayed_frame_count;
    logic [7:0] base_red, base_green, base_blue;
    logic [7:0] red, green, blue;

    frame_counter_overlay dut (.*);

    task automatic check_rgb(
        input [7:0] er, input [7:0] eg, input [7:0] eb,
        input [255:0] label
    );
        #1;
        if ({red, green, blue} !== {er, eg, eb})
            $fatal(1, "%0s: got %02x%02x%02x expected %02x%02x%02x",
                   label, red, green, blue, er, eg, eb);
    endtask

    initial begin
        de = 1'b1;
        counters_valid = 1'b1;
        input_sof_count = 32'h0000_0001;
        capture_good_count = 32'h0000_0002;
        capture_bad_count = 32'h0000_0000;
        algorithm_good_count = 32'h0000_0000;
        committed_frame_count = 32'h0000_0000;
        busy_drop_count = 32'h0000_0000;
        displayed_frame_count = 32'h0000_0000;
        base_red = 8'h12;
        base_green = 8'h34;
        base_blue = 8'h56;

        // HDMI (11,404) maps to physical landscape (100,8): row 0, bit 0.
        hdmi_x = 12'd11;
        hdmi_y = 12'd404;
        check_rgb(8'hff, 8'hff, 8'hff, "row0 bit0 set");

        // HDMI (11,392) maps to physical x=116: row 0, bit 1.
        hdmi_y = 12'd392;
        check_rgb(8'h18, 8'h18, 8'h18, "row0 bit1 clear");

        // HDMI (32,392) maps to physical y=24: row 1, bit 1.
        hdmi_x = 12'd32;
        check_rgb(8'hff, 8'hff, 8'hff, "row1 bit1 set");

        // Physical image region must pass through unchanged.
        hdmi_x = 12'd267;
        hdmi_y = 12'd240;
        check_rgb(8'h12, 8'h34, 8'h56, "image pass-through");

        counters_valid = 1'b0;
        hdmi_x = 12'd11;
        hdmi_y = 12'd404;
        check_rgb(8'h90, 8'h60, 8'h00, "invalid snapshot amber");

        de = 1'b0;
        check_rgb(8'h00, 8'h00, 8'h00, "blanking black");
        $display("PASS: physical-landscape frame counter overlay");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "timeout");
    end
endmodule
