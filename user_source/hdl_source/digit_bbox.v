`timescale 1ns / 1ns

// Locates a dark digit on a bright background using downsampled projections.
module digit_bbox #(
    parameter integer IMG_WIDTH          = 1280,
    parameter integer IMG_HEIGHT         = 720,
    parameter integer ROI_X_MIN          = 198,
    parameter integer ROI_X_MAX          = 1022,
    parameter integer ROI_Y_MIN          = 18,
    parameter integer ROI_Y_MAX          = 702,
    parameter integer LUMA_THRESHOLD     = 35,
    parameter integer MIN_BOX_WIDTH      = 4,
    parameter integer MIN_BOX_HEIGHT     = 8,
    parameter integer BOX_MARGIN         = 4
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [23:0] I_rgb,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    output reg  [11:0] O_x_min,
    output reg  [11:0] O_x_max,
    output reg  [11:0] O_y_min,
    output reg  [11:0] O_y_max,
    output reg         O_bbox_valid
);

localparam integer SAMPLE_STEP = 3;
localparam integer COL_SAMPLES = ((ROI_X_MAX - ROI_X_MIN) / SAMPLE_STEP) + 1;
localparam integer ROW_SAMPLES = ((ROI_Y_MAX - ROI_Y_MIN) / SAMPLE_STEP) + 1;
localparam integer LUMA_LIMIT  = LUMA_THRESHOLD << 8;
localparam [12:0] IMG_WIDTH_13  = IMG_WIDTH;
localparam [11:0] IMG_HEIGHT_12 = IMG_HEIGHT;
localparam [12:0] ROI_X_MIN_13  = ROI_X_MIN;
localparam [11:0] ROI_Y_MIN_12  = ROI_Y_MIN;
localparam [12:0] BOX_MARGIN_13 = BOX_MARGIN;
localparam [11:0] BOX_MARGIN_12 = BOX_MARGIN;

localparam [3:0] ST_CLEAR_COL = 4'd0;
localparam [3:0] ST_CLEAR_ROW = 4'd1;
localparam [3:0] ST_WAIT_FRAME = 4'd2;
localparam [3:0] ST_CAPTURE = 4'd3;
localparam [3:0] ST_SCAN_COL = 4'd4;
localparam [3:0] ST_SCAN_ROW = 4'd5;
localparam [3:0] ST_PUBLISH = 4'd6;

reg [3:0] state;
reg [11:0] pixel_x;
reg [11:0] pixel_y;
reg [1:0] x_phase;
reg [1:0] y_phase;
reg [8:0] sample_col;
reg [7:0] sample_row;

reg col_hit [0:COL_SAMPLES-1];
reg row_hit [0:ROW_SAMPLES-1];
reg [8:0] scan_col;
reg [7:0] scan_row;
reg [8:0] first_col;
reg [8:0] last_col;
reg [7:0] first_row;
reg [7:0] last_row;
reg [8:0] col_run_start;
reg [8:0] col_best_length;
reg [7:0] row_run_start;
reg [7:0] row_best_length;
reg       col_run_active;
reg       row_run_active;
reg       col_found;
reg       row_found;
reg [1:0] miss_count;

wire [7:0] red   = I_rgb[23:16];
wire [7:0] green = I_rgb[15:8];
wire [7:0] blue  = I_rgb[7:0];
wire [16:0] red_ext   = {9'd0, red};
wire [16:0] green_ext = {9'd0, green};
wire [16:0] blue_ext  = {9'd0, blue};

// 77R + 150G + 29B is 256 times the standard luma approximation.
wire [16:0] luma_sum =
    (red_ext << 6) + (red_ext << 3) + (red_ext << 2) + red_ext +
    (green_ext << 7) + (green_ext << 4) + (green_ext << 2) + (green_ext << 1) +
    (blue_ext << 4) + (blue_ext << 3) + (blue_ext << 2) + blue_ext;
wire pixel_is_dark = luma_sum <= LUMA_LIMIT;

wire [12:0] first_col_scaled = ({4'd0, first_col} << 1) + {4'd0, first_col};
wire [12:0] last_col_scaled  = ({4'd0, last_col} << 1) + {4'd0, last_col};
wire [11:0] first_row_scaled = ({4'd0, first_row} << 1) + {4'd0, first_row};
wire [11:0] last_row_scaled  = ({4'd0, last_row} << 1) + {4'd0, last_row};
wire [12:0] detected_x_min = ROI_X_MIN_13 + first_col_scaled;
wire [12:0] detected_x_max = ROI_X_MIN_13 + last_col_scaled + BOX_MARGIN_13;
wire [11:0] detected_y_min = ROI_Y_MIN_12 + first_row_scaled;
wire [11:0] detected_y_max = ROI_Y_MIN_12 + last_row_scaled + BOX_MARGIN_12;
wire [12:0] padded_x_min = detected_x_min - BOX_MARGIN_13;
wire [11:0] padded_y_min = detected_y_min - BOX_MARGIN_12;
wire geometry_valid = col_found && row_found &&
                      (col_best_length >= MIN_BOX_WIDTH) &&
                      (row_best_length >= MIN_BOX_HEIGHT);

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        state                 <= ST_CLEAR_COL;
        pixel_x               <= 12'd0;
        pixel_y               <= 12'd0;
        x_phase               <= 2'd0;
        y_phase               <= 2'd0;
        sample_col            <= 9'd0;
        sample_row            <= 8'd0;
        scan_col              <= 9'd0;
        scan_row              <= 8'd0;
        first_col             <= 9'd0;
        last_col              <= 9'd0;
        first_row             <= 8'd0;
        last_row              <= 8'd0;
        col_run_start         <= 9'd0;
        col_best_length       <= 9'd0;
        row_run_start         <= 8'd0;
        row_best_length       <= 8'd0;
        col_run_active        <= 1'b0;
        row_run_active        <= 1'b0;
        col_found             <= 1'b0;
        row_found             <= 1'b0;
        miss_count            <= 2'd0;
        O_x_min               <= 12'd0;
        O_x_max               <= 12'd0;
        O_y_min               <= 12'd0;
        O_y_max               <= 12'd0;
        O_bbox_valid          <= 1'b0;
    end else begin
        case (state)
            ST_CLEAR_COL: begin
                col_hit[scan_col] <= 1'b0;
                if (scan_col == COL_SAMPLES - 1) begin
                    scan_col <= 9'd0;
                    scan_row <= 8'd0;
                    state    <= ST_CLEAR_ROW;
                end else begin
                    scan_col <= scan_col + 1'b1;
                end
            end

            ST_CLEAR_ROW: begin
                row_hit[scan_row] <= 1'b0;
                if (scan_row == ROW_SAMPLES - 1) begin
                    scan_row <= 8'd0;
                    state    <= ST_WAIT_FRAME;
                end else begin
                    scan_row <= scan_row + 1'b1;
                end
            end

            ST_WAIT_FRAME: begin
                if (I_user) begin
                    pixel_x               <= 12'd0;
                    pixel_y               <= 12'd0;
                    x_phase               <= 2'd0;
                    y_phase               <= 2'd0;
                    sample_col            <= 9'd0;
                    sample_row            <= 8'd0;
                    state                 <= ST_CAPTURE;
                end
            end

            ST_CAPTURE: begin
                if (I_de) begin
                    if ((pixel_x >= ROI_X_MIN) && (pixel_x <= ROI_X_MAX) &&
                        (pixel_y >= ROI_Y_MIN) && (pixel_y <= ROI_Y_MAX)) begin
                        if ((x_phase == 2'd0) && (y_phase == 2'd0) && pixel_is_dark) begin
                            col_hit[sample_col] <= 1'b1;
                            row_hit[sample_row] <= 1'b1;
                        end

                        if (x_phase == SAMPLE_STEP - 1) begin
                            x_phase <= 2'd0;
                            if (sample_col != COL_SAMPLES - 1)
                                sample_col <= sample_col + 1'b1;
                        end else begin
                            x_phase <= x_phase + 1'b1;
                        end
                    end

                    if (I_last) begin
                        pixel_x    <= 12'd0;
                        x_phase    <= 2'd0;
                        sample_col <= 9'd0;

                        if (pixel_y == IMG_HEIGHT - 1) begin
                            scan_col        <= 9'd0;
                            first_col       <= 9'd0;
                            last_col        <= 9'd0;
                            col_run_start   <= 9'd0;
                            col_best_length <= 9'd0;
                            col_run_active  <= 1'b0;
                            col_found       <= 1'b0;
                            row_found       <= 1'b0;
                            state           <= ST_SCAN_COL;
                        end else begin
                            pixel_y <= pixel_y + 1'b1;
                            if ((pixel_y >= ROI_Y_MIN) && (pixel_y < ROI_Y_MAX)) begin
                                if (y_phase == SAMPLE_STEP - 1) begin
                                    y_phase <= 2'd0;
                                    if (sample_row != ROW_SAMPLES - 1)
                                        sample_row <= sample_row + 1'b1;
                                end else begin
                                    y_phase <= y_phase + 1'b1;
                                end
                            end
                        end
                    end else begin
                        pixel_x <= pixel_x + 1'b1;
                    end
                end
            end

            ST_SCAN_COL: begin
                if (col_hit[scan_col]) begin
                    if (!col_run_active) begin
                        col_run_start  <= scan_col;
                        col_run_active <= 1'b1;
                    end
                end else if (col_run_active) begin
                    if ((scan_col - col_run_start) > col_best_length) begin
                        first_col       <= col_run_start;
                        last_col        <= scan_col - 1'b1;
                        col_best_length <= scan_col - col_run_start;
                    end
                    col_run_active <= 1'b0;
                    col_found      <= 1'b1;
                end

                if (scan_col == COL_SAMPLES - 1) begin
                    if (col_hit[scan_col]) begin
                        if (!col_run_active) begin
                            if (col_best_length < 9'd1) begin
                                first_col       <= scan_col;
                                last_col        <= scan_col;
                                col_best_length <= 9'd1;
                            end
                        end else if ((scan_col - col_run_start + 1'b1) > col_best_length) begin
                            first_col       <= col_run_start;
                            last_col        <= scan_col;
                            col_best_length <= scan_col - col_run_start + 1'b1;
                        end
                        col_found <= 1'b1;
                    end

                    scan_row        <= 8'd0;
                    first_row       <= 8'd0;
                    last_row        <= 8'd0;
                    row_run_start   <= 8'd0;
                    row_best_length <= 8'd0;
                    row_run_active  <= 1'b0;
                    state           <= ST_SCAN_ROW;
                end else begin
                    scan_col <= scan_col + 1'b1;
                end
            end

            ST_SCAN_ROW: begin
                if (row_hit[scan_row]) begin
                    if (!row_run_active) begin
                        row_run_start  <= scan_row;
                        row_run_active <= 1'b1;
                    end
                end else if (row_run_active) begin
                    if ((scan_row - row_run_start) > row_best_length) begin
                        first_row       <= row_run_start;
                        last_row        <= scan_row - 1'b1;
                        row_best_length <= scan_row - row_run_start;
                    end
                    row_run_active <= 1'b0;
                    row_found      <= 1'b1;
                end

                if (scan_row == ROW_SAMPLES - 1) begin
                    if (row_hit[scan_row]) begin
                        if (!row_run_active) begin
                            if (row_best_length < 8'd1) begin
                                first_row       <= scan_row;
                                last_row        <= scan_row;
                                row_best_length <= 8'd1;
                            end
                        end else if ((scan_row - row_run_start + 1'b1) > row_best_length) begin
                            first_row       <= row_run_start;
                            last_row        <= scan_row;
                            row_best_length <= scan_row - row_run_start + 1'b1;
                        end
                        row_found <= 1'b1;
                    end
                    state <= ST_PUBLISH;
                end else begin
                    scan_row <= scan_row + 1'b1;
                end
            end

            ST_PUBLISH: begin
                if (geometry_valid) begin
                    O_x_min <= (detected_x_min > BOX_MARGIN_13) ?
                               padded_x_min[11:0] : 12'd0;
                    O_x_max <= (detected_x_max < IMG_WIDTH_13) ?
                               detected_x_max[11:0] : IMG_WIDTH_13[11:0] - 1'b1;
                    O_y_min <= (detected_y_min > BOX_MARGIN_12) ?
                               padded_y_min : 12'd0;
                    O_y_max <= (detected_y_max < IMG_HEIGHT_12) ?
                               detected_y_max : IMG_HEIGHT_12 - 1'b1;
                    O_bbox_valid <= 1'b1;
                    miss_count   <= 2'd0;
                end else if (miss_count == 2'd2) begin
                    O_bbox_valid <= 1'b0;
                end else begin
                    miss_count <= miss_count + 1'b1;
                end

                scan_col <= 9'd0;
                state    <= ST_CLEAR_COL;
            end

            default: begin
                scan_col <= 9'd0;
                state    <= ST_CLEAR_COL;
            end
        endcase
    end
end

endmodule
