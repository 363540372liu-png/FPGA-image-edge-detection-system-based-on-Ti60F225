`timescale 1ns/1ps

// Adapter around the complete merchant-supplied VGA RGB565 register table.
// Entry 0 preserves the soft reset used by the proven SCCB controller;
// entries 1..311 are the official table, unmodified.
module I2C_OV5640_640480_Config (
    input  logic [8:0]  LUT_INDEX,
    output logic [23:0] LUT_DATA,
    output logic [8:0]  LUT_SIZE
);
    logic [8:0] official_index;
    logic [23:0] official_data;
    logic [8:0] official_size;

    assign official_index = LUT_INDEX + 9'd1;
    assign LUT_SIZE = 9'd312;

    I2C_OV5640_RGB565_Config_Official u_official_table (
        .LUT_INDEX(official_index),
        .LUT_DATA(official_data),
        .LUT_SIZE(official_size)
    );

    always_comb begin
        if (LUT_INDEX == 9'd0)
            LUT_DATA = 24'h3008_82;
        else
            LUT_DATA = official_data;
    end
endmodule
