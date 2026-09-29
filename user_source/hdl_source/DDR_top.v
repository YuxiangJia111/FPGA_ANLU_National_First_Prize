`timescale 1ns / 1ns

module DDR_top (
    input  wire         I_sys_clk,
    input  wire         I_rst_n,
    input  wire         I_camera_clk,
    input  wire         I_camera_frame_start,
    input  wire         I_camera_valid,
    input  wire [127:0] I_camera_data,
    input  wire         I_mipi_rx_error,
    input  wire         I_display_clk,
    input  wire         I_display_vsync,
    input  wire         I_display_rd_en,
    output wire [23:0]  O_display_data,
    output wire [3:0]   O_debug_status,
    output wire         O_init_calib_complete,

    output wire [12:0]  ddr_addr,
    output wire [1:0]   ddr_ba,
    output wire [0:0]   ddr_cke,
    output wire [0:0]   ddr_odt,
    output wire [0:0]   ddr_cs_n,
    output wire         ddr_ras_n,
    output wire         ddr_cas_n,
    output wire         ddr_we_n,
    output wire [0:0]   ddr_ck_p,
    output wire [0:0]   ddr_ck_n,
    inout  wire [1:0]   ddr_dm,
    inout  wire [15:0]  ddr_dq,
    inout  wire [1:0]   ddr_dqs_p,
    inout  wire [1:0]   ddr_dqs_n
);

wire ddr_clk;
wire video_out_rd_busy;
wire video_in_wr_busy;
wire [1:0] video_out_rp;
wire ddr_user_wr_en;
wire ddr_user_rd_en;
wire [24:0] ddr_user_addr;
wire [127:0] ddr_user_wr_data;
wire ddr_user_ready;
wire ddr_user_rd_valid;
wire [127:0] ddr_user_rd_data;
wire vi_ddr_wr_en;
wire [24:0] vi_ddr_wr_addr;
wire [127:0] vi_ddr_wr_data;
wire vo_ddr_rd_en;
wire [24:0] vo_ddr_rd_addr;
wire [24:0] mc_app_addr;
wire [2:0] mc_app_cmd;
wire mc_app_en;
wire [127:0] mc_app_wdf_data;
wire mc_app_wdf_end;
wire [15:0] mc_app_wdf_mask;
wire mc_app_wdf_wren;
wire [127:0] mc_app_rd_data;
wire mc_app_rd_data_end;
wire mc_app_rd_data_valid;
wire mc_app_rdy;
wire mc_app_wdf_rdy;

assign ddr_user_wr_en = vi_ddr_wr_en;
assign ddr_user_rd_en = vo_ddr_rd_en;
assign ddr_user_addr = vi_ddr_wr_en ? vi_ddr_wr_addr :
                       vo_ddr_rd_en ? vo_ddr_rd_addr : 25'd0;
assign ddr_user_wr_data = vi_ddr_wr_data;
assign O_debug_status = {
    (|ddr_user_rd_data),
    ddr_user_rd_valid,
    vo_ddr_rd_en,
    vi_ddr_wr_en
};

video_in u_video_in (
    .I_rst_n              (I_rst_n),
    .I_camera_clk         (I_camera_clk),
    .I_camera_frame_start (I_camera_frame_start),
    .I_camera_valid       (I_camera_valid),
    .I_camera_data        (I_camera_data),
    .I_mipi_rx_error      (I_mipi_rx_error),
    .I_ddr_clk            (ddr_clk),
    .I_display_pause      (1'b0),
    .I_video_out_rd_busy  (video_out_rd_busy),
    .O_video_in_wr_busy   (video_in_wr_busy),
    .O_video_out_rp       (video_out_rp),
    .O_ddr_user_wr_en     (vi_ddr_wr_en),
    .O_ddr_user_addr      (vi_ddr_wr_addr),
    .O_ddr_user_wr_data   (vi_ddr_wr_data),
    .I_ddr_user_ready     (ddr_user_ready)
);

video_out u_video_out (
    .I_rst_n             (I_rst_n),
    .I_ddr_clk           (ddr_clk),
    .O_video_out_rd_busy (video_out_rd_busy),
    .I_video_in_wr_busy  (video_in_wr_busy),
    .I_video_out_rp      (video_out_rp),
    .O_ddr_user_rd_en    (vo_ddr_rd_en),
    .O_ddr_user_addr     (vo_ddr_rd_addr),
    .I_ddr_user_ready    (ddr_user_ready),
    .I_ddr_user_rd_valid (ddr_user_rd_valid),
    .I_ddr_user_rd_data  (ddr_user_rd_data),
    .I_dsi_clk           (I_display_clk),
    .I_video_vsync       (I_display_vsync),
    .I_video_rd_en       (I_display_rd_en),
    .O_vdieo_data        (O_display_data)
);

mc_to_user_interface u_mc_to_user_interface (
    .I_clk                  (ddr_clk),
    .I_rst_n                (I_rst_n),
    .I_ddr_user_wr_en       (ddr_user_wr_en),
    .I_ddr_user_rd_en       (ddr_user_rd_en),
    .I_ddr_user_addr        (ddr_user_addr),
    .I_ddr_user_wr_data     (ddr_user_wr_data),
    .O_ddr_user_ready       (ddr_user_ready),
    .O_ddr_user_rd_valid    (ddr_user_rd_valid),
    .O_ddr_user_rd_data     (ddr_user_rd_data),
    .O_mc_app_en            (mc_app_en),
    .O_mc_app_addr          (mc_app_addr),
    .O_mc_app_cmd           (mc_app_cmd),
    .I_mc_app_rdy           (mc_app_rdy),
    .O_mc_app_wdf_wren      (mc_app_wdf_wren),
    .O_mc_app_wdf_data      (mc_app_wdf_data),
    .O_mc_app_wdf_end       (mc_app_wdf_end),
    .O_mc_app_wdf_mask      (mc_app_wdf_mask),
    .I_mc_app_wdf_rdy       (mc_app_wdf_rdy),
    .I_mc_app_rd_data       (mc_app_rd_data),
    .I_mc_app_rd_data_end   (mc_app_rd_data_end),
    .I_mc_app_rd_data_valid (mc_app_rd_data_valid)
);

ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper (
    .I_sys_clk              (I_sys_clk),
    .I_sys_rst_n            (I_rst_n),
    .O_ddr_clk              (ddr_clk),
    .O_init_calib_complete  (O_init_calib_complete),
    .I_mc_app_addr          (mc_app_addr),
    .I_mc_app_cmd           (mc_app_cmd),
    .I_mc_app_en            (mc_app_en),
    .I_mc_app_wdf_data      (mc_app_wdf_data),
    .I_mc_app_wdf_end       (mc_app_wdf_end),
    .I_mc_app_wdf_mask      (mc_app_wdf_mask),
    .I_mc_app_wdf_wren      (mc_app_wdf_wren),
    .O_mc_app_rd_data       (mc_app_rd_data),
    .O_mc_app_rd_data_end   (mc_app_rd_data_end),
    .O_mc_app_rd_data_valid (mc_app_rd_data_valid),
    .O_mc_app_rdy           (mc_app_rdy),
    .O_mc_app_wdf_rdy       (mc_app_wdf_rdy),
    .ddr_addr               (ddr_addr),
    .ddr_ba                 (ddr_ba),
    .ddr_cke                (ddr_cke),
    .ddr_odt                (ddr_odt),
    .ddr_cs_n               (ddr_cs_n),
    .ddr_ras_n              (ddr_ras_n),
    .ddr_cas_n              (ddr_cas_n),
    .ddr_we_n               (ddr_we_n),
    .ddr_ck_p               (ddr_ck_p),
    .ddr_ck_n               (ddr_ck_n),
    .ddr_dm                 (ddr_dm),
    .ddr_dq                 (ddr_dq),
    .ddr_dqs_p              (ddr_dqs_p),
    .ddr_dqs_n              (ddr_dqs_n)
);

endmodule
