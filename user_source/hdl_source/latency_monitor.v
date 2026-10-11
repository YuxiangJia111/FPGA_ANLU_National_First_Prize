module latency_monitor (
    input  wire        I_rst_n,
    input  wire        I_sys_clk,
    input  wire        I_camera_clk,
    input  wire        I_camera_frame_start,
    input  wire        I_hdmi_clk,
    input  wire        I_hdmi_frame_start,
    input  wire        I_cnn_start,
    input  wire        I_cnn_done,
    output reg [31:0]  O_camera_latency_us,
    output reg         O_camera_latency_valid,
    output reg [31:0]  O_cnn_latency_us,
    output reg         O_cnn_latency_valid
);
    reg [5:0]  sys_us_divider;
    reg [31:0] sys_time_us;
    wire [31:0] sys_time_gray = sys_time_us ^ (sys_time_us >> 1);

    reg [31:0] camera_time_gray_1d;
    reg [31:0] camera_time_gray_2d;
    reg        camera_start_1d;
    reg [31:0] camera_timestamp;
    reg        camera_timestamp_toggle;

    reg [31:0] hdmi_time_gray_1d;
    reg [31:0] hdmi_time_gray_2d;
    wire [31:0] hdmi_time_us = gray_to_binary(hdmi_time_gray_2d);

    reg [31:0] camera_timestamp_hdmi_1d;
    reg [31:0] camera_timestamp_hdmi_2d;
    reg        camera_toggle_hdmi_1d;
    reg        camera_toggle_hdmi_2d;
    reg        camera_toggle_hdmi_seen;
    reg [31:0] camera_timestamp_latched;
    reg        camera_timestamp_valid;

    reg [31:0] cnn_start_timestamp;
    reg        cnn_measure_active;

    function [31:0] gray_to_binary;
        input [31:0] gray;
        integer i;
        begin
            gray_to_binary[31] = gray[31];
            for(i = 30; i >= 0; i = i - 1)
                gray_to_binary[i] = gray_to_binary[i + 1] ^ gray[i];
        end
    endfunction

    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            sys_us_divider <= 6'd0;
            sys_time_us <= 32'd0;
        end else if(sys_us_divider == 6'd49) begin
            sys_us_divider <= 6'd0;
            sys_time_us <= sys_time_us + 32'd1;
        end else begin
            sys_us_divider <= sys_us_divider + 6'd1;
        end
    end

    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            camera_time_gray_1d <= 32'd0;
            camera_time_gray_2d <= 32'd0;
            camera_start_1d <= 1'b0;
            camera_timestamp <= 32'd0;
            camera_timestamp_toggle <= 1'b0;
        end else begin
            camera_time_gray_1d <= sys_time_gray;
            camera_time_gray_2d <= camera_time_gray_1d;
            camera_start_1d <= I_camera_frame_start;
            if(I_camera_frame_start && !camera_start_1d) begin
                camera_timestamp <= gray_to_binary(camera_time_gray_2d);
                camera_timestamp_toggle <= ~camera_timestamp_toggle;
            end
        end
    end

    always @(posedge I_hdmi_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            hdmi_time_gray_1d <= 32'd0;
            hdmi_time_gray_2d <= 32'd0;
            camera_timestamp_hdmi_1d <= 32'd0;
            camera_timestamp_hdmi_2d <= 32'd0;
            camera_toggle_hdmi_1d <= 1'b0;
            camera_toggle_hdmi_2d <= 1'b0;
            camera_toggle_hdmi_seen <= 1'b0;
            camera_timestamp_latched <= 32'd0;
            camera_timestamp_valid <= 1'b0;
            cnn_start_timestamp <= 32'd0;
            cnn_measure_active <= 1'b0;
            O_camera_latency_us <= 32'd0;
            O_camera_latency_valid <= 1'b0;
            O_cnn_latency_us <= 32'd0;
            O_cnn_latency_valid <= 1'b0;
        end else begin
            hdmi_time_gray_1d <= sys_time_gray;
            hdmi_time_gray_2d <= hdmi_time_gray_1d;
            camera_timestamp_hdmi_1d <= camera_timestamp;
            camera_timestamp_hdmi_2d <= camera_timestamp_hdmi_1d;
            camera_toggle_hdmi_1d <= camera_timestamp_toggle;
            camera_toggle_hdmi_2d <= camera_toggle_hdmi_1d;

            if(camera_toggle_hdmi_2d != camera_toggle_hdmi_seen) begin
                camera_toggle_hdmi_seen <= camera_toggle_hdmi_2d;
                camera_timestamp_latched <= camera_timestamp_hdmi_2d;
                camera_timestamp_valid <= 1'b1;
            end

            if(I_hdmi_frame_start && camera_timestamp_valid) begin
                O_camera_latency_us <= hdmi_time_us - camera_timestamp_latched;
                O_camera_latency_valid <= 1'b1;
            end

            if(I_cnn_start) begin
                cnn_start_timestamp <= hdmi_time_us;
                cnn_measure_active <= 1'b1;
            end
            if(I_cnn_done && cnn_measure_active) begin
                O_cnn_latency_us <= hdmi_time_us - cnn_start_timestamp;
                O_cnn_latency_valid <= 1'b1;
                cnn_measure_active <= 1'b0;
            end
        end
    end
endmodule
