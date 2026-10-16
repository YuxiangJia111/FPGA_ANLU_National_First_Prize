`timescale 1ns/1ps
// Use the real project VTC, retaining its 1650-clock line / five-line VSYNC.
// Only active/total vertical sizes are shortened to speed up the regression.
module digit_tracker_vtc_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    wire vs,hs,de,user,last;
    reg update=0;
    reg [95:0] x0=0,x1=0,y0=0,y1=0;
    reg [7:0] valid=0;
    wire [7:0] ov;
    wire [95:0] cx,cy;
    wire done;
    integer frame_no=0,prior_frame;
    reg [95:0] old_cx;
    reg sampled_user, sampled_de;
    uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
        .V_ActiveSize(32),.V_FrameSize(64),.V_SyncStart(40),.V_SyncEnd(45)) vtc(
        .I_vtc_rstn(rst_n),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),
        .O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
    digit_motion_tracker #(.REQUIRE_FRAME_DIFF(1)) dut(.I_motion_blocks(270'd0),.I_motion_ready(1'b1),.I_motion_global(1'b0),.I_clk(clk),.I_rst_n(rst_n),.I_enable(1'b1),
        .I_frame_start(user),.I_vblank(vs),.I_bbox_update(update),.I_bbox_valid(valid),
        .I_x_min(x0),.I_x_max(x1),.I_y_min(y0),.I_y_max(y1),
        .O_valid(ov),.O_x_min(),.O_x_max(),.O_y_min(),.O_y_max(),
        .O_center_x(cx),.O_center_y(cy),.O_center_x_bcd(),.O_center_y_bcd(),
        .O_arrow_valid(),.O_arrow_direction(),.O_count(),.O_update(done));
    always @(posedge clk)if(rst_n)begin
        update<=user;old_cx=cx;prior_frame=frame_no;sampled_user=user;sampled_de=de;
        if(user)begin
            valid<=1;x0[11:0]<=280+frame_no*10;x1[11:0]<=320+frame_no*10;
            y0[11:0]<=160;y1[11:0]<=240;frame_no=frame_no+1;
        end
        #1;
        if(sampled_de && cx!==old_cx)$fatal(1,"FAIL: display coordinates changed during active video");
        if(sampled_user && prior_frame>=1)begin
            if(!done || ov!==1 || cx[11:0]!==300+(prior_frame-1)*10 || cy[11:0]!==200)
                $fatal(1,"FAIL: VSYNC preload / next-frame detector update timing");
            if(prior_frame==4)begin
                $display("PASS: actual VTC VSYNC polarity/window, active-video stability and back-to-back frame updates");
                $finish;
            end
        end
    end
    initial begin repeat(4)@(negedge clk);rst_n=1;end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
