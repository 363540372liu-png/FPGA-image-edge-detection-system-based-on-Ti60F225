`timescale 1ns/1ps
module tb_split_pingpong_framebuffer;
    localparam int W=320,H=240,N=W*H;
    logic clk=0,rst_n=0;
    logic [7:0] wr_gray=0;
    logic wr_edge=0,wr_valid=0,wr_sof=0,wr_end=0,wr_good=0;
    logic [10:0] wr_threshold=11'd80;
    logic [11:0] wr_x=0,wr_y=0,rd_x=0,rd_y=0;
    logic rd_de=0,rd_tick=0;
    logic buffer_error,committed,rd_edge,gray_view,edge_view,pixel_valid,has_frame;
    logic [3:0] error_code;
    logic [7:0] rd_gray;
    logic [31:0] sampled,committed_count,dropped,displayed_count;
    logic [15:0] words;
    logic [10:0] displayed_threshold;
    integer fd,errors=0;
    always #5 clk=~clk;

    split_pingpong_framebuffer dut(
        .wr_clk(clk),.wr_rst_n(rst_n),.wr_gray,.wr_edge,.wr_valid,
        .wr_start_of_frame(wr_sof),.wr_frame_end(wr_end),.wr_frame_good(wr_good),
        .wr_frame_threshold(wr_threshold),.wr_x,.wr_y,
        .buffer_error_wr(buffer_error),.buffer_error_code_wr(error_code),
        .frame_committed_wr(committed),.last_sampled_pixel_count_wr(sampled),
        .last_written_word_count_wr(words),.committed_frame_count_wr(committed_count),
        .dropped_frame_count(dropped),.rd_clk(clk),.rd_rst_n(rst_n),
        .rd_x,.rd_y,.rd_de,.rd_frame_tick(rd_tick),.rd_gray,.rd_edge,
        .rd_gray_view(gray_view),.rd_edge_view(edge_view),.rd_pixel_valid(pixel_valid),
        .display_has_frame(has_frame),.displayed_frame_count(displayed_count),
        .displayed_frame_threshold(displayed_threshold)
    );
    function automatic [7:0] gv(input integer x,input integer y); gv=(x*255)/319; endfunction
    function automatic ev(input integer x,input integer y); ev=(x%40==0)||(y%30==0)||(x==y); endfunction

    task automatic read_point(input integer hx,input integer hy,input bit expect_valid,input bit expect_gray);
        integer px,py,sx,sy;
        begin
            rd_x=hx;rd_y=hy;rd_de=1;@(posedge clk);#1;
            px=(((480-hy)*4)/3)-1; py=(hx*3)/4;
            if(pixel_valid!==expect_valid) begin $error("valid (%0d,%0d)",hx,hy);errors=errors+1;end
            if(expect_valid) begin
                sx=(px<320)?px:px-320;sy=py-120;
                if(expect_gray) begin
                    if(!gray_view||edge_view||rd_gray!==gv(sx,sy)) begin $error("gray map");errors=errors+1;end
                end else if(gray_view||!edge_view||rd_edge!==ev(sx,sy)) begin $error("edge map");errors=errors+1;end
            end
            rd_de=0;@(posedge clk);
        end
    endtask

    initial begin
        fd=$fopen("sim/split_hdmi_readout.ppm","w");
        if(!fd)$fatal(1,"cannot open preview dump");
        repeat(5)@(posedge clk);rst_n=1;
        for(integer i=0;i<N;i=i+1) begin
            wr_valid=1;wr_x=i%W;wr_y=i/W;wr_gray=gv(i%W,i/W);wr_edge=ev(i%W,i/W);
            wr_sof=(i==0);wr_end=(i==N-1);wr_good=wr_end;@(posedge clk);
        end
        wr_valid=0;wr_sof=0;wr_end=0;wr_good=0;
        repeat(8)@(posedge clk);rd_tick=1;@(posedge clk);rd_tick=0;repeat(3)@(posedge clk);
        if(!has_frame||displayed_threshold!=80||sampled!=N||words!=N/2||buffer_error)
            $fatal(1,"commit failure frame=%0b threshold=%0d sampled=%0d words=%0d err=%0h",has_frame,displayed_threshold,sampled,words,error_code);
        read_point(320,240,1,1);
        read_point(0,240,0,0);
        read_point(639,240,0,0);
        read_point(320,80,1,0);

        $fdisplay(fd,"P3\n640 480\n255");
        for(integer y=0;y<480;y=y+1) begin
            for(integer x=0;x<640;x=x+1) begin
                rd_x=x;rd_y=y;rd_de=1;@(posedge clk);#1;
                if(pixel_valid&&gray_view)$fwrite(fd,"%0d %0d %0d ",rd_gray,rd_gray,rd_gray);
                else if(pixel_valid&&edge_view&&rd_edge)$fwrite(fd,"255 255 255 ");
                else $fwrite(fd,"0 0 0 ");
            end
            $fwrite(fd,"\n");
        end
        $fclose(fd);rd_de=0;
        if(errors)$fatal(1,"SPLIT_FB_FAIL errors=%0d",errors);
        $display("SPLIT_FB_PASS pixels=%0d words=%0d threshold=%0d",sampled,words,displayed_threshold);
        $finish;
    end
endmodule
