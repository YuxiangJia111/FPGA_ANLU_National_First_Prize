`timescale 1ns / 1ns

module display_top (
    input  wire        I_pixel_clk,
    input  wire        I_serial_clk,
    input  wire        I_rst_n,
    input  wire [23:0] I_video_data,
    input  wire        I_video_vsync,
    input  wire        I_video_hsync,
    input  wire        I_video_de,
    input  wire        I_video_user,
    input  wire        I_video_last,
    input  wire [3:0]  I_debug_status,
    input  wire [7:0]  I_bbox_valid,
    input  wire [95:0] I_bbox_x_min,
    input  wire [95:0] I_bbox_x_max,
    input  wire [95:0] I_bbox_y_min,
    input  wire [95:0] I_bbox_y_max,
    input  wire [7:0]  I_bbox_digit_valid,
    input  wire [31:0] I_bbox_digits,
    input  wire        I_track_view,
    input  wire [3:0]  I_track_count,
    input  wire [7:0] I_track_arrow_valid,
    input  wire [23:0] I_track_arrow_direction,
    input  wire [127:0] I_track_center_x_bcd, I_track_center_y_bcd,
    input  wire [269:0] I_motion_blocks,
    input  wire I_motion_ready, I_motion_global,
    input  wire        I_debug_view,
    input  wire [2:0]  I_debug_box,
    input  wire        I_downsample_valid,
    input  wire [10:0] I_downsample_pixel,
    input  wire [9:0]  I_downsample_pixel_addr,
    input  wire [2:0]  I_downsample_box_index,
    input  wire [31:0] I_camera_latency_us,
    input  wire        I_camera_latency_valid,
    input  wire [31:0] I_cnn_latency_us,
    input  wire        I_cnn_latency_valid,
    output wire        O_hdmi_frame_start,
    output wire        O_video_vsync,
    output wire        O_video_rd_en,
    output wire        O_process_vsync,
    output wire        O_process_hsync,
    output wire        O_process_de,
    output wire        O_process_user,
    output wire        O_process_last,
    output wire        O_tmds_ch0_p,
    output wire        O_tmds_ch1_p,
    output wire        O_tmds_ch2_p,
    output wire        O_tmds_clk_p
);

wire video_vsync;
wire video_hsync;
wire video_de;
wire video_user;
wire video_last;
wire hdmi_vsync;
wire hdmi_hsync;
wire hdmi_de;
wire [23:0] hdmi_data;
wire unused_mixer_rd_en;
reg hdmi_vsync_d;
reg hdmi_de_d;
reg hdmi_sync_sampled;
reg hdmi_frame_armed;

// Combinational pulse accompanies the pixel sampled by the TX on this edge.
// Do not report the startup partial frame before observing a real sync edge.
assign O_hdmi_frame_start = I_rst_n && hdmi_frame_armed &&
                            hdmi_de && !hdmi_de_d;
always @(posedge I_pixel_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        hdmi_vsync_d <= 1'b0;
        hdmi_de_d <= 1'b0;
        hdmi_sync_sampled <= 1'b0;
        hdmi_frame_armed <= 1'b0;
    end else begin
        hdmi_vsync_d <= hdmi_vsync;
        hdmi_de_d <= hdmi_de;
        hdmi_sync_sampled <= 1'b1;
        if(hdmi_sync_sampled && hdmi_vsync && !hdmi_vsync_d)
            hdmi_frame_armed <= 1'b1;
        else if(hdmi_de && !hdmi_de_d)
            hdmi_frame_armed <= 1'b0;
    end
end

assign O_video_vsync = ~video_vsync;
assign O_video_rd_en = video_de;
assign O_process_vsync = video_vsync;
assign O_process_hsync = video_hsync;
assign O_process_de    = video_de;
assign O_process_user  = video_user;
assign O_process_last  = video_last;

uivtc #(
    .H_ActiveSize (1280),
    .H_FrameSize  (1650),
    .H_SyncStart  (1390),
    .H_SyncEnd    (1430),
    .V_ActiveSize (720),
    .V_FrameSize  (750),
    .V_SyncStart  (725),
    .V_SyncEnd    (730)
) u_hdmi_vtc (
    .I_vtc_rstn     (I_rst_n),
    .I_vtc_clk      (I_pixel_clk),
    .O_vtc_vs       (video_vsync),
    .O_vtc_hs       (video_hsync),
    .O_vtc_de_valid (video_de),
    .O_vtc_user     (video_user),
    .O_vtc_last     (video_last)
);

hdmi_mixer #(
    .H_OFFSET   (0),
    .V_OFFSET   (0),
    .IMG_WIDTH  (1280),
    .IMG_HEIGHT (720),
    .DEBUG_MODE (0)
) u_hdmi_mixer (
    .I_clk           (I_pixel_clk),
    .I_rst_n         (I_rst_n),
    .I_video_vsync   (I_video_vsync),
    .I_video_hsync   (I_video_hsync),
    .I_video_de      (I_video_de),
    .I_video_user    (I_video_user),
    .I_video_last    (I_video_last),
    .I_debug_status  (I_debug_status),
    .I_bbox_valid    (I_bbox_valid),
    .I_bbox_x_min    (I_bbox_x_min),
    .I_bbox_x_max    (I_bbox_x_max),
    .I_bbox_y_min    (I_bbox_y_min),
    .I_bbox_y_max    (I_bbox_y_max),
    .I_bbox_digit_valid (I_bbox_digit_valid),
    .I_bbox_digits   (I_bbox_digits),
    .I_track_view (I_track_view), .I_track_count (I_track_count),
    .I_track_arrow_valid (I_track_arrow_valid), .I_track_arrow_direction (I_track_arrow_direction),
    .I_track_center_x_bcd (I_track_center_x_bcd),
    .I_track_center_y_bcd (I_track_center_y_bcd),
    .I_motion_blocks (I_motion_blocks), .I_motion_ready (I_motion_ready),
    .I_motion_global (I_motion_global),
    .I_debug_view    (I_debug_view),
    .I_debug_box     (I_debug_box),
    .I_downsample_valid      (I_downsample_valid),
    .I_downsample_pixel      (I_downsample_pixel),
    .I_downsample_pixel_addr (I_downsample_pixel_addr),
    .I_downsample_box_index  (I_downsample_box_index),
    .I_camera_latency_us    (I_camera_latency_us),
    .I_camera_latency_valid (I_camera_latency_valid),
    .I_cnn_latency_us       (I_cnn_latency_us),
    .I_cnn_latency_valid    (I_cnn_latency_valid),
    .O_video_rd_en   (unused_mixer_rd_en),
    .I_video_rd_data (I_video_data),
    .O_hdmi_vsync    (hdmi_vsync),
    .O_hdmi_hsync    (hdmi_hsync),
    .O_hdmi_de       (hdmi_de),
    .O_hdmi_data     (hdmi_data)
);

hdmi_tx u_hdmi_tx (
    .I_pixel_clk        (I_pixel_clk),
    .I_serial_clk       (I_serial_clk),
    .I_rst              (~I_rst_n),
    .I_key_in           (1'b0),
    .I_edid_read_trig   (1'b0),
    .O_edid_read_valid  (),
    .O_edid_read_data   (),
    .I_video_rgb_enable (1'b1),
    .I_video_in_vs      (hdmi_vsync),
    .I_video_in_de      (hdmi_de),
    .I_video_in_user    (1'b0),
    .I_video_in_valid   (1'b0),
    .I_video_in_last    (1'b0),
    .O_video_in_ready   (),
    .I_video_in_data    (hdmi_data),
    .I_audio_valid      (1'b0),
    .I_audio_left_data  (24'd0),
    .I_audio_right_data (24'd0),
    .I_i2s_BCLK         (1'b0),
    .I_i2s_LRCK         (1'b0),
    .I_i2s_DOUT         (1'b0),
    .O_ddc_scl          (),
    .IO_ddc_sda         (),
    .O_hdmi_clk_p       (),
    .O_hdmi_tx_p        (),
    .O_tmds_ch0_p       (O_tmds_ch0_p),
    .O_tmds_ch1_p       (O_tmds_ch1_p),
    .O_tmds_ch2_p       (O_tmds_ch2_p),
    .O_tmds_clk_p       (O_tmds_clk_p)
);

endmodule
