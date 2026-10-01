`timescale 1ns / 1ns

// Adapts the current 1280x720 RGB888 display stream to the imported CNN.
module cnn_inference_top (
    input  wire        I_pixel_clk,
    input  wire        I_rst_n,
    input  wire [23:0] I_rgb,
    input  wire        I_de,
    output reg  [3:0]  O_result,
    output reg         O_result_valid
);

wire [15:0] rgb565;
wire [15:0] resized_data;
wire        cnn_clk;
wire        resize_active;
wire [11:0] resize_x;
wire [11:0] resize_y;

reg         preprocess_start;
wire        preprocess_done;
wire [10:0] preprocess_data;
wire [4:0]  preprocess_x;
wire [4:0]  preprocess_y;
wire        preprocess_write;
wire [12:0] preprocess_address;

reg         cnn_go;
wire [3:0]  cnn_result;
wire        cnn_done;

reg  [9:0] sample_x;
reg  [9:0] sample_y;
reg        capture_active;
reg        rearm_capture;
reg        first_frame;

assign rgb565 = {I_rgb[23:19], I_rgb[15:10], I_rgb[7:3]};
assign preprocess_address = preprocess_y * 13'd28 + preprocess_x;

resolution u_resolution (
    .hdmi_clk    (I_pixel_clk),
    .rst_n       (I_rst_n),
    .rd_data     (rgb565),
    .hdmi_rd_en  (I_de),
    .data_out    (resized_data),
    .gray_clk    (cnn_clk),
    .reso_en     (resize_active),
    .x_t_img     (resize_x),
    .y_t_img     (resize_y)
);

pre_v2 u_preprocess (
    .clk         (cnn_clk),
    .rst_n       (I_rst_n),
    .start       (preprocess_start),
    .data        (resized_data),
    .end_pre     (preprocess_done),
    .output_data (preprocess_data),
    .cnn_end     (cnn_done),
    .x           (sample_x),
    .y           (sample_y),
    .i           (preprocess_x),
    .j           (preprocess_y),
    .data_req    (preprocess_write)
);

TOP u_cnn (
    .clk                (cnn_clk),
    .GO                 (cnn_go),
    .RESULT             (cnn_result),
    .we_database        (preprocess_write),
    .dp_database        (preprocess_data),
    .address_p_database (preprocess_address),
    .STOP               (cnn_done)
);

// Arm capture at the first complete display frame after reset or inference.
always @(posedge I_pixel_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        capture_active <= 1'b0;
        rearm_capture  <= 1'b0;
        first_frame    <= 1'b1;
    end else begin
        if (cnn_done || first_frame) begin
            rearm_capture <= 1'b1;
            first_frame   <= 1'b0;
        end

        if (rearm_capture && (resize_x == 12'd0) && (resize_y == 12'd0)) begin
            capture_active <= 1'b1;
            rearm_capture  <= 1'b0;
        end

        if (preprocess_done)
            capture_active <= 1'b0;
    end
end

// Preserve the source design's 320x240 sampling coordinates and trigger point.
always @(posedge cnn_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        sample_x         <= 10'd0;
        sample_y         <= 10'd0;
        preprocess_start <= 1'b0;
    end else if (capture_active) begin
        if (resize_active) begin
            if (sample_x == 10'd319) begin
                sample_x <= 10'd0;
                if (sample_y == 10'd239)
                    sample_y <= 10'd0;
                else
                    sample_y <= sample_y + 1'b1;
            end else begin
                sample_x <= sample_x + 1'b1;
            end
        end

        if (cnn_go && (sample_x == 10'd47) && (sample_y == 10'd7))
            preprocess_start <= 1'b1;

        if (preprocess_done) begin
            preprocess_start <= 1'b0;
            sample_x         <= 10'd0;
            sample_y         <= 10'd0;
        end
    end
end

// GO is high while a new image is being collected and low during inference.
always @(posedge cnn_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        cnn_go         <= 1'b1;
        O_result       <= 4'hf;
        O_result_valid <= 1'b0;
    end else begin
        if (preprocess_done) begin
            cnn_go         <= 1'b0;
            O_result_valid <= 1'b0;
        end

        if (cnn_done) begin
            cnn_go         <= 1'b1;
            O_result       <= cnn_result;
            O_result_valid <= 1'b1;
        end
    end
end

endmodule
