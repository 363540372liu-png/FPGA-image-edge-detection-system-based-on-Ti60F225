`timescale 1ns/1ps
module tb_gray_preview_2x2_mean;
    localparam int W=8, H=6;
    logic clk=0, rst_n=0;
    logic in_valid=0, in_sof=0, in_end=0, in_good=0;
    logic [7:0] gray_in=0;
    logic [2:0] in_x=0;
    logic [2:0] in_y=0;
    logic out_valid, out_sof, out_end, out_good, coordinate_error;
    logic [7:0] out_gray;
    logic [11:0] out_x, out_y;
    integer checked=0, errors=0, cycle_count=0;

    always #5 clk=~clk;
    gray_preview_2x2_mean #(.SOURCE_WIDTH(W),.SOURCE_HEIGHT(H),
        .X_WIDTH(3),.Y_WIDTH(3)) dut (
        .clk,.rst_n,.in_valid,.gray_in,.in_x,.in_y,.in_sof,
        .in_frame_end(in_end),.in_frame_good(in_good),
        .out_valid,.out_gray,.out_x,.out_y,.out_sof,
        .out_frame_end(out_end),.out_frame_good(out_good),.coordinate_error
    );

    always @(posedge clk) begin
        cycle_count <= cycle_count+1;
        if(cycle_count>2000) $fatal(1,"GRAY_MEAN_TIMEOUT");
        if(rst_n && out_valid) begin
            integer sx,sy,p0,p1,p2,p3,exp;
            sx=out_x*2; sy=out_y*2;
            p0=sy*W+sx; p1=p0+1; p2=p0+W; p3=p2+1;
            exp=(p0+p1+p2+p3+2)>>2;
            if(out_gray!==exp[7:0]) begin
                $error("mean mismatch (%0d,%0d) exp=%0d got=%0d",out_x,out_y,exp,out_gray);
                errors=errors+1;
            end
            if(out_sof!==((out_x==0)&&(out_y==0))) errors=errors+1;
            if(out_end!==((out_x==W/2-1)&&(out_y==H/2-1))) errors=errors+1;
            if(out_good!==out_end) errors=errors+1;
            checked=checked+1;
        end
    end

    initial begin
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
        for(integer y=0;y<H;y=y+1) begin
            for(integer x=0;x<W;x=x+1) begin
                if(((x+y)%5)==0) begin in_valid=0; @(negedge clk); end
                in_valid=1; in_x=x; in_y=y; gray_in=y*W+x;
                in_sof=(x==0&&y==0); in_end=(x==W-1&&y==H-1); in_good=in_end;
                @(negedge clk);
            end
        end
        in_valid=0; in_sof=0; in_end=0; in_good=0;
        repeat(8) @(posedge clk);
        if(coordinate_error||checked!=W*H/4||errors)
            $fatal(1,"GRAY_MEAN_FAIL checked=%0d errors=%0d coord=%0b",checked,errors,coordinate_error);
        $display("GRAY_MEAN_PASS checked=%0d rounding=nearest",checked);
        $finish;
    end
endmodule
