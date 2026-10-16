`timescale 1ns/1ps
module digit_motion_arrow_mixer_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,vs=0,de=0,user=0,last=0,track=1;
    reg [7:0] arrows=1;
    reg [95:0] x0=200,x1=240,y0=100,y1=180;
    reg [269:0] motion=0;
    wire [23:0] rgb;
    reg sampled_de;reg [11:0] sampled_x,sampled_y;
    reg [7:0] checked=0;
    integer xx,yy,frame;
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.ENABLE_LOGO(0),.ENABLE_DEBUG_PREVIEW(0)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(vs),.I_video_hsync(1'b0),.I_video_de(de),
        .I_video_user(user),.I_video_last(last),.I_debug_status(4'hf),
        .I_bbox_valid(8'd1),.I_bbox_x_min(x0),.I_bbox_x_max(x1),.I_bbox_y_min(y0),.I_bbox_y_max(y1),
        .I_bbox_digit_valid(8'd1),.I_bbox_digits(32'h87654321),.I_track_view(track),.I_track_count(4'd1),
        .I_track_arrow_valid(arrows),.I_track_arrow_direction(24'd0),.I_track_center_x_bcd(128'h0220),
        .I_track_center_y_bcd(128'h0140),.I_motion_blocks(motion),.I_motion_ready(1'b1),.I_motion_global(1'b0),
        .I_debug_view(1'b0),.I_debug_box(3'd0),.I_downsample_valid(1'b0),.I_downsample_pixel(11'd0),
        .I_downsample_pixel_addr(10'd0),.I_downsample_box_index(3'd0),.I_camera_latency_us(32'd0),
        .I_camera_latency_valid(1'b0),.I_cnn_latency_us(32'd0),.I_cnn_latency_valid(1'b0),
        .O_video_rd_en(),.I_video_rd_data(24'h112233),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(),.O_hdmi_data(rgb));
    task check(input bit ok,input string msg);if(!ok)$fatal(1,"FAIL track=%0d at %0d,%0d RGB=%h: %s",track,sampled_x,sampled_y,rgb,msg);endtask
    always @(posedge clk)if(rst_n)begin
        sampled_x=dut.S_x_2d;sampled_y=dut.S_y_2d;sampled_de=dut.S_video_de_2d;
        #1;
        if(sampled_de)begin
            if(sampled_x==276 && sampled_y==116)begin
                check(rgb===((track && arrows[0])?24'hff8000:24'h112233),"arrow tip aligned with video");checked[0]=1;
            end
            if(sampled_x==264 && sampled_y==116)begin
                check(rgb===((track && arrows[0])?24'hff8000:24'h112233),"arrow shaft");checked[1]=1;
            end
            if(sampled_x==248 && sampled_y==100)begin
                check(rgb===24'h112233,"transparent sprite background");checked[2]=1;
            end
            if(sampled_x==240 && sampled_y==150)begin
                check(rgb===(track?(arrows[0]?24'h0000ff:24'h00ff00):24'hff0000),"existing box border priority/color");checked[3]=1;
            end
            if(sampled_x==220 && sampled_y==18)begin
                check(rgb===(track?24'hffff00:24'h112233),"frame-difference outline preserved");checked[4]=1;
            end
            if(sampled_x==260 && sampled_y==115)begin
                check(rgb===(track?(arrows[0]?24'hff8000:24'hffff00):24'h112233),"arrow wins over yellow block outline");checked[5]=1;
            end
        end
    end
    initial begin
        motion[0]=1;motion[37]=1;
        repeat(4)@(negedge clk);rst_n=1;
        for(frame=0;frame<3;frame=frame+1)begin
            track=(frame!=1);arrows=(frame==2)?0:1;vs=1;de=0;repeat(200)@(negedge clk);vs=0;
            user=1;@(negedge clk);user=0;checked=0;
            for(yy=0;yy<190;yy=yy+1)begin
                for(xx=0;xx<1280;xx=xx+1)begin de=1;last=(xx==1279);@(negedge clk);end
                de=0;last=0;repeat(4)@(negedge clk);
            end
            repeat(5)@(negedge clk);check(checked[5:0]==6'h3f,"all output landmarks visited");
        end
        $display("PASS: actual HDMI mixer arrow color/alignment, transparency, motion/box priority and old-mode bypass");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
