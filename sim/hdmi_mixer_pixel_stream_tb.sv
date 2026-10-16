`timescale 1ns/1ps
// Every source pixel differs: catches line shifts that constant RGB misses.
module hdmi_mixer_pixel_stream_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,vs=0,de=0,user=0,last=0,track=0;
    reg [7:0] arrows=0;
    reg [95:0] x0=0,x1=0,y0=0,y1=0;
    reg [269:0] motion=0;
    reg [23:0] source_rgb=0;
    wire [23:0] rgb;
    integer xx=0,yy=0,frame=0,s,n,px,py;
    reg [23:0] data_q[0:2];reg de_q[0:2];
    integer x_q[0:2],y_q[0:2];
    integer checked=0,logo_checked=0,border_checked=0;
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.ENABLE_LOGO(1),.ENABLE_DEBUG_PREVIEW(0)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(vs),.I_video_hsync(1'b0),.I_video_de(de),
        .I_video_user(user),.I_video_last(last),.I_debug_status(4'hf),
        .I_bbox_valid(8'hff),.I_bbox_x_min(x0),.I_bbox_x_max(x1),.I_bbox_y_min(y0),.I_bbox_y_max(y1),
        .I_bbox_digit_valid(8'd0),.I_bbox_digits(32'h87654321),.I_track_view(track),.I_track_count(4'd8),
        .I_track_arrow_valid(arrows),.I_track_arrow_direction(24'd0),.I_track_center_x_bcd(128'h0220),
        .I_track_center_y_bcd(128'h0140),.I_motion_blocks(motion),.I_motion_ready(1'b1),.I_motion_global(1'b0),
        .I_debug_view(1'b0),.I_debug_box(3'd0),.I_downsample_valid(1'b0),.I_downsample_pixel(11'd0),
        .I_downsample_pixel_addr(10'd0),.I_downsample_box_index(3'd0),.I_camera_latency_us(32'd0),
        .I_camera_latency_valid(1'b0),.I_cnn_latency_us(32'd0),.I_cnn_latency_valid(1'b0),
        .O_video_rd_en(),.I_video_rd_data(source_rgb),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(),.O_hdmi_data(rgb));
    wire [23:0] rgb_baseline;
    hdmi_mixer_pre_counter_pipeline #(.H_OFFSET(0),.V_OFFSET(0),.ENABLE_LOGO(1),.ENABLE_DEBUG_PREVIEW(0)) baseline(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(vs),.I_video_hsync(1'b0),.I_video_de(de),
        .I_video_user(user),.I_video_last(last),.I_debug_status(4'hf),
        .I_bbox_valid(8'hff),.I_bbox_x_min(x0),.I_bbox_x_max(x1),.I_bbox_y_min(y0),.I_bbox_y_max(y1),
        .I_bbox_digit_valid(8'd0),.I_bbox_digits(32'h87654321),.I_track_view(track),.I_track_count(4'd8),
        .I_track_arrow_valid(arrows),.I_track_arrow_direction(24'd0),.I_track_center_x_bcd(128'h0220),
        .I_track_center_y_bcd(128'h0140),.I_motion_blocks(motion),.I_motion_ready(1'b1),.I_motion_global(1'b0),
        .I_debug_view(1'b0),.I_debug_box(3'd0),.I_downsample_valid(1'b0),.I_downsample_pixel(11'd0),
        .I_downsample_pixel_addr(10'd0),.I_downsample_box_index(3'd0),.I_camera_latency_us(32'd0),
        .I_camera_latency_valid(1'b0),.I_cnn_latency_us(32'd0),.I_cnn_latency_valid(1'b0),
        .O_video_rd_en(),.I_video_rd_data(source_rgb),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(),.O_hdmi_data(rgb_baseline));
    // Independent reference address uses integer multiplication and stage-1
    // stimulus coordinates; no dependency on the mixer's address logic.
    wire logo_active_ref=de_q[0] && x_q[0]>=7 && x_q[0]<=152 && y_q[0]>=34 && y_q[0]<=127;
    wire [13:0] logo_address_ref=logo_active_ref ? (y_q[0]-34)*146+x_q[0]-7 : 0;
    wire [24:0] logo_ref;
    anlogic_logo_rom reference_logo(.I_clk(clk),.I_addr(logo_address_ref),.O_pixel(logo_ref));
    reg [24:0] logo_for_output;
    reg border_expected,moving_expected,skip_sprite;
    reg [23:0] expected_rgb;
    always @(posedge clk)begin
        for(n=2;n>0;n=n-1)begin
            data_q[n]<=data_q[n-1];de_q[n]<=de_q[n-1];x_q[n]<=x_q[n-1];y_q[n]<=y_q[n-1];
        end
        data_q[0]<=source_rgb;de_q[0]<=de && rst_n;x_q[0]<=xx;y_q[0]<=yy;
        logo_for_output=logo_ref;
        #1;
        if(rst_n && de_q[2])begin
            px=x_q[2];py=y_q[2];
            if(rgb!==rgb_baseline)$fatal(1,"counter pipeline changed visible pixel frame=%0d xy=%0d,%0d got=%h old=%h",frame,px,py,rgb,rgb_baseline);
            if(!dut.O_hdmi_de)$fatal(1,"pixel DE misalignment");
            if(px<160 && py<160)begin
                expected_rgb=logo_for_output[24]?logo_for_output[23:0]:data_q[2];
                if(rgb!==expected_rgb)$fatal(1,"logo/background alignment frame=%0d xy=%0d,%0d got=%h expected=%h",frame,px,py,rgb,expected_rgb);
                logo_checked=logo_checked+1;
            end
            // Exclude the left panel/counter and top-right latency HUD.
            if(px>=192 && py>=48 && !(px>=375 && px<575 && py>=120 && py<144))begin
                border_expected=0;moving_expected=0;skip_sprite=0;
                for(s=0;s<8;s=s+1)begin
                    if(px>=x0[s*12+:12] && px<=x1[s*12+:12] && py>=y0[s*12+:12] && py<=y1[s*12+:12] &&
                       (px<=x0[s*12+:12]+1 || px>=x1[s*12+:12]-1 || py<=y0[s*12+:12]+1 || py>=y1[s*12+:12]-1))begin
                        border_expected=1;if(arrows[s])moving_expected=1;
                    end
                    if(track && arrows[s] && px>=x1[s*12+:12]+8 && px<x1[s*12+:12]+40 &&
                       py>=y0[s*12+:12] && py<y0[s*12+:12]+32)skip_sprite=1;
                end
                expected_rgb=border_expected?(track?(moving_expected?24'h0000ff:24'h00ff00):24'hff0000):data_q[2];
                if(!skip_sprite)begin
                    if(rgb!==expected_rgb)$fatal(1,"pixel stream frame=%0d xy=%0d,%0d got=%h expected=%h",frame,px,py,rgb,expected_rgb);
                    checked=checked+1;if(border_expected)border_checked=border_checked+1;
                end
            end
        end
    end
    initial begin
        for(s=0;s<8;s=s+1)begin
            x0[s*12+:12]=230+(s%4)*240;x1[s*12+:12]=270+(s%4)*240;
            y0[s*12+:12]=220+(s/4)*280;y1[s*12+:12]=300+(s/4)*280;
        end
        repeat(4)@(negedge clk);rst_n=1;
        for(frame=0;frame<3;frame=frame+1)begin
            track=(frame!=0);arrows=(frame==1)?0:8'h55;
            vs=1;de=0;repeat(200)@(negedge clk);vs=0;
            user=1;@(negedge clk);user=0;
            for(yy=0;yy<720;yy=yy+1)begin
                for(xx=0;xx<1280;xx=xx+1)begin
                    source_rgb={xx[11:0],yy[11:0]} ^ (frame*24'h10203);
                    de=1;last=(xx==1279);@(negedge clk);
                end
                de=0;last=0;repeat(6)@(negedge clk);
            end
        end
        repeat(5)@(negedge clk);
        if(checked<2000000 || logo_checked!=76800 || border_checked<10000)$fatal(1,"insufficient pixel coverage");
        $display("PASS: %0d changing source pixels, %0d logo pixels, eight red/green/blue borders and unchanged video latency",checked,logo_checked);$finish;
    end
    initial begin #40000000;$fatal(1,"timeout");end
endmodule
