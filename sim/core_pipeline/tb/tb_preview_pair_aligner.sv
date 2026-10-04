`timescale 1ns/1ps
module tb_preview_pair_aligner;
    localparam int W=320,H=240,N=W*H,LAG=321;
    logic clk=0,rst_n=0;
    logic gray_valid=0,gray_sof=0,gray_end=0;
    logic [7:0] gray_value=0;
    logic [11:0] gray_x=0,gray_y=0;
    logic [10:0] gray_threshold=11'd80;
    logic edge_valid=0,edge_value=0,edge_sof=0,edge_end=0,edge_good=0;
    logic [11:0] edge_x=0,edge_y=0;
    logic out_valid,out_edge,out_sof,out_end,out_good,alignment_error;
    logic [7:0] out_gray;
    logic [11:0] out_x,out_y;
    logic [10:0] out_threshold,fifo_max;
    integer gidx=0,eidx=0,checked=0,errors=0,cycles=0;
    always #5 clk=~clk;

    preview_pair_aligner dut(
        .clk,.rst_n,.gray_valid,.gray_value,.gray_x,.gray_y,.gray_sof,
        .gray_frame_end(gray_end),.gray_frame_threshold(gray_threshold),
        .edge_valid,.edge_value,.edge_x,.edge_y,.edge_sof,
        .edge_frame_end(edge_end),.edge_frame_good(edge_good),
        .out_valid,.out_gray,.out_edge,.out_x,.out_y,.out_sof,
        .out_frame_end(out_end),.out_frame_good(out_good),
        .out_frame_threshold(out_threshold),.alignment_error,
        .fifo_max_level(fifo_max)
    );
    function automatic [7:0] gv(input integer i); gv=(i*37+11)&8'hff; endfunction
    function automatic ev(input integer i); ev=((i%17)==0)||((i%W)==0); endfunction

    always @(posedge clk) begin
        cycles<=cycles+1;
        if(cycles>200000) $fatal(1,"PAIR_TIMEOUT");
        if(rst_n && out_valid) begin
            integer idx;
            idx=out_y*W+out_x;
            if(out_gray!==gv(idx)||out_edge!==ev(idx)||out_sof!==(idx==0)||
               out_end!==(idx==N-1)||out_good!==out_end) begin
                $error("pair mismatch idx=%0d gray=%0d edge=%0b sof=%0b end=%0b good=%0b",idx,out_gray,out_edge,out_sof,out_end,out_good);
                errors=errors+1;
            end
            if(out_sof && out_threshold!=80) errors=errors+1;
            checked=checked+1;
        end
    end

    initial begin
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
        while(eidx<N || gidx<N) begin
            gray_valid=(gidx<N);
            if(gray_valid) begin
                gray_x=gidx%W; gray_y=gidx/W; gray_value=gv(gidx);
                gray_sof=(gidx==0); gray_end=(gidx==N-1);
            end
            edge_valid=(gidx>=LAG && eidx<N);
            if(edge_valid) begin
                edge_x=eidx%W; edge_y=eidx/W; edge_value=ev(eidx);
                edge_sof=(eidx==0); edge_end=(eidx==N-1); edge_good=edge_end;
            end
            @(negedge clk);
            if(gray_valid) gidx=gidx+1;
            if(edge_valid) eidx=eidx+1;
        end
        gray_valid=0;edge_valid=0;gray_sof=0;gray_end=0;edge_sof=0;edge_end=0;edge_good=0;
        repeat(8) @(posedge clk);
        if(alignment_error||checked!=N||errors||fifo_max<LAG||fifo_max>1024)
            $fatal(1,"PAIR_FAIL checked=%0d errors=%0d align=%0b max=%0d",checked,errors,alignment_error,fifo_max);
        $display("PAIR_PASS checked=%0d fifo_max=%0d",checked,fifo_max);
        $finish;
    end
endmodule
