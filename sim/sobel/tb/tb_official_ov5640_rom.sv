`timescale 1ns/1ps
module tb_official_ov5640_rom;
    logic [8:0]  lut_index;
    logic [23:0] lut_data;
    logic [8:0]  lut_size;

    I2C_OV5640_640480_Config dut (
        .LUT_INDEX(lut_index), .LUT_DATA(lut_data), .LUT_SIZE(lut_size)
    );

    task automatic check_entry(input logic [8:0] index,
                               input logic [23:0] expected);
        begin
            lut_index = index;
            #1;
            if (lut_data !== expected)
                $fatal(1, "ROM[%0d]=%06h expected=%06h",
                       index, lut_data, expected);
        end
    endtask

    initial begin
        if (lut_size !== 9'd312)
            $fatal(1, "LUT_SIZE=%0d expected=312", lut_size);
        check_entry(9'd0,   24'h3008_82);
        check_entry(9'd1,   24'h3008_42);
        check_entry(9'd4,   24'h4740_21);
        check_entry(9'd8,   24'h3035_11);
        check_entry(9'd9,   24'h3036_69);
        check_entry(9'd62,  24'h3808_02);
        check_entry(9'd63,  24'h3809_80);
        check_entry(9'd64,  24'h380a_01);
        check_entry(9'd65,  24'h380b_e0);
        check_entry(9'd97,  24'h4300_61);
        check_entry(9'd98,  24'h501f_01);
        check_entry(9'd278, 24'h3808_02);
        check_entry(9'd279, 24'h3809_80);
        check_entry(9'd280, 24'h380a_01);
        check_entry(9'd281, 24'h380b_e0);
        check_entry(9'd311, 24'h3000_00);
        $display("PASS: complete official OV5640 VGA RGB565 table plus controller reset adapter");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "timeout");
    end
endmodule
