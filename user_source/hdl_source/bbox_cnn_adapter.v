`timescale 1ns / 1ns

// One pixel mailbox feeds the CNN; the downsampler RAM retains queued crops.
module bbox_cnn_adapter (
    input  wire        I_pixel_clk,
    input  wire        I_cnn_clk,
    input  wire        I_rst_n,
    input  wire        I_video_user,
    input  wire        I_crop_update,
    input  wire [7:0]  I_bbox_valid,
    input  wire [95:0] I_x_min,
    input  wire [95:0] I_x_max,
    input  wire [95:0] I_y_min,
    input  wire [95:0] I_y_max,
    output wire        O_crop_accept,
    output reg         O_batch_busy,
    output reg         O_batch_done,
    input  wire        I_valid,
    output wire        O_ready,
    input  wire [10:0] I_pixel,
    input  wire [9:0]  I_pixel_addr,
    input  wire [2:0]  I_box_index,
    input  wire [2:0]  I_source_slot,
    input  wire [3:0]  I_box_count,
    input  wire        I_batch_done,
    output reg         O_cnn_go,
    output reg         O_cnn_we,
    output reg  [10:0] O_cnn_data,
    output reg  [12:0] O_cnn_addr,
    input  wire        I_cnn_stop,
    input  wire [3:0]  I_cnn_result,
    output reg  [7:0]  O_bbox_valid,
    output reg  [95:0] O_x_min,
    output reg  [95:0] O_x_max,
    output reg  [95:0] O_y_min,
    output reg  [95:0] O_y_max,
    output reg  [7:0]  O_digit_valid,
    output reg  [31:0] O_digits
);
    localparam [2:0] C_ARM   = 3'd0;
    localparam [2:0] C_LOAD  = 3'd1;
    localparam [2:0] C_WRITE = 3'd2;
    localparam [2:0] C_START = 3'd3;
    localparam [2:0] C_RUN   = 3'd4;
    localparam [2:0] C_REPLY = 3'd5;

    reg [1:0] pixel_reset_sync;
    reg [1:0] cnn_reset_sync;
    wire pixel_rst_n = pixel_reset_sync[1];
    wire cnn_rst_n = cnn_reset_sync[1];
    always @(posedge I_pixel_clk or negedge I_rst_n) begin
        if (!I_rst_n) pixel_reset_sync <= 2'b00;
        else pixel_reset_sync <= {pixel_reset_sync[0], 1'b1};
    end
    always @(posedge I_cnn_clk or negedge I_rst_n) begin
        if (!I_rst_n) cnn_reset_sync <= 2'b00;
        else cnn_reset_sync <= {cnn_reset_sync[0], 1'b1};
    end

    // Bundled payloads stay unchanged until the remote clock acknowledges them.
    reg [10:0] pixel_mailbox_data;
    reg [9:0] pixel_mailbox_addr;
    reg pixel_request;
    reg pixel_ack;
    reg pixel_request_sync_1, pixel_request_sync_2;
    reg pixel_ack_sync_1, pixel_ack_sync_2;
    reg [3:0] result_mailbox_data;
    reg result_request;
    reg result_ack;
    reg result_request_sync_1, result_request_sync_2;
    reg result_ack_sync_1, result_ack_sync_2;
    reg [2:0] cnn_state;
    reg stop_was_low;
    reg waiting_result;
    reg completed_batch;
    reg [2:0] active_slot;
    reg active_last_box;
    reg [7:0] batch_bbox_valid;
    reg [95:0] batch_x_min, batch_x_max, batch_y_min, batch_y_max;
    reg [7:0] batch_digit_valid;
    reg [31:0] batch_digits;

    assign O_crop_accept = pixel_rst_n && I_crop_update && !O_batch_busy;
    assign O_ready = pixel_rst_n && O_batch_busy && !completed_batch &&
                     !waiting_result && (pixel_request == pixel_ack_sync_2);

    always @(posedge I_pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            pixel_ack_sync_1 <= 1'b0;
            pixel_ack_sync_2 <= 1'b0;
            result_request_sync_1 <= 1'b0;
            result_request_sync_2 <= 1'b0;
        end else begin
            pixel_ack_sync_1 <= pixel_ack;
            pixel_ack_sync_2 <= pixel_ack_sync_1;
            result_request_sync_1 <= result_request;
            result_request_sync_2 <= result_request_sync_1;
        end
    end

    always @(posedge I_pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            pixel_mailbox_data <= 11'd0;
            pixel_mailbox_addr <= 10'd0;
            pixel_request <= 1'b0;
            result_ack <= 1'b0;
            waiting_result <= 1'b0;
            completed_batch <= 1'b0;
            active_slot <= 3'd0;
            active_last_box <= 1'b0;
            O_batch_busy <= 1'b0;
            O_batch_done <= 1'b0;
            batch_bbox_valid <= 8'd0;
            batch_x_min <= 96'd0;
            batch_x_max <= 96'd0;
            batch_y_min <= 96'd0;
            batch_y_max <= 96'd0;
            batch_digit_valid <= 8'd0;
            batch_digits <= 32'd0;
            O_bbox_valid <= 8'd0;
            O_x_min <= 96'd0;
            O_x_max <= 96'd0;
            O_y_min <= 96'd0;
            O_y_max <= 96'd0;
            O_digit_valid <= 8'd0;
            O_digits <= 32'd0;
        end else begin
            O_batch_done <= 1'b0;
            if (O_crop_accept) begin
                O_batch_busy <= 1'b1;
                completed_batch <= 1'b0;
                batch_bbox_valid <= I_bbox_valid;
                batch_x_min <= I_x_min;
                batch_x_max <= I_x_max;
                batch_y_min <= I_y_min;
                batch_y_max <= I_y_max;
                batch_digit_valid <= 8'd0;
                batch_digits <= 32'd0;
            end

            if (I_valid && O_ready) begin
                pixel_mailbox_data <= I_pixel;
                pixel_mailbox_addr <= I_pixel_addr;
                pixel_request <= ~pixel_request;
                if (I_pixel_addr == 10'd783) begin
                    active_slot <= I_source_slot;
                    active_last_box <= ({1'b0, I_box_index} == I_box_count - 1'b1);
                    waiting_result <= 1'b1;
                end
            end

            if (waiting_result && (result_request_sync_2 != result_ack)) begin
                result_ack <= result_request_sync_2;
                batch_digits[active_slot*4 +: 4] <= result_mailbox_data;
                batch_digit_valid[active_slot] <= (result_mailbox_data <= 4'd9);
                waiting_result <= 1'b0;
                if (active_last_box) completed_batch <= 1'b1;
            end
            if (O_batch_busy && I_batch_done && (batch_bbox_valid == 8'd0))
                completed_batch <= 1'b1;

            // Display the geometry and progressive results together at frame start.
            // Keep the final result visible for a frame before accepting a new batch.
            if (I_video_user) begin
                O_bbox_valid <= batch_bbox_valid;
                O_x_min <= batch_x_min;
                O_x_max <= batch_x_max;
                O_y_min <= batch_y_min;
                O_y_max <= batch_y_max;
                O_digit_valid <= batch_digit_valid;
                O_digits <= batch_digits;
                if (completed_batch) begin
                    O_batch_busy <= 1'b0;
                    completed_batch <= 1'b0;
                    O_batch_done <= 1'b1;
                end
            end
        end
    end

    always @(posedge I_cnn_clk or negedge cnn_rst_n) begin
        if (!cnn_rst_n) begin
            pixel_request_sync_1 <= 1'b0;
            pixel_request_sync_2 <= 1'b0;
            result_ack_sync_1 <= 1'b0;
            result_ack_sync_2 <= 1'b0;
        end else begin
            pixel_request_sync_1 <= pixel_request;
            pixel_request_sync_2 <= pixel_request_sync_1;
            result_ack_sync_1 <= result_ack;
            result_ack_sync_2 <= result_ack_sync_1;
        end
    end

    always @(posedge I_cnn_clk or negedge cnn_rst_n) begin
        if (!cnn_rst_n) begin
            cnn_state <= C_ARM;
            pixel_ack <= 1'b0;
            result_request <= 1'b0;
            result_mailbox_data <= 4'd0;
            stop_was_low <= 1'b0;
            O_cnn_go <= 1'b1;
            O_cnn_we <= 1'b0;
            O_cnn_data <= 11'd0;
            O_cnn_addr <= 13'd0;
        end else begin
            O_cnn_we <= 1'b0;
            case (cnn_state)
                C_ARM: begin
                    O_cnn_go <= 1'b1;
                    cnn_state <= C_LOAD;
                end
                C_LOAD: begin
                    if (pixel_request_sync_2 != pixel_ack) begin
                        O_cnn_data <= pixel_mailbox_data;
                        O_cnn_addr <= {3'd0, pixel_mailbox_addr};
                        O_cnn_we <= 1'b1;
                        cnn_state <= C_WRITE;
                    end
                end
                C_WRITE: begin
                    // TOP writes this edge, before GO is lowered on a later edge.
                    pixel_ack <= pixel_request_sync_2;
                    cnn_state <= (O_cnn_addr == 13'd783) ? C_START : C_LOAD;
                end
                C_START: begin
                    O_cnn_go <= 1'b0;
                    stop_was_low <= !I_cnn_stop;
                    cnn_state <= C_RUN;
                end
                C_RUN: begin
                    if (!I_cnn_stop) stop_was_low <= 1'b1;
                    if (stop_was_low && I_cnn_stop) begin
                        result_mailbox_data <= I_cnn_result;
                        result_request <= ~result_request;
                        cnn_state <= C_REPLY;
                    end
                end
                C_REPLY: begin
                    if (result_ack_sync_2 == result_request) begin
                        O_cnn_go <= 1'b1;
                        cnn_state <= C_ARM;
                    end
                end
                default: cnn_state <= C_ARM;
            endcase
        end
    end
endmodule
