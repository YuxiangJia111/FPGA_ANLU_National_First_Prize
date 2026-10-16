`timescale 1ns/1ps
module frame_diff_motion_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,start=0,ending=0,valid=0,reference_valid=1;
    reg [3:0] current=12,reference=12;
    reg [11:0] x=0,y=0;
    wire [24:0] blocks;wire ready,global_change;
    integer xx,yy,pattern;
    frame_diff_motion #(.SAMPLE_COLS(19),.SAMPLE_ROWS(18),.BLOCK_SHIFT(2),.MIN_CHANGED(4)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_frame_start(start),.I_frame_end(ending),
        .I_sample_valid(valid),.I_reference_valid(reference_valid),.I_current(current),.I_reference(reference),
        .I_sample_x(x),.I_sample_y(y),.O_completed_blocks(),.O_completed_ready(),.O_completed_global(),.O_completed_valid(),
        .O_blocks(blocks),.O_reference_ready(ready),.O_global_change(global_change));
    task check(input bit ok,input string msg);if(!ok)$fatal(1,"FAIL: %s",msg);endtask
    task frame(input integer scene,input [24:0] expected,input bit expected_ready,expected_global);
        reg [24:0] old_blocks;
        begin
            old_blocks=blocks;
            @(negedge clk);start=1;@(negedge clk);start=0;
            for(yy=0;yy<18;yy=yy+1) for(xx=0;xx<19;xx=xx+1) begin
                x=xx;y=yy;valid=1;reference_valid=1;current=12;reference=12;
                case(scene)
                    1:if(xx<4 && yy<4)current=2;
                    2:if(yy==0 && xx<3)current=2; // too few points
                    3:if(yy==0 && xx<4)current=2; // exact threshold
                    4:if(xx<4 && yy<4)current=10; // below gray difference threshold
                    5:if(xx>=16 && yy>=16)current=9; // partial corner, difference exactly 3
                    6:begin current=2;end // global change
                    7:if(xx==3 && yy==3)reference_valid=0;
                    8:if(xx==18 && yy==17)valid=0; // truncated frame
                    9:if(xx<4 && yy<4)begin current=12;reference=2;end
                    default:begin end
                endcase
                ending=(xx==18 && yy==17); // final sample and end on the same edge
                @(negedge clk);
                check(blocks===old_blocks,"no mid-frame bitmap changes");
            end
            valid=0;ending=0;repeat(3)@(negedge clk);
            check(blocks===old_blocks,"result waits for next frame boundary");
            start=1;@(negedge clk);start=0;
            check(blocks===expected,"motion block mask");
            check(ready===expected_ready && global_change===expected_global,"reference/global status");
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;enable=1;
        frame(0,0,1,0);frame(1,25'h1,1,0);frame(2,0,1,0);frame(3,25'h1,1,0);
        frame(4,0,1,0);frame(5,25'h1000000,1,0);frame(6,0,1,1);
        frame(7,0,0,0);frame(8,0,0,0);frame(9,25'h1,1,0);
        @(negedge clk);enable=0;@(negedge clk);
        check(blocks==0 && !ready && !global_change,"mode exit clears stale result");
        $display("PASS: frame difference thresholds, partial tiles, global suppression and atomic publication");$finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
