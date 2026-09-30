`timescale 1ns / 1ns

module design_top_wrapper (
    input  wire        I_sys_clk,
    input  wire        I_rst_n,

    output wire        O_cam_scl,
    inout  wire        IO_cam_sda,
    output wire        O_cam_24m,
    output wire        O_cam_rst,

    input  wire [3:0]  I_key,
    input  wire [3:0]  I_sw,
    output wire [7:0]  O_DIG,
    output wire [7:0]  O_SEL,

    output wire        O_screen_pwm,
    output wire        O_tmds_ch0_p,
    output wire        O_tmds_ch1_p,
    output wire        O_tmds_ch2_p,
    output wire        O_tmds_clk_p,

    inout  wire        IO_rx_clk_pad_n,
    inout  wire        IO_rx_clk_pad_p,
    inout  wire [3:0]  IO_rx_data_pad_n,
    inout  wire [3:0]  IO_rx_data_pad_p,

    output wire [12:0] ddr_addr,
    output wire [1:0]  ddr_ba,
    output wire [0:0]  ddr_cke,
    output wire [0:0]  ddr_odt,
    output wire [0:0]  ddr_cs_n,
    output wire        ddr_ras_n,
    output wire        ddr_cas_n,
    output wire        ddr_we_n,
    output wire [0:0]  ddr_ck_p,
    output wire [0:0]  ddr_ck_n,
    inout  wire [1:0]  ddr_dm,
    inout  wire [15:0] ddr_dq,
    inout  wire [1:0]  ddr_dqs_p,
    inout  wire [1:0]  ddr_dqs_n
);

wire clk_100m;
wire clk_24m;
wire hdmi_pixel_clk;
wire hdmi_serial_clk;
wire pll_lock;
wire system_rst_n;
wire camera_video_clk;
wire [39:0] camera_tdata;
wire camera_tlast;
wire camera_tuser;
wire camera_tvalid;
wire [1:0] camera_lane_error;
wire [127:0] isp_tdata;
wire isp_tlast;
wire isp_tuser;
wire isp_tvalid;
wire [23:0] display_video_data;
wire [23:0] processed_video_data;
wire [23:0] processed_ycbcr_data;
wire display_video_vsync;
wire display_video_rd_en;
wire process_video_vsync;
wire process_video_hsync;
wire process_video_de;
wire process_video_user;
wire process_video_last;
wire processed_video_vsync;
wire processed_video_hsync;
wire processed_video_de;
wire processed_video_user;
wire processed_video_last;
wire [3:0] ddr_debug_status;
wire ddr_init_calib_complete;
wire [2:0] image_mode;
reg [2:0] image_mode_sync_1;
reg [2:0] image_mode_sync_2;
wire [3:0] control_key_event;
wire [3:0] control_switch_state;

assign system_rst_n = pll_lock;
assign O_screen_pwm = 1'b1;

control_top u_control_top (
    .I_clk          (clk_24m),
    .I_rst_n        (system_rst_n),
    .I_key_n        (I_key),
    .I_switch       (I_sw),
    .O_key_event    (control_key_event),
    .O_switch_state (control_switch_state),
    .O_image_mode   (image_mode)
);

always @(posedge hdmi_pixel_clk or negedge system_rst_n) begin
    if(!system_rst_n) begin
        image_mode_sync_1 <= 3'b001;
        image_mode_sync_2 <= 3'b001;
    end else begin
        image_mode_sync_1 <= image_mode;
        image_mode_sync_2 <= image_mode_sync_1;
    end
end

PLL u_PLL (
    .refclk   (I_sys_clk),
    .reset    (~I_rst_n),
    .clk0_out (clk_100m),
    .clk1_out (clk_24m),
    .clk4_out (hdmi_pixel_clk),
    .clk5_out (hdmi_serial_clk),
    .lock     (pll_lock)
);

SC500CS_top u_SC500CS_top (
    .I_ctrl_clk         (clk_24m),
    .I_lp_clk           (clk_100m),
    .I_rst_n            (system_rst_n),
    .I_key_n            (4'hf),
    .O_cam_scl          (O_cam_scl),
    .IO_cam_sda         (IO_cam_sda),
    .O_cam_24m          (O_cam_24m),
    .O_cam_rst          (O_cam_rst),
    .O_DIG              (O_DIG),
    .O_SEL              (O_SEL),
    .IO_rx_clk_pad_n    (IO_rx_clk_pad_n),
    .IO_rx_clk_pad_p    (IO_rx_clk_pad_p),
    .IO_rx_data_pad_n   (IO_rx_data_pad_n),
    .IO_rx_data_pad_p   (IO_rx_data_pad_p),
    .O_video_clk        (camera_video_clk),
    .O_video_tdata      (camera_tdata),
    .O_video_tlast      (camera_tlast),
    .O_video_tuser      (camera_tuser),
    .O_video_tvalid     (camera_tvalid),
    .O_lane_error       (camera_lane_error)
);

ISP_preprocess_top u_ISP_preprocess_top (
    .I_clk    (camera_video_clk),
    .I_rst_n  (system_rst_n),
    .I_tdata  (camera_tdata),
    .I_tlast  (camera_tlast),
    .I_tuser  (camera_tuser),
    .I_tvalid (camera_tvalid),
    .O_tdata  (isp_tdata),
    .O_tlast  (isp_tlast),
    .O_tuser  (isp_tuser),
    .O_tvalid (isp_tvalid)
);

DDR_top u_DDR_top (
    .I_sys_clk             (I_sys_clk),
    .I_rst_n               (system_rst_n),
    .I_camera_clk          (camera_video_clk),
    .I_camera_frame_start  (isp_tuser),
    .I_camera_valid        (isp_tvalid),
    .I_camera_data         (isp_tdata),
    .I_mipi_rx_error       (1'b0),
    .I_display_clk         (hdmi_pixel_clk),
    .I_display_vsync       (display_video_vsync),
    .I_display_rd_en       (display_video_rd_en),
    .O_display_data        (display_video_data),
    .O_debug_status        (ddr_debug_status),
    .O_init_calib_complete (ddr_init_calib_complete),
    .ddr_addr              (ddr_addr),
    .ddr_ba                (ddr_ba),
    .ddr_cke               (ddr_cke),
    .ddr_odt               (ddr_odt),
    .ddr_cs_n              (ddr_cs_n),
    .ddr_ras_n             (ddr_ras_n),
    .ddr_cas_n             (ddr_cas_n),
    .ddr_we_n              (ddr_we_n),
    .ddr_ck_p              (ddr_ck_p),
    .ddr_ck_n              (ddr_ck_n),
    .ddr_dm                (ddr_dm),
    .ddr_dq                (ddr_dq),
    .ddr_dqs_p             (ddr_dqs_p),
    .ddr_dqs_n             (ddr_dqs_n)
);

img_processing #(
    .IMG_WIDTH  (1280),
    .IMG_HEIGHT (720)
) u_img_processing (
    .I_clk    (hdmi_pixel_clk),
    .I_rst_n  (system_rst_n),
    .I_mode   (image_mode_sync_2),
    .I_rgb    (display_video_data),
    .I_vsync  (process_video_vsync),
    .I_hsync  (process_video_hsync),
    .I_de     (process_video_de),
    .I_user   (process_video_user),
    .I_last   (process_video_last),
    .O_rgb    (processed_video_data),
    .O_ycbcr  (processed_ycbcr_data),
    .O_vsync  (processed_video_vsync),
    .O_hsync  (processed_video_hsync),
    .O_de     (processed_video_de),
    .O_user   (processed_video_user),
    .O_last   (processed_video_last)
);

display_top u_display_top (
    .I_pixel_clk    (hdmi_pixel_clk),
    .I_serial_clk   (hdmi_serial_clk),
    .I_rst_n        (system_rst_n),
    .I_video_data   (processed_video_data),
    .I_video_vsync  (processed_video_vsync),
    .I_video_hsync  (processed_video_hsync),
    .I_video_de     (processed_video_de),
    .I_video_user   (processed_video_user),
    .I_video_last   (processed_video_last),
    .I_debug_status (ddr_debug_status),
    .O_video_vsync  (display_video_vsync),
    .O_video_rd_en  (display_video_rd_en),
    .O_process_vsync(process_video_vsync),
    .O_process_hsync(process_video_hsync),
    .O_process_de   (process_video_de),
    .O_process_user (process_video_user),
    .O_process_last (process_video_last),
    .O_tmds_ch0_p   (O_tmds_ch0_p),
    .O_tmds_ch1_p   (O_tmds_ch1_p),
    .O_tmds_ch2_p   (O_tmds_ch2_p),
    .O_tmds_clk_p   (O_tmds_clk_p)
);

endmodule
