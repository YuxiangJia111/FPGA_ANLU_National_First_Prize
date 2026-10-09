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
wire [7:0] bbox_valid;
wire [95:0] bbox_x_min;
wire [95:0] bbox_x_max;
wire [95:0] bbox_y_min;
wire [95:0] bbox_y_max;
wire bbox_frame_valid;
wire downsample_valid;
wire [10:0] downsample_pixel;
wire [9:0] downsample_pixel_addr;
wire [2:0] downsample_box_index;
wire [2:0] downsample_source_slot;
wire [3:0] downsample_box_count;
wire downsample_box_start;
wire downsample_box_end;
wire downsample_batch_done;
wire downsample_ready;
wire cnn_crop_accept;
wire cnn_go;
wire cnn_write;
wire [10:0] cnn_pixel;
wire [12:0] cnn_pixel_addr;
wire cnn_stop;
wire [3:0] cnn_result;
wire [7:0] cnn_bbox_valid;
wire [95:0] cnn_bbox_x_min;
wire [95:0] cnn_bbox_x_max;
wire [95:0] cnn_bbox_y_min;
wire [95:0] cnn_bbox_y_max;
wire [7:0] cnn_digit_valid;
wire [31:0] cnn_digits;
wire [15:0] gray_frame_read_addr;
wire gray_frame_read_bank;
wire [3:0] gray_frame_read_data;
wire crop_frame_valid;
wire crop_frame_bank;
wire crop_source_busy;
wire [7:0] crop_bbox_valid;
wire [95:0] crop_x_min;
wire [95:0] crop_x_max;
wire [95:0] crop_y_min;
wire [95:0] crop_y_max;
wire [3:0] ddr_debug_status;
wire ddr_init_calib_complete;
wire [2:0] image_mode;
wire debug_view;
reg [2:0] image_mode_sync_1;
reg [2:0] image_mode_sync_2;
reg [2:0] debug_box_sync_1;
reg [2:0] debug_box_sync_2;
reg [3:0] downsample_box_count_sync_1;
reg [3:0] downsample_box_count_sync_2;
wire [3:0] control_key_event;
wire [3:0] control_switch_state;
wire [7:0] bbox_luma_threshold_ctrl;
wire [2:0] bbox_connect_gap_ctrl;
reg  [7:0] bbox_luma_threshold_sync_1;
reg  [7:0] bbox_luma_threshold_sync_2;
reg  [2:0] bbox_connect_gap_sync_1;
reg  [2:0] bbox_connect_gap_sync_2;

