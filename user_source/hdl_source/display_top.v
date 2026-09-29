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
