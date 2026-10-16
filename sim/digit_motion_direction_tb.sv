`timescale 1ns/1ps
module digit_motion_direction_tb;
    parameter USE_ERAM=1;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,fs=0,vblank=0,update=0;
    reg [7:0] valid=0;
    reg [95:0] x0=0,x1=0,y0=0,y1=0;
    wire [7:0] ov,av;
    wire [23:0] direction;
    wire [95:0] centers;
    integer d,k,s,raw_slot,xc,yc,moving_seen;
    digit_motion_tracker #(.USE_ERAM_IP(USE_ERAM)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_frame_start(fs),.I_vblank(vblank),
        .I_motion_blocks(270'd0),.I_motion_ready(1'b0),.I_motion_global(1'b0),
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
        begin
            old_av=av;old_dir=direction;
            @(negedge clk);update=1;@(negedge clk);update=0;cycles=0;
            while(!dut.pending_ready && cycles<20000)begin
                check(av===old_av && direction===old_dir,"arrow changed during active frame");
                @(negedge clk);cycles=cycles+1;
            end
            check(dut.pending_ready,"compute completes");vblank=1;cycles=0;
            while(!dut.preloaded && cycles<256)begin @(negedge clk);cycles=cycles+1;end
            check(dut.preloaded,"display preloads");vblank=0;fs=1;
            @(negedge clk);fs=0;@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;enable=1;
        // All eight direction encodings, stable stop, then each ID's new seed.
        for(d=0;d<8;d=d+1)begin
            restart();box(0,600,360);submit();check(av==0,"new target has no direction history");
            for(k=1;k<=8;k=k+1)begin
                clear_boxes();box(7,600+12*k*step_x(d),360+12*k*step_y(d));submit();
            end
            check(ov==1 && av==1 && direction[2:0]==d,"eight-way movement direction");
            for(k=0;k<2;k=k+1)submit();check(av==1,"short stop hold prevents flicker");
            for(k=0;k<20;k=k+1)submit();check(av==0,"stopped target eventually hides arrow");
        end
        d=0;restart();box(0,600,360);submit();
        for(k=0;k<40;k=k+1)begin
            clear_boxes();box(3,600+(k%2),360-((k+1)%2));submit();
            check(av==0,"one-pixel stationary jitter stays below dead zone");
        end
        restart();box(0,600,360);submit();moving_seen=0;
        for(k=1;k<=24;k=k+1)begin
            clear_boxes();box(5,600+k,360);submit();
            if(av[0])begin moving_seen=1;check(direction[2:0]==0,"slow move points right");end
        end
        check(moving_seen==1,"slow movement accumulates beyond one observation window");
        for(k=1;k<=12;k=k+1)begin clear_boxes();box(2,624-8*k,360);submit();end
        check(av==1 && direction[2:0]==4,"direction reverses after sustained left motion");
        clear_boxes();submit();check(ov==0 && av==0,"missed target hides arrow");
        box(4,530,360);submit();check(ov==1 && av==0,"reacquired target seeds history without a jump arrow");
        // Eight simultaneously moving targets, each a different direction.
        restart();
        for(s=0;s<8;s=s+1)box(s,250+(s%4)*250,200+(s/4)*300);
        submit();check(ov==8'hff && av==0,"eight new IDs seed independently");
        for(k=1;k<=8;k=k+1)begin
            clear_boxes();
            for(s=0;s<8;s=s+1)begin
                raw_slot=(s+k)%8;
                box(raw_slot,250+(s%4)*250+8*k*step_x(s),200+(s/4)*300+8*k*step_y(s));
            end
            submit();
        end
        check(ov==8'hff && av==8'hff,"eight target arrows independently valid");
        for(s=0;s<8;s=s+1)check(direction[s*3+:3]==s,"directions remain bound to IDs after input permutation");
        // Stop one target while the other seven continue moving.
        for(k=9;k<=24;k=k+1)begin
            clear_boxes();
            for(s=0;s<8;s=s+1)begin
                xc=250+(s%4)*250+64*step_x(s)+((s==0)?0:2*(k-8));
                yc=200+(s/4)*300+64*step_y(s);
                box(s,xc,yc);
            end
            submit();
        end
        check(ov[0] && !av[0],"one stopped ID hides independently");
        check(av[6] && direction[20:18]==0,"another ID continues pointing right");
        restart();box(1,1279,719);submit();check(av==0,"screen-edge center seeds without overflow");
        $display("PASS: direction ERAM=%0d eight ways, jitter, slow motion, reversal, stop, reacquisition and eight IDs",USE_ERAM);
        $finish;
    end
    initial begin #30000000;$fatal(1,"timeout");end
endmodule