assign system_rst_n = pll_lock;
assign O_screen_pwm = 1'b1;
assign debug_view = (image_mode_sync_2 == 3'b110);

control_top u_control_top (
    .I_clk          (clk_24m),
    .I_rst_n        (system_rst_n),
    .I_key_n        (I_key),
    .I_switch       (I_sw),
    .O_key_event    (control_key_event),
    .O_switch_state (control_switch_state),
    .O_image_mode   (image_mode),
    .O_bbox_luma_threshold (bbox_luma_threshold_ctrl),
    .O_bbox_connect_gap    (bbox_connect_gap_ctrl)
);

always @(posedge hdmi_pixel_clk or negedge system_rst_n) begin
    if(!system_rst_n) begin
        image_mode_sync_1 <= 3'b001;
        image_mode_sync_2 <= 3'b001;
        debug_box_sync_1  <= 3'd0;
        debug_box_sync_2  <= 3'd0;
        bbox_luma_threshold_sync_1 <= 8'd55;
        bbox_luma_threshold_sync_2 <= 8'd55;
        bbox_connect_gap_sync_1    <= 3'd4;
        bbox_connect_gap_sync_2    <= 3'd4;
    end else begin
        image_mode_sync_1 <= image_mode;
        image_mode_sync_2 <= image_mode_sync_1;
        debug_box_sync_1  <= control_switch_state[2:0];
        debug_box_sync_2  <= debug_box_sync_1;
        bbox_luma_threshold_sync_1 <= bbox_luma_threshold_ctrl;
        bbox_luma_threshold_sync_2 <= bbox_luma_threshold_sync_1;
        bbox_connect_gap_sync_1    <= bbox_connect_gap_ctrl;
        bbox_connect_gap_sync_2    <= bbox_connect_gap_sync_1;
    end
end

always @(posedge clk_24m or negedge system_rst_n) begin
    if(!system_rst_n) begin
        downsample_box_count_sync_1 <= 4'd0;
        downsample_box_count_sync_2 <= 4'd0;
    end else begin
        downsample_box_count_sync_1 <= downsample_box_count;
        downsample_box_count_sync_2 <= downsample_box_count_sync_1;
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
    .I_display_param_a ((image_mode == 3'b110) ?
                        {13'd0, control_switch_state[2:0]} :
                        {8'd0, bbox_luma_threshold_ctrl}),
    .I_display_param_b ((image_mode == 3'b110) ?
                        {12'd0, downsample_box_count_sync_2} :
                        {13'd0, bbox_connect_gap_ctrl}),
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

digit_multi_bbox #(
    .IMG_WIDTH      (1280),
    .IMG_HEIGHT     (720),
    .ROI_X_MIN      (198),
    .ROI_X_MAX      (1022),
    .ROI_Y_MIN      (18),
    .ROI_Y_MAX      (702),
    .LUMA_THRESHOLD (55),
    .SAMPLE_STEP    (3),
    .MAX_BOXES      (8),
    .CONNECT_GAP    (4),
    .MAX_ROW_GAP    (2),
    .MIN_RUN_WIDTH  (1),
    .MIN_BOX_WIDTH  (4),
    .MIN_BOX_HEIGHT (8),
    .MIN_AREA       (8),
    .BOX_MARGIN     (4),
    .USE_GRAY_ERAM_IP (1)
) u_digit_multi_bbox (
    .I_clk                (hdmi_pixel_clk),
    .I_rst_n              (system_rst_n),
    .I_luma               (processed_ycbcr_data[23:16]),
    .I_luma_threshold     (bbox_luma_threshold_sync_2),
    .I_connect_gap        (bbox_connect_gap_sync_2),
    .I_crop_busy          (crop_source_busy),
    .I_gray_read_addr     (gray_frame_read_addr),
    .I_gray_read_bank     (gray_frame_read_bank),
    .O_gray_read_data     (gray_frame_read_data),
    .I_de                 (processed_video_de),
    .I_user               (processed_video_user),
    .I_last               (processed_video_last),
    .O_bbox_valid         (bbox_valid),
    .O_x_min              (bbox_x_min),
    .O_x_max              (bbox_x_max),
    .O_y_min              (bbox_y_min),
    .O_y_max              (bbox_y_max),
    .O_bbox_frame_valid   (bbox_frame_valid),
    .O_crop_frame_valid   (crop_frame_valid),
    .O_crop_bank          (crop_frame_bank),
    .O_crop_bbox_valid    (crop_bbox_valid),
    .O_crop_x_min         (crop_x_min),
    .O_crop_x_max         (crop_x_max),
    .O_crop_y_min         (crop_y_min),
    .O_crop_y_max         (crop_y_max)
);

bbox_gray_downsampler #(
    .ROI_X_MIN   (198),
    .ROI_X_MAX   (1022),
    .ROI_Y_MIN   (18),
    .ROI_Y_MAX   (702),
    .SAMPLE_STEP (3),
    .MAX_BOXES   (8),
    .OUTPUT_SIZE (28),
    .USE_RESULT_ERAM (1)
) u_bbox_gray_downsampler (
    .I_clk          (hdmi_pixel_clk),
    .I_rst_n        (system_rst_n),
    .I_crop_update  (cnn_crop_accept),
    .I_crop_bank    (crop_frame_bank),
    .I_bbox_valid   (crop_bbox_valid),
    .I_x_min        (crop_x_min),
    .I_x_max        (crop_x_max),
    .I_y_min        (crop_y_min),
    .I_y_max        (crop_y_max),
    .I_gray_read_data (gray_frame_read_data),
    .O_gray_read_addr (gray_frame_read_addr),
    .O_gray_read_bank (gray_frame_read_bank),
    .O_crop_busy      (crop_source_busy),
    .I_ready        (downsample_ready),
    .O_valid        (downsample_valid),
    .O_pixel        (downsample_pixel),
    .O_pixel_addr   (downsample_pixel_addr),
    .O_box_index    (downsample_box_index),
    .O_source_slot  (downsample_source_slot),
    .O_box_count    (downsample_box_count),
    .O_box_start    (downsample_box_start),
    .O_box_end      (downsample_box_end),
    .O_batch_done   (downsample_batch_done)
);

bbox_cnn_adapter u_bbox_cnn_adapter (
    .I_pixel_clk    (hdmi_pixel_clk),
    .I_cnn_clk      (clk_24m),
    .I_rst_n        (system_rst_n),
    .I_video_user   (processed_video_user),
    .I_crop_update  (crop_frame_valid),
    .I_bbox_valid   (crop_bbox_valid),
    .I_x_min        (crop_x_min),
    .I_x_max        (crop_x_max),
    .I_y_min        (crop_y_min),
    .I_y_max        (crop_y_max),
    .O_crop_accept  (cnn_crop_accept),
    .O_batch_busy   (),
    .O_batch_done   (),
    .I_valid        (downsample_valid),
    .O_ready        (downsample_ready),
    .I_pixel        (downsample_pixel),
    .I_pixel_addr   (downsample_pixel_addr),
    .I_box_index    (downsample_box_index),
    .I_source_slot  (downsample_source_slot),
    .I_box_count    (downsample_box_count),
    .I_batch_done   (downsample_batch_done),
    .O_cnn_go       (cnn_go),
    .O_cnn_we       (cnn_write),
    .O_cnn_data     (cnn_pixel),
    .O_cnn_addr     (cnn_pixel_addr),
    .I_cnn_stop     (cnn_stop),
    .I_cnn_result   (cnn_result),
    .O_bbox_valid   (cnn_bbox_valid),
    .O_x_min        (cnn_bbox_x_min),
    .O_x_max        (cnn_bbox_x_max),
    .O_y_min        (cnn_bbox_y_min),
    .O_y_max        (cnn_bbox_y_max),
    .O_digit_valid  (cnn_digit_valid),
    .O_digits       (cnn_digits)
);

TOP u_cnn (
    .clk                (clk_24m),
    .GO                 (cnn_go),
    .RESULT             (cnn_result),
    .we_database        (cnn_write),
    .dp_database        (cnn_pixel),
    .address_p_database (cnn_pixel_addr),
    .STOP               (cnn_stop)
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
    .I_bbox_valid   (cnn_bbox_valid),
    .I_bbox_x_min   (cnn_bbox_x_min),
    .I_bbox_x_max   (cnn_bbox_x_max),
    .I_bbox_y_min   (cnn_bbox_y_min),
    .I_bbox_y_max   (cnn_bbox_y_max),
    .I_bbox_digit_valid (cnn_digit_valid),
    .I_bbox_digits      (cnn_digits),
    .I_debug_view   (debug_view),
    .I_debug_box    (debug_box_sync_2),
    .I_downsample_valid      (downsample_valid && downsample_ready),
    .I_downsample_pixel      (downsample_pixel),
    .I_downsample_pixel_addr (downsample_pixel_addr),
    .I_downsample_box_index  (downsample_box_index),
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
