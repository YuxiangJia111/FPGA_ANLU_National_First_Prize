`timescale 1ns/1ps
// Compare visible frame results against the accepted pre-ERAM tracker.
module digit_tracker_eram_equivalence_tb;
    parameter USE_ERAM=1;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1,fs=0,vblank=0,update=0;
    reg [7:0] valid=0;
    reg [95:0] x0=0,x1=0,y0=0,y1=0;
    wire [7:0] ov,gv;
    wire [95:0] ax0,ax1,ay0,ay1,acx,acy,gx0,gx1,gy0,gy1,gcx,gcy;
    wire [127:0] abx,aby,gbx,gby;
    wire [3:0] count,gcount;
    wire done,gdone;
    reg [31:0] rng=32'h19a753e1;
    integer frame,n,s,cx,cy,w,h,cycles,max_cycles=0;
    digit_motion_tracker #(.USE_ERAM_IP(USE_ERAM)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_frame_start(fs),.I_vblank(vblank),
        .I_motion_blocks(270'd0),.I_motion_ready(1'b0),.I_motion_global(1'b0),
        .I_bbox_update(update),.I_bbox_valid(valid),.I_x_min(x0),.I_x_max(x1),.I_y_min(y0),.I_y_max(y1),
        .O_valid(ov),.O_x_min(ax0),.O_x_max(ax1),.O_y_min(ay0),.O_y_max(ay1),
        .O_center_x(acx),.O_center_y(acy),.O_center_x_bcd(abx),.O_center_y_bcd(aby),
        .O_arrow_valid(),.O_arrow_direction(),.O_count(count),.O_update(done));
    digit_motion_tracker_legacy golden (
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_frame_start(fs),
        .I_bbox_update(update),.I_bbox_valid(valid),.I_x_min(x0),.I_x_max(x1),.I_y_min(y0),.I_y_max(y1),
        .O_valid(gv),.O_x_min(gx0),.O_x_max(gx1),.O_y_min(gy0),.O_y_max(gy1),
        .O_center_x(gcx),.O_center_y(gcy),.O_center_x_bcd(gbx),.O_center_y_bcd(gby),.O_count(gcount),.O_update(gdone));
    task check(input bit ok,input string msg);if(!ok)$fatal(1,"frame %0d: %s",frame,msg);endtask
    task step_rng;
        begin rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};end
    endtask
    task run_frame;
        reg [95:0] old_x;
        reg [127:0] old_bcd;
        reg [7:0] old_valid;
        begin
            old_x=ax0;old_bcd=abx;old_valid=ov;
            @(negedge clk);update=1;
            @(negedge clk);update=0;x0=0;x1=0;y0=0;y1=0;valid=0;
            cycles=0;
            while((!dut.pending_ready || !golden.pending_ready) && cycles<20000)begin
                check(ax0===old_x && abx===old_bcd && ov===old_valid,"active-frame output changed");
                @(negedge clk);cycles=cycles+1;
            end
            check(cycles<20000,"processing timeout");
            if(cycles>max_cycles)max_cycles=cycles;
            check(dut.active===golden.active,"active metadata differs");
            for(n=0;n<8;n=n+1)if(dut.active[n])
                check(dut.missed[n]===golden.missed[n],"miss counter differs");
            vblank=1;cycles=0;
            while(!dut.preloaded && cycles<256)begin @(negedge clk);cycles=cycles+1;end
            check(dut.preloaded,"preload timeout");
            vblank=0;fs=1;@(negedge clk);fs=0;
            check(done && gdone && ov===gv && count===gcount,"published status differs");
            for(n=0;n<8;n=n+1)if(ov[n])begin
                check({ax0[n*12+:12],ax1[n*12+:12],ay0[n*12+:12],ay1[n*12+:12]}===
                      {gx0[n*12+:12],gx1[n*12+:12],gy0[n*12+:12],gy1[n*12+:12]},"box/ID differs");
                check({acx[n*12+:12],acy[n*12+:12],abx[n*16+:16],aby[n*16+:16]}===
                      {gcx[n*12+:12],gcy[n*12+:12],gbx[n*16+:16],gby[n*16+:16]},"center/BCD differs");
            end
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(frame=0;frame<120;frame=frame+1)begin
            if(frame%24==0)begin
                enable=0;repeat(2)@(negedge clk);enable=1;
            end
            valid=0;x0=0;x1=0;y0=0;y1=0;
            for(s=0;s<8;s=s+1)begin
                step_rng();
                if(frame%11!=0 && rng[2:0]!=0)begin
                    // Permutations, same-looking targets, births/losses and size changes.
                    n=(s+frame)%8;cx=160+s*130+(rng[7:3]%31);cy=180+(s%4)*75+(rng[12:8]%21);
                    w=40+(rng[16:13]%12);h=(frame%17==0)?160:80;
                    valid[n]=1;x0[n*12+:12]=cx-w/2;x1[n*12+:12]=cx+w/2;
                    y0[n*12+:12]=cy-h/2;y1[n*12+:12]=cy+h/2;
                end
            end
            run_frame();
        end
        // Abort an in-flight snapshot, then prove stale ERAM contents stay masked.
        valid=8'hff;x0={8{12'd300}};x1={8{12'd340}};y0={8{12'd200}};y1={8{12'd280}};
        update=1;@(negedge clk);update=0;repeat(7)@(negedge clk);
        enable=0;repeat(2)@(negedge clk);enable=1;
        valid=0;x0=0;x1=0;y0=0;y1=0;run_frame();
        $display("PASS: ERAM=%0d matches legacy tracker for 120 frames; maximum compute cycles=%0d",USE_ERAM,max_cycles);
        $finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule
