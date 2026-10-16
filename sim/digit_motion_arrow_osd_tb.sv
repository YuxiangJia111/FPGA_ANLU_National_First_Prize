`timescale 1ns/1ps
module digit_motion_arrow_osd_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1,vblank=0,de=1;
    reg [11:0] x=0,y=0;
    reg [7:0] bv=1,av=1;
    reg [23:0] direction=0;
    reg [95:0] x0=0,x1=0,y0=0;
    wire hit;
    integer d,s,ox,oy,bx,by,tx,ty;
    digit_motion_arrow_osd dut(.I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_vblank(vblank),
        .I_de(de),.I_x(x),.I_y(y),.I_box_valid(bv),.I_arrow_valid(av),.I_direction(direction),
        .I_x_min(x0),.I_x_max(x1),.I_y_min(y0),.O_hit(hit));
    function integer rot_x(input integer px,py,dir);
        case(dir/2)0:rot_x=px;1:rot_x=31-py;2:rot_x=31-px;default:rot_x=py;endcase
    endfunction
    function integer rot_y(input integer px,py,dir);
        case(dir/2)0:rot_y=py;1:rot_y=px;2:rot_y=31-py;default:rot_y=31-px;endcase
    endfunction
    task check(input bit ok,input string msg);if(!ok)$fatal(1,"FAIL dir=%0d pixel=%0d,%0d: %s",d,x,y,msg);endtask
    task layout;
        begin
            @(negedge clk);de=0;vblank=1;repeat(3)@(negedge clk);vblank=0;de=1;
        end
    endtask
    task pixel(input integer px,py,input bit expected);
        begin
            @(negedge clk);x=px;y=py;repeat(2)@(posedge clk);#1;
            check(hit===expected,"arrow landmark, mask, edge or placement");
        end
    endtask
    task landmark(input integer base_x,base_y,input bit expected);
        begin pixel(ox+rot_x(base_x,base_y,d),oy+rot_y(base_x,base_y,d),expected);end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        x0[11:0]=100;x1[11:0]=140;y0[11:0]=100;layout();ox=148;oy=100;
        for(d=0;d<8;d=d+1)begin
            direction[2:0]=d;
            if(d%2==0)begin
                landmark(28,16,1);landmark(4,16,1);landmark(20,8,1);landmark(20,24,1);
                landmark(0,16,0);landmark(29,16,0);
            end else begin
                landmark(26,26,1);landmark(6,6,1);landmark(16,26,1);landmark(26,16,1);
                landmark(0,0,0);landmark(28,28,0);
            end
            landmark(16,16,1);landmark(4,4,0);
            pixel(ox-1,oy+16,0);pixel(ox+32,oy+16,0);
        end
        // Check exact two-edge latency with a one-clock active pixel pulse.
        d=0;direction=0;de=0;repeat(3)@(negedge clk);
        x=ox+16;y=oy+16;de=1;@(posedge clk);#1;check(!hit,"first stage cannot render early");
        @(negedge clk);de=0;@(posedge clk);#1;check(hit,"second stage renders the pulse");
        @(posedge clk);#1;check(!hit,"blanking follows pulse without trailing pixel");
        de=1;
        // Geometry changes only inside blanking, not while scanning video.
        x0[11:0]=300;x1[11:0]=340;pixel(176,116,1);pixel(376,116,0);
        layout();pixel(176,116,0);pixel(376,116,1);
        // Entire sprite remains visible near bottom/right and at top/left.
        x0[11:0]=1240;x1[11:0]=1279;y0[11:0]=710;layout();
        pixel(1228,704,1);pixel(1280,704,0);pixel(1228,720,0);
        x0[11:0]=0;x1[11:0]=20;y0[11:0]=0;layout();direction[2:0]=4;
        pixel(31,15,1);pixel(0,0,0);
        x0[11:0]=950;x1[11:0]=990;y0[11:0]=18;direction=0;layout();
        pixel(1026,68,1);pixel(1026,34,0); // moved below the latency HUD
        // Eight independent slots use the same renderer without losing IDs.
        bv=8'hff;av=8'hff;
        for(s=0;s<8;s=s+1)begin
            x0[s*12+:12]=20+s*140;x1[s*12+:12]=60+s*140;y0[s*12+:12]=200;
            direction[s*3+:3]=s;
        end
        layout();
        for(d=0;d<8;d=d+1)begin
            bx=(d%2==0)?28:26;by=(d%2==0)?16:26;
            pixel(68+d*140+rot_x(bx,by,d),200+rot_y(bx,by,d),1);
        end
        av[3]=0;d=3;pixel(68+3*140+rot_x(26,26,3),200+rot_y(26,26,3),0);
        // Low-ID overlapping windows have deterministic priority.
        bv=3;av=3;x0=0;x1=0;y0=0;
        x0[11:0]=100;x0[23:12]=100;x1[11:0]=140;x1[23:12]=140;
        y0[11:0]=100;y0[23:12]=100;direction=0;direction[5:3]=4;layout();
        pixel(176,116,1);pixel(151,115,0);av=2;pixel(151,115,1);
        enable=0;pixel(151,115,0);enable=1;de=0;pixel(151,115,0);
        de=1;bv=0;pixel(151,115,0);
        $display("PASS: arrow OSD eight orientations, landmarks, two-stage timing, screen edges, masks and eight slots");$finish;
    end
endmodule
