`timescale 1ns/1ps
module digit_motion_fusion_tb;
    parameter USE_ERAM=1;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,fs=0,vblank=0,update=0;
    reg [7:0] valid=0;
    reg [269:0] blocks=0;reg ready=1,global_change=0;
    reg [95:0] x0=0,x1=0,y0=0,y1=0;
    wire [7:0] ov,av;
    wire [23:0] direction;
    wire [95:0] centers;
    integer d,k,s,raw_slot,xc,yc,moving_seen;
    digit_motion_tracker #(.USE_ERAM_IP(USE_ERAM),.REQUIRE_FRAME_DIFF(1)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_frame_start(fs),.I_vblank(vblank),
        .I_motion_blocks(blocks),.I_motion_ready(ready),.I_motion_global(global_change),
        .I_bbox_update(update),.I_bbox_valid(valid),.I_x_min(x0),.I_x_max(x1),.I_y_min(y0),.I_y_max(y1),
        .O_valid(ov),.O_x_min(),.O_x_max(),.O_y_min(),.O_y_max(),.O_center_x(centers),.O_center_y(),
        .O_center_x_bcd(),.O_center_y_bcd(),.O_arrow_valid(av),.O_arrow_direction(direction),.O_count(),.O_update());
    function integer step_x(input integer code);
        case(code)0,1,7:step_x=1;3,4,5:step_x=-1;default:step_x=0;endcase
    endfunction
    function integer step_y(input integer code);
        case(code)1,2,3:step_y=1;5,6,7:step_y=-1;default:step_y=0;endcase
    endfunction
    task check(input bit ok,input string msg);if(!ok)$fatal(1,"FAIL direction=%0d step=%0d: %s",d,k,msg);endtask
    task clear_boxes;begin valid=0;x0=0;x1=0;y0=0;y1=0;end endtask
    task box(input integer slot,cx,cy);
        begin
            valid[slot]=1;x0[slot*12+:12]=cx-20;x1[slot*12+:12]=cx+20;
            y0[slot*12+:12]=cy-40;y1[slot*12+:12]=cy+40;
        end
    endtask
    task restart;
        begin
            @(negedge clk);enable=0;repeat(2)@(negedge clk);
            check(av==0,"mode exit hides all arrows");enable=1;clear_boxes();
        end
    endtask
    task submit;
        reg [7:0] old_av;
        reg [23:0] old_dir;
        integer cycles;
        reg [269:0] saved_blocks;reg saved_ready,saved_global;
        begin
            old_av=av;old_dir=direction;saved_blocks=blocks;saved_ready=ready;saved_global=global_change;
            @(negedge clk);update=1;@(negedge clk);update=0;blocks=~blocks;ready=~ready;global_change=~global_change;cycles=0;
            while(!dut.pending_ready && cycles<20000)begin
                check(av===old_av && direction===old_dir,"arrow changed during active frame");
                @(negedge clk);cycles=cycles+1;
            end
            check(dut.pending_ready,"compute completes");blocks=saved_blocks;ready=saved_ready;global_change=saved_global;vblank=1;cycles=0;
            while(!dut.preloaded && cycles<256)begin @(negedge clk);cycles=cycles+1;end
            check(dut.preloaded,"display preloads");vblank=0;fs=1;
            @(negedge clk);fs=0;@(negedge clk);
        end
    endtask
    task activity(input integer cx,cy);
        begin blocks[((cy-18)/48)*18+(cx-198)/48]=1;end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;enable=1;
        // A hand/other tile changes while the tracked digit is stationary.
        box(0,300,360);blocks=0;activity(300,360);submit();
        for(k=0;k<16;k=k+1)submit();check(av==0,"difference alone never confirms motion");
        // Displacement with no difference never confirms motion.
        restart();blocks=0;box(0,300,360);submit();
        for(k=1;k<=12;k=k+1)begin clear_boxes();box(7,300+10*k,360);submit();check(av==0,"coordinates alone suppressed");end
        // Remote activity cannot qualify this digit, even with displacement.
        blocks=0;activity(900,600);
        for(k=13;k<=16;k=k+1)begin clear_boxes();box(3,300+10*k,360);submit();check(av==0,"unrelated tile suppressed");end
        // Local activity and displacement combine; input order changes every time.
        for(k=17;k<=20;k=k+1)begin
            clear_boxes();box(k%8,300+10*k,360);blocks=0;activity(300+10*k,360);submit();
        end
        check(av==1 && direction[2:0]==0,"joint evidence confirms same-ID right motion");
        blocks=0;submit();check(av==1,"short evidence gap held");
        repeat(3)submit();check(av==0,"activity hold expires without evidence");
        activity(500,360);submit();check(av==1,"local evidence restores confirmation");
        global_change=1;submit();check(av==0,"global light change immediately suppresses confirmation");
        global_change=0;ready=0;submit();check(av==0,"invalid reference immediately suppresses confirmation");
        ready=1;submit();check(av==1,"usable local evidence recovers");
        clear_boxes();submit();check(av==0 && ov==0,"lost digit hidden");
        box(2,510,360);submit();check(av==0,"reacquisition seeds fresh motion state");
        // Two IDs: only the one with local frame difference turns blue.
        restart();clear_boxes();box(0,300,250);box(1,700,500);blocks=0;submit();
        for(k=1;k<=8;k=k+1)begin
            clear_boxes();box(6,300+10*k,250);box(2,700+10*k,500);
            blocks=0;activity(300+10*k,250);submit();
        end
        check(ov==3 && av==1,"activity remains attached to ID after detection permutation");
        // All eight IDs share the scanner, but only alternating IDs qualify.
        restart();clear_boxes();blocks=0;
        for(s=0;s<8;s=s+1)box(s,270+(s%4)*180,200+(s/4)*300);
        submit();
        for(k=1;k<=8;k=k+1)begin
            clear_boxes();blocks=0;
            for(s=0;s<8;s=s+1)begin
                box((s+k)%8,270+(s%4)*180+6*k,200+(s/4)*300);
                if(s%2==0)activity(270+(s%4)*180+6*k,200+(s/4)*300);
            end
            submit();
        end
        check(ov==8'hff && av==8'h55,"eight independent IDs share evidence scanner");
        // Clipped bottom-right tile is valid evidence.
        restart();clear_boxes();box(0,960,690);blocks=0;submit();
        for(k=1;k<=8;k=k+1)begin
            clear_boxes();box(0,960+6*k,690);if(x1[11:0]>1022)x1[11:0]=1022;blocks=0;blocks[269]=1;submit();
        end
        check(av==1,"partial ROI edge tile participates in fusion");
        restart();check(av==0,"mode reset clears confirmed motion");
        $display("PASS: joint motion USE_ERAM=%0d, independent IDs, ROI overlap, hold, invalid/global rejection, loss/reset",USE_ERAM);$finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule
