`timescale 1ns / 1ns

module SC500CS_top (
    input  wire        I_ctrl_clk,
    input  wire        I_lp_clk,
    input  wire        I_rst_n,
    input  wire [3:0]  I_key_n,
    input  wire [15:0] I_display_param_a,
    input  wire [15:0] I_display_param_b,

    output wire        O_cam_scl,
    inout  wire        IO_cam_sda,
    output wire        O_cam_24m,
    output wire        O_cam_rst,
    output wire [7:0]  O_DIG,
    output wire [7:0]  O_SEL,

    inout  wire        IO_rx_clk_pad_n,
    inout  wire        IO_rx_clk_pad_p,
    inout  wire [3:0]  IO_rx_data_pad_n,
    inout  wire [3:0]  IO_rx_data_pad_p,

    output wire        O_video_clk,
    output wire [39:0] O_video_tdata,
    output wire        O_video_tlast,
    output wire        O_video_tuser,
    output wire        O_video_tvalid,
    output wire [1:0]  O_lane_error
);

wire [15:0] ae_value;
wire [15:0] ag_value;
wire cam_cfg_done;
wire ae_cfg_done;
wire ae_req;
wire hs_rx_valid;
wire [15:0] hs_rx_data;
wire csi_frame_start;
wire csi_frame_end;
wire csi_valid;
wire [31:0] csi_data;
wire raw10_frame_start;
wire raw10_frame_end;
wire raw10_valid;
wire [39:0] raw10_data;

assign O_cam_rst = 1'b1;
assign O_cam_24m = I_ctrl_clk;

ae_set u_ae_set (
    .I_clk          (I_ctrl_clk),
    .I_rst          (~I_rst_n),
    .I_key_n        (I_key_n),
    .I_cam_cfg_done (cam_cfg_done),
    .I_ae_cfg_done  (ae_cfg_done),
    .O_ae_req       (ae_req),
    .O_ae           (ae_value),
    .O_ag           (ag_value)
);

seg7_scan8 #(
    .SCAN_DIV       (24000),
    .SEG_ACTIVE_LOW (1'b1),
    .SEL_ACTIVE_LOW (1'b1)
) u_seg7_scan8 (
    .I_clk      (I_ctrl_clk),
    .I_rst_n    (I_rst_n),
    .I_param_a  (I_display_param_a),
    .I_param_b  (I_display_param_b),
    .O_DIG      (O_DIG),
    .O_SEL      (O_SEL)
);

uicfgcs500_720p #(
    .CLK_DIV (24000000 / 100000 - 1)
) u_uicfgcs500 (
    .I_clk         (I_ctrl_clk),
    .I_rst_n       (I_rst_n),
    .I_ae_req      (ae_req),
    .I_ae          (ae_value),
    .I_ag          (ag_value),
    .O_cam_scl     (O_cam_scl),
    .IO_cam_sda    (IO_cam_sda),
    .O_cfg_done    (cam_cfg_done),
    .O_ae_cfg_done (ae_cfg_done)
);

mipi_dphy_rx_ph1p_mipiio_wrapper #(
    .DPHY_RX_LOCATION ("DPHY0"),
    .HS_EQUALIZER     ("0dB"),
    .HS_VGA_GAIN      ("8dB"),
    .LANE_NUM         (2),
    .BYTE_NUM         (1)
) u_mipi_dphy_rx_ph1p_mipiio_wrapper (
    .I_lp_clk              (I_lp_clk),
    .I_rst                 (~I_rst_n),
    .I_clk_lane_in_delay   (6'd0),
    .I_data_lane0_in_delay (6'd0),
    .I_data_lane1_in_delay (6'd0),
    .I_data_lane2_in_delay (6'd0),
    .I_data_lane3_in_delay (6'd0),
    .I_lane_invert         (4'b0000),
    .O_hs_rx_clk           (O_video_clk),
    .O_hs_rx_valid         (hs_rx_valid),
    .O_hs_rx_data          (hs_rx_data),
    .O_lp_rx_lane0_p       (),
    .O_lp_rx_lane0_n       (),
    .I_lp_tx_en            (1'b0),
    .I_lp_tx_lane0_p       (1'b1),
    .I_lp_tx_lane0_n       (1'b1),
    .O_lane_match_error    (),
    .O_lane_error          (O_lane_error),
    .IO_rx_clk_pad_n       (IO_rx_clk_pad_n),
    .IO_rx_clk_pad_p       (IO_rx_clk_pad_p),
    .IO_rx_data_pad_n      (IO_rx_data_pad_n),
    .IO_rx_data_pad_p      (IO_rx_data_pad_p)
);

csi_unpacket_2lane u_csi_unpacket (
    .I_clk             (O_video_clk),
    .I_rst_n           (I_rst_n),
    .I_hs_valid        (hs_rx_valid),
    .I_hs_data         (hs_rx_data),
    .O_csi_frame_start (csi_frame_start),
    .O_csi_frame_end   (csi_frame_end),
    .O_csi_valid       (csi_valid),
    .O_csi_data        (csi_data)
);

raw10_unpacket_2lane u_raw10_unpacket (
    .I_clk               (O_video_clk),
    .I_rst_n             (I_rst_n),
    .I_csi_frame_start   (csi_frame_start),
    .I_csi_frame_end     (csi_frame_end),
    .I_csi_valid         (csi_valid),
    .I_csi_data          (csi_data),
    .O_raw10_frame_start (raw10_frame_start),
    .O_raw10_frame_end   (raw10_frame_end),
    .O_raw10_valid       (raw10_valid),
    .O_raw10_data        (raw10_data)
);

uial2axis #(
    .IMG_WIDTH        (1280),
    .IMG_HEIGHT       (720),
    .INPUT_DATA_WIDTH (40)
) u_uial2axis (
    .I_native_clk (O_video_clk),
    .I_rst_n      (I_rst_n),
    .I_data       (raw10_data),
    .I_data_valid (raw10_valid),
    .I_data_start (raw10_frame_start),
    .I_data_end   (raw10_frame_end),
    .axis_tvalid  (O_video_tvalid),
    .axis_tdata   (O_video_tdata),
    .axis_tuser   (O_video_tuser),
    .axis_tlast   (O_video_tlast)
);

endmodule
