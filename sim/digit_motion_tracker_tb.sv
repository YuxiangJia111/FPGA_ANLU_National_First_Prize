`timescale 1ns/1ps
module digit_motion_tracker_tb;
    parameter USE_ERAM=0;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,frame_start=0,update=0,vblank=0;
    reg [7:0] valid=0;
    reg [95:0] x0=0,x1=0,y0=0,y1=0;
    wire [7:0] ov;
    wire [95:0] ox0,ox1,oy0,oy1,ocx,ocy;
    wire [127:0] bx,by;
    wire [3:0] count;
    wire committed;
    integer n;
    digit_motion_tracker #(.USE_ERAM_IP(USE_ERAM)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),
        .I_frame_start(frame_start),.I_vblank(vblank),.I_motion_blocks(270'd0),.I_motion_ready(1'b0),.I_motion_global(1'b0),
        .I_bbox_update(update),.I_bbox_valid(valid),
        .I_x_min(x0),.I_x_max(x1),.I_y_min(y0),.I_y_max(y1),
        .O_valid(ov),.O_x_min(ox0),.O_x_max(ox1),.O_y_min(oy0),.O_y_max(oy1),
        .O_center_x(ocx),.O_center_y(ocy),.O_center_x_bcd(bx),.O_center_y_bcd(by),
        .O_arrow_valid(),.O_arrow_direction(),.O_count(count),.O_update(committed)
    );
    task check(input bit ok,input string message);
        if(!ok) $fatal(1,"FAIL: %s",message);
    endtask
    task preload_display;
        integer cycles;
        begin
            vblank=1;cycles=0;
            while(!dut.preloaded && cycles<256)begin
                @(negedge clk);cycles=cycles+1;
            end
            check(dut.preloaded,"display preload fits vertical blank");
            check(!committed,"valid mask waits for active frame start");
            vblank=0;
        end
    endtask
    task clear_boxes;
        begin valid=0;x0=0;x1=0;y0=0;y1=0;end
    endtask
    task box(input integer slot,xc,yc,w,h);
        begin
            valid[slot]=1;
            x0[slot*12 +: 12]=xc-w/2;x1[slot*12 +: 12]=xc+w/2;
            y0[slot*12 +: 12]=yc-h/2;y1[slot*12 +: 12]=yc+h/2;
        end
    endtask
    task restart;
        begin
            @(negedge clk);enable=0;repeat(2) @(negedge clk);
            check(ov==0 && count==0,"mode exit clears visible tracks");
            enable=1;clear_boxes();
        end
    endtask
    task submit;
        reg [7:0] previous_valid;
        reg [95:0] previous_centers;
        reg [127:0] previous_bcd;
        integer cycles;
        begin
            previous_valid=ov;previous_centers=ocx;previous_bcd=bx;
            @(negedge clk);update=1;
            @(negedge clk);update=0;cycles=0;
            while(!dut.pending_ready && cycles<20000) begin
                check(ov===previous_valid && ocx===previous_centers && bx===previous_bcd,
                      "public result must stay stable before frame boundary");
                @(negedge clk);cycles=cycles+1;
            end
            check(dut.pending_ready,"bounded processing time");
            check(!committed,"no mid-frame commit");
            preload_display();
            frame_start=1;@(negedge clk);frame_start=0;
            check(committed,"result commits at frame start");
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;enable=1;
        clear_boxes();submit();check(count==0,"empty result");
        for(n=0;n<8;n=n+1) box(n,250+100*n,200,40,80);
        submit();check(ov==8'hff && count==8,"allocate eight unique tracks");
        for(n=0;n<8;n=n+1) check(ocx[n*12 +: 12]==250+100*n,"initial ID positions");
        clear_boxes();
        for(n=0;n<8;n=n+1) box(7-n,255+100*n,203,40,80);
        submit();
        for(n=0;n<8;n=n+1) begin
            check(ocx[n*12 +: 12]==255+100*n,"IDs survive detector slot reversal");
            check(ocy[n*12 +: 12]==203,"Y centers follow matched targets");
            check(ox0[n*12 +: 12]==235+100*n,"bounds follow ID");
        end
        check(bx[15:0]==16'h0255 && by[15:0]==16'h0203,"decimal center conversion");
        clear_boxes();submit();submit();check(ov==0,"missing targets hidden");
        box(6,260,205,40,80);submit();check(ov==1 && ocx[11:0]==260,"reacquire reserved ID");
        for(n=0;n<5;n=n+1) begin clear_boxes();submit();end
        check(dut.active==0,"retire after five missing detector updates");
        box(3,800,400,40,80);submit();check(ov==1,"reuse retired ID");

        restart();box(0,300,200,40,80);box(1,360,200,40,80);submit();
        clear_boxes();box(0,340,200,40,80);box(1,300,200,40,80);submit();
        check(ocx[11:0]==300 && ocx[23:12]==340,"global nearest pair avoids slot-order theft");

        restart();box(0,300,200,40,80);submit();
        clear_boxes();box(0,600,200,40,80);submit();
        check(ov==2 && ocx[23:12]==600,"distance gate rejects a distant replacement");

        restart();box(0,300,200,40,80);submit();
        clear_boxes();box(0,300,200,200,80);submit();
        check(ov==2,"size gate rejects a different-shaped target");

        restart();box(0,1279,719,0,0);submit();
        check(bx[15:0]==16'h1279 && by[15:0]==16'h0719,"four-digit coordinate limits");
        restart();box(5,500,300,40,80);submit();check(ov==1,"mode re-entry restarts IDs");
        // Detector payload changes immediately after its update pulse are ignored.
        clear_boxes();box(7,510,301,40,80);
        @(negedge clk);update=1;@(negedge clk);update=0;clear_boxes();
        wait(dut.pending_ready);@(negedge clk);preload_display();frame_start=1;
        @(negedge clk);frame_start=0;
        check(ov==1 && ocx[11:0]==510,"snapshot isolates input changes");
        // A too-short blank must never expose a partly loaded active frame.
        @(negedge clk);clear_boxes();box(2,520,305,40,80);update=1;
        @(negedge clk);update=0;
        wait(dut.pending_ready);@(negedge clk);vblank=1;
        repeat(10)@(negedge clk);vblank=0;
        repeat(2)@(negedge clk);
        check(!dut.preloaded && ov==0,"short blank hides partial display records");
        frame_start=1;@(negedge clk);frame_start=0;
        check(!committed,"short blank cannot commit partial records");
        preload_display();frame_start=1;@(negedge clk);frame_start=0;
        check(committed && ov==1 && ocx[11:0]==520,"retry succeeds at next full blank");
        $display("PASS: digit_motion_tracker ERAM=%0d regression",USE_ERAM);$finish;
    end
    initial begin #20000000;$fatal(1,"timeout");end
endmodule
