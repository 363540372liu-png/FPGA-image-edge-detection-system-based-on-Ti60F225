`timescale 1ns/1ps
module tb_split_framebuffer_commit;
    localparam int W=8,H=6,N=W*H;
    logic clk=0,rst_n=0;
    logic [7:0] wr_gray=0;
    logic wr_edge=0,wr_valid=0,wr_sof=0,wr_end=0,wr_good=0;
    logic [10:0] wr_threshold=128;
    logic [11:0] wr_x=0,wr_y=0;
    logic rd_tick=0;
    logic buffer_error,committed,rd_edge,gray_view,edge_view,pixel_valid,has_frame;
    logic [3:0] error_code;
    logic [7:0] rd_gray;
    logic [31:0] sampled,committed_count,dropped,displayed_count;
    logic [15:0] words;
    logic [10:0] displayed_threshold;
    always #5 clk=~clk;

    split_pingpong_framebuffer #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H)) dut(
        .wr_clk(clk),.wr_rst_n(rst_n),.wr_gray,.wr_edge,.wr_valid,
        .wr_start_of_frame(wr_sof),.wr_frame_end(wr_end),.wr_frame_good(wr_good),
        .wr_frame_threshold(wr_threshold),.wr_x,.wr_y,
        .buffer_error_wr(buffer_error),.buffer_error_code_wr(error_code),
        .frame_committed_wr(committed),.last_sampled_pixel_count_wr(sampled),
        .last_written_word_count_wr(words),.committed_frame_count_wr(committed_count),
        .dropped_frame_count(dropped),.rd_clk(clk),.rd_rst_n(rst_n),
        .rd_x(12'd0),.rd_y(12'd0),.rd_de(1'b0),.rd_frame_tick(rd_tick),
        .rd_gray,.rd_edge,.rd_gray_view(gray_view),.rd_edge_view(edge_view),
        .rd_pixel_valid(pixel_valid),.display_has_frame(has_frame),
        .displayed_frame_count(displayed_count),.displayed_frame_threshold(displayed_threshold)
    );

    task automatic send_frame(input integer threshold,input bit good);
        begin
            for(integer i=0;i<N;i=i+1) begin
                @(negedge clk);
                wr_valid=1;wr_x=i%W;wr_y=i/W;wr_gray=i+threshold;wr_edge=i[0];
                wr_sof=(i==0);wr_end=(i==N-1);wr_good=wr_end&&good;wr_threshold=threshold;
            end
            @(negedge clk);wr_valid=0;wr_sof=0;wr_end=0;wr_good=0;
        end
    endtask

    task automatic display_tick;
        begin
            repeat(5)@(posedge clk);@(negedge clk);rd_tick=1;
            @(negedge clk);rd_tick=0;repeat(5)@(posedge clk);
        end
    endtask

    initial begin
        repeat(4)@(posedge clk);@(negedge clk);rst_n=1;
        send_frame(80,1);
        if(committed_count!=1||sampled!=N||words!=N/2||buffer_error)
            $fatal(1,"first commit failed");
        send_frame(96,1);
        if(dropped!=1||committed_count!=1)$fatal(1,"busy frame not distinguished");
        display_tick();
        if(!has_frame||displayed_threshold!=80||displayed_count!=1)
            $fatal(1,"first display metadata mismatch");
        send_frame(160,0);
        if(!buffer_error||committed_count!=1)$fatal(1,"bad frame was not rejected");
        send_frame(176,1);
        if(committed_count!=2||buffer_error)$fatal(1,"recovery frame failed");
        display_tick();
        if(displayed_threshold!=176||displayed_count!=2||dropped!=1)
            $fatal(1,"recovery metadata mismatch");
        $display("SPLIT_COMMIT_PASS commits=%0d displayed=%0d dropped=%0d",committed_count,displayed_count,dropped);
        $finish;
    end
endmodule

