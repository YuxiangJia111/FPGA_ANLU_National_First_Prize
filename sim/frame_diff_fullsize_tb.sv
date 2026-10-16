`timescale 1ns/1ps
module frame_diff_fullsize_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,ending=0,valid=0,ref_valid=1;
    reg [3:0] current=12;
    reg [11:0] x=0,y=0;
    wire [269:0] blocks;
    wire ready,global_change;
    integer xx,yy;
    frame_diff_motion dut(.I_clk(clk),.I_rst_n(rst_n),.I_enable(1'b1),
        .I_frame_start(start),.I_frame_end(ending),.I_sample_valid(valid),.I_reference_valid(ref_valid),
        .I_current(current),.I_reference(4'd12),.I_sample_x(x),.I_sample_y(y),
        .O_completed_blocks(),.O_completed_ready(),.O_completed_global(),.O_completed_valid(),
        .O_blocks(blocks),.O_reference_ready(ready),.O_global_change(global_change));
    task frame(input integer pattern,input [269:0] expected,input bit expected_global);
        reg [269:0] previous;
        begin
            previous=blocks;
            @(negedge clk);start=1;@(negedge clk);start=0;
            for(yy=0;yy<229;yy=yy+1)for(xx=0;xx<275;xx=xx+1)begin
                x=xx;y=yy;valid=1;current=12;
                if(pattern==1 && xx<16 && yy<16)current=2;
                if(pattern==2 && xx==274 && yy==228)current=9;
                if(pattern==4 && xx>=273 && yy==228)current=9;
                if(pattern==3)current=2;
                ending=(xx==274 && yy==228);
                @(negedge clk);
            end
            valid=0;ending=0;repeat(3)@(negedge clk);
            if(blocks!==previous)$fatal(1,"FAIL: full-size mid-frame publication");
            start=1;@(negedge clk);start=0;
            if(blocks!==expected || !ready || global_change!==expected_global)
                $fatal(1,"FAIL: full-size bitmap/status pattern %0d",pattern);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        frame(0,0,0);frame(1,270'b1,0);frame(2,0,0);frame(4,270'b1<<269,0);
        frame(3,0,1);frame(0,0,0);
        $display("PASS: production 275x229 samples, all 270 block addresses, tail threshold and global count");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
