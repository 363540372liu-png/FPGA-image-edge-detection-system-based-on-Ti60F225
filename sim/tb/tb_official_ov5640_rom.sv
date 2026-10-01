`timescale 1ns/1ps
module tb_official_ov5640_rom;
    logic [7:0]  lut_index;
    logic [23:0] lut_data;
    logic [7:0]  lut_size;

    I2C_OV5640_1280720_Config dut (
        .LUT_INDEX(lut_index), .LUT_DATA(lut_data), .LUT_SIZE(lut_size)
    );

    task automatic check_entry(input logic [7:0] index,
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
        if (lut_size !== 8'd252)
            $fatal(1, "LUT_SIZE=%0d expected=252", lut_size);
        check_entry(8'd56,  24'h4300_61); // RGB565, MS byte first
        check_entry(8'd223, 24'h3808_05); // 1280 = 0x0500
        check_entry(8'd224, 24'h3809_00);
        check_entry(8'd225, 24'h380a_02); // 720 = 0x02d0
        check_entry(8'd226, 24'h380b_d0);
        $display("PASS: merchant official OV5640 ROM programs 1280x720 RGB565");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "timeout");
    end
endmodule
