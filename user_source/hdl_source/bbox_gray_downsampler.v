`timescale 1ns / 1ns

// Sorts detector boxes, expands each crop to a square in the detector's
// same-frame sampled grayscale image, stores 28x28 crops, then streams them.
module bbox_gray_downsampler #(
    parameter integer ROI_X_MIN       = 198,
    parameter integer ROI_X_MAX       = 1022,
    parameter integer ROI_Y_MIN       = 18,
    parameter integer ROI_Y_MAX       = 702,
    parameter integer SAMPLE_STEP     = 3,
    parameter integer MAX_BOXES       = 8,
    parameter integer OUTPUT_SIZE     = 28,
    parameter integer USE_RESULT_ERAM = 1
) (
    input  wire                         I_clk,
    input  wire                         I_rst_n,
    input  wire                         I_crop_update,
    input  wire                         I_crop_bank,
    input  wire [MAX_BOXES-1:0]         I_bbox_valid,
    input  wire [MAX_BOXES*12-1:0]      I_x_min,
    input  wire [MAX_BOXES*12-1:0]      I_x_max,
    input  wire [MAX_BOXES*12-1:0]      I_y_min,
    input  wire [MAX_BOXES*12-1:0]      I_y_max,
    input  wire [3:0]                   I_gray_read_data,
    output reg  [15:0]                  O_gray_read_addr,
    output reg                          O_gray_read_bank,
    output wire                         O_crop_busy,
    input  wire                         I_ready,
    output reg                          O_valid,
    output reg  [10:0]                  O_pixel,
    output reg  [9:0]                   O_pixel_addr,
    output reg  [2:0]                   O_box_index,
    output reg  [2:0]                   O_source_slot,
    output reg  [3:0]                   O_box_count,
    output reg                          O_box_start,
    output reg                          O_box_end,
    output reg                          O_batch_done
);

    localparam integer COL_SAMPLES = ((ROI_X_MAX - ROI_X_MIN) / SAMPLE_STEP) + 1;
    localparam integer ROW_SAMPLES = ((ROI_Y_MAX - ROI_Y_MIN) / SAMPLE_STEP) + 1;
    localparam integer PIXELS_PER_BOX = OUTPUT_SIZE * OUTPUT_SIZE;
    localparam integer MAP_DENOM = 2 * OUTPUT_SIZE;
    localparam integer MAP_REM_W = (MAP_DENOM <= 2) ? 1 : $clog2(MAP_DENOM);
    localparam integer MAX_MAP_SIDE = (COL_SAMPLES < ROW_SAMPLES) ? COL_SAMPLES : ROW_SAMPLES;
    localparam integer MAX_MAP_QUOTIENT =
        ((2 * MAX_MAP_SIDE) + MAP_DENOM - 1) / MAP_DENOM;
    localparam integer MAP_DIV_W = (COL_W + 1) + MAP_REM_W;
    localparam integer BOX_INDEX_W = (MAX_BOXES <= 2) ? 1 : $clog2(MAX_BOXES);
    localparam integer COL_W = (COL_SAMPLES <= 2) ? 1 : $clog2(COL_SAMPLES);
    localparam integer ROW_W = (ROW_SAMPLES <= 2) ? 1 : $clog2(ROW_SAMPLES);

    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_SORT       = 4'd1;
    localparam [3:0] ST_COUNT      = 4'd2;
    localparam [3:0] ST_PREP_BOX   = 4'd3;
    localparam [3:0] ST_CROP_REQ   = 4'd4;
    localparam [3:0] ST_CROP_WAIT  = 4'd5;
    localparam [3:0] ST_READ_REQ   = 4'd6;
    localparam [3:0] ST_READ_WAIT  = 4'd7;
    localparam [3:0] ST_HOLD       = 4'd8;
    localparam [3:0] ST_PREP_GEOMETRY = 4'd9;
    localparam [3:0] ST_PREP_ORIGIN   = 4'd10;

    // Constant-denominator quotient/remainder without a divider or reciprocal
    // multiplier. The loop bounds are parameters, so synthesis unrolls only
    // comparisons and constant subtracts.
    function [MAP_DIV_W-1:0] F_map_div;
        input [COL_W+2:0] numerator;
        integer k;
        reg [COL_W:0] quotient;
        reg [COL_W+2:0] remainder;
        begin
            quotient = 0;
            remainder = numerator;
            for(k = 0; k <= MAX_MAP_QUOTIENT; k = k + 1) begin
                if(numerator >= (k * MAP_DENOM)) begin
                    quotient = k;
                    remainder = numerator - (k * MAP_DENOM);
                end
            end
            F_map_div = {quotient, remainder[MAP_REM_W-1:0]};
        end
    endfunction

    reg [3:0] state;
    reg [BOX_INDEX_W-1:0] sort_pass;
    reg [BOX_INDEX_W-1:0] sort_index;
    reg [BOX_INDEX_W-1:0] box_index;
    reg [BOX_INDEX_W:0] count_index;
    reg [BOX_INDEX_W:0] box_count;
    reg [9:0] crop_pixel_addr;
    reg [4:0] crop_x_pos;
    reg crop_bank;
    reg [2:0] source_slot [0:MAX_BOXES-1];
    reg box_valid [0:MAX_BOXES-1];
    reg [11:0] box_x_min [0:MAX_BOXES-1];
    reg [11:0] box_x_max [0:MAX_BOXES-1];
    reg [11:0] box_y_min [0:MAX_BOXES-1];
    reg [11:0] box_y_max [0:MAX_BOXES-1];
    reg [COL_W-1:0] square_x_min [0:MAX_BOXES-1];
    reg [ROW_W-1:0] square_y_min [0:MAX_BOXES-1];
    reg [COL_W:0] square_side [0:MAX_BOXES-1];
    reg [COL_W-1:0] prep_x_min;
    reg [COL_W-1:0] prep_x_max;
    reg [ROW_W-1:0] prep_y_min;
    reg [ROW_W-1:0] prep_y_max;
    reg [COL_W:0] prep_side;
    reg [COL_W-1:0] prep_center_x;
    reg [ROW_W-1:0] prep_center_y;
    reg [COL_W:0] map_start_value;
    reg [MAP_REM_W-1:0] map_start_remainder;
    reg [COL_W:0] map_x_value;
    reg [ROW_W:0] map_y_value;
    reg [MAP_REM_W-1:0] map_x_remainder;
    reg [MAP_REM_W-1:0] map_y_remainder;

    reg [7:0] result_write_data;
    reg [12:0] result_write_addr;
    reg result_write_enable;
    wire [12:0] result_read_addr = (O_box_index * PIXELS_PER_BOX) + O_pixel_addr;
    wire [7:0] result_read_data;

    integer i;
    integer x0;
    integer x1;
    integer y0;
    integer y1;
    integer width_samples;
    integer height_samples;
    integer side_samples;
    integer center_x;
    integer center_y;
    integer crop_x;
    integer crop_y;
    reg [COL_W-1:0] sample_x;
    reg [ROW_W-1:0] sample_y;
    integer swap_valid;
    integer swap_x_min;
    integer swap_x_max;
    integer swap_y_min;
    integer swap_y_max;
    integer swap_slot;

    wire [7:0] gray4_to_result = {I_gray_read_data, I_gray_read_data};
    wire [12:0] crop_result_addr = (box_index * PIXELS_PER_BOX) + crop_pixel_addr;
    wire [COL_W+2:0] map_step_sum =
        ((crop_x_pos == OUTPUT_SIZE - 1) ? map_y_remainder : map_x_remainder) +
        (square_side[box_index] << 1);
    wire [MAP_DIV_W-1:0] map_step_div = F_map_div(map_step_sum);
    wire [MAP_DIV_W-1:0] map_initial_div =
        F_map_div({{2{1'b0}}, prep_side});
    wire [COL_W:0] map_step_delta = map_step_div[MAP_DIV_W-1:MAP_REM_W];
    wire [MAP_REM_W-1:0] map_step_remainder = map_step_div[MAP_REM_W-1:0];
    wire [COL_W:0] map_initial_value =
        map_initial_div[MAP_DIV_W-1:MAP_REM_W];
    wire [MAP_REM_W-1:0] map_initial_remainder =
        map_initial_div[MAP_REM_W-1:0];
    wire [15:0] sample_y_extended = {{(16-ROW_W){1'b0}}, sample_y};
    wire [15:0] sample_x_extended = {{(16-COL_W){1'b0}}, sample_x};
    wire [15:0] sample_row_base = (sample_y_extended << 8) +
                                         (sample_y_extended << 4) +
                                         (sample_y_extended << 1) +
                                          sample_y_extended;
    assign O_crop_busy = ((state >= ST_SORT) && (state <= ST_CROP_WAIT)) ||
                         (state == ST_PREP_GEOMETRY) || (state == ST_PREP_ORIGIN);

    bbox_gray_result_ram_adapter #(
        .USE_ERAM_IP (USE_RESULT_ERAM)
    ) u_result_ram (
        .I_clk        (I_clk),
        .I_write_data (result_write_data),
        .I_write_addr (result_write_addr),
        .I_write_en   (result_write_enable),
        .I_read_addr  (result_read_addr),
        .O_read_data  (result_read_data)
    );

    always @(*) begin
        result_write_enable = (state == ST_CROP_WAIT);
        result_write_addr = crop_result_addr;
        result_write_data = gray4_to_result;
        sample_x = 0;
        sample_y = 0;

        if ((state == ST_CROP_REQ) && (box_index < box_count)) begin
            sample_x = square_x_min[box_index] + map_x_value;
            sample_y = square_y_min[box_index] + map_y_value;
            O_gray_read_addr = sample_row_base + sample_x_extended;
        end else begin
            O_gray_read_addr = 16'd0;
        end
        O_gray_read_bank = crop_bank;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state          <= ST_IDLE;
            sort_pass      <= {BOX_INDEX_W{1'b0}};
            sort_index     <= {BOX_INDEX_W{1'b0}};
            box_index      <= {BOX_INDEX_W{1'b0}};
            count_index    <= {(BOX_INDEX_W+1){1'b0}};
            box_count      <= {(BOX_INDEX_W+1){1'b0}};
            crop_pixel_addr <= 10'd0;
            crop_x_pos      <= 5'd0;
            crop_bank      <= 1'b0;
            prep_x_min     <= 0;
            prep_x_max     <= 0;
            prep_y_min     <= 0;
            prep_y_max     <= 0;
            prep_side      <= 1;
            prep_center_x  <= 0;
            prep_center_y  <= 0;
            map_start_value <= 0;
            map_start_remainder <= 0;
            map_x_value <= 0;
            map_y_value <= 0;
            map_x_remainder <= 0;
            map_y_remainder <= 0;
            O_valid        <= 1'b0;
            O_pixel        <= 11'd0;
            O_pixel_addr   <= 10'd0;
            O_box_index    <= 3'd0;
            O_source_slot  <= 3'd0;
            O_box_count    <= 4'd0;
            O_box_start    <= 1'b0;
            O_box_end      <= 1'b0;
            O_batch_done   <= 1'b0;
            for (i = 0; i < MAX_BOXES; i = i + 1) begin
                box_valid[i] <= 1'b0;
                box_x_min[i] <= 12'd0;
                box_x_max[i] <= 12'd0;
                box_y_min[i] <= 12'd0;
                box_y_max[i] <= 12'd0;
                source_slot[i] <= 3'd0;
                square_x_min[i] <= 9'd0;
                square_y_min[i] <= 8'd0;
                square_side[i] <= 8'd1;
            end
        end else begin
            O_batch_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    O_valid <= 1'b0;
                    if (I_crop_update) begin
                        crop_bank <= I_crop_bank;
                        sort_pass <= {BOX_INDEX_W{1'b0}};
                        sort_index <= {BOX_INDEX_W{1'b0}};
                        state <= ST_SORT;
                        for (i = 0; i < MAX_BOXES; i = i + 1) begin
                            box_valid[i] <= I_bbox_valid[i];
                            box_x_min[i] <= I_x_min[i*12 +: 12];
                            box_x_max[i] <= I_x_max[i*12 +: 12];
                            box_y_min[i] <= I_y_min[i*12 +: 12];
                            box_y_max[i] <= I_y_max[i*12 +: 12];
                            source_slot[i] <= i;
                        end
                    end
                end

                ST_SORT: begin
                    if ((!box_valid[sort_index] && box_valid[sort_index + 1'b1]) ||
                        (box_valid[sort_index] && box_valid[sort_index + 1'b1] &&
                         ((box_x_min[sort_index] > box_x_min[sort_index + 1'b1]) ||
                          ((box_x_min[sort_index] == box_x_min[sort_index + 1'b1]) &&
                           (box_y_min[sort_index] > box_y_min[sort_index + 1'b1]))))) begin
                        swap_valid = box_valid[sort_index];
                        swap_x_min = box_x_min[sort_index];
                        swap_x_max = box_x_max[sort_index];
                        swap_y_min = box_y_min[sort_index];
                        swap_y_max = box_y_max[sort_index];
                        swap_slot = source_slot[sort_index];
                        box_valid[sort_index] <= box_valid[sort_index + 1'b1];
                        box_x_min[sort_index] <= box_x_min[sort_index + 1'b1];
                        box_x_max[sort_index] <= box_x_max[sort_index + 1'b1];
                        box_y_min[sort_index] <= box_y_min[sort_index + 1'b1];
                        box_y_max[sort_index] <= box_y_max[sort_index + 1'b1];
                        source_slot[sort_index] <= source_slot[sort_index + 1'b1];
                        box_valid[sort_index + 1'b1] <= swap_valid;
                        box_x_min[sort_index + 1'b1] <= swap_x_min;
                        box_x_max[sort_index + 1'b1] <= swap_x_max;
                        box_y_min[sort_index + 1'b1] <= swap_y_min;
                        box_y_max[sort_index + 1'b1] <= swap_y_max;
                        source_slot[sort_index + 1'b1] <= swap_slot;
                    end

                    if (sort_index == MAX_BOXES - 2) begin
                        sort_index <= {BOX_INDEX_W{1'b0}};
                        if (sort_pass == MAX_BOXES - 2) begin
                            count_index <= {(BOX_INDEX_W+1){1'b0}};
                            box_count <= {(BOX_INDEX_W+1){1'b0}};
                            state <= ST_COUNT;
                        end else begin
                            sort_pass <= sort_pass + 1'b1;
                        end
                    end else begin
                        sort_index <= sort_index + 1'b1;
                    end
                end

                ST_COUNT: begin
                    if (box_valid[count_index])
                        box_count <= box_count + 1'b1;
                    if (count_index == MAX_BOXES - 1) begin
                        O_box_count <= box_count + (box_valid[count_index] ? 1'b1 : 1'b0);
                        if ((box_count + (box_valid[count_index] ? 1'b1 : 1'b0)) == 0) begin
                            O_batch_done <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            box_count <= box_count + (box_valid[count_index] ? 1'b1 : 1'b0);
                            box_index <= {BOX_INDEX_W{1'b0}};
                            state <= ST_PREP_BOX;
                        end
                    end else begin
                        count_index <= count_index + 1'b1;
                    end
                end

                ST_PREP_BOX: begin
                    x0 = (box_x_min[box_index] <= ROI_X_MIN) ? 0 :
                         (box_x_min[box_index] - ROI_X_MIN + SAMPLE_STEP/2) / SAMPLE_STEP;
                    x1 = (box_x_max[box_index] <= ROI_X_MIN) ? 0 :
                         (box_x_max[box_index] - ROI_X_MIN + SAMPLE_STEP/2) / SAMPLE_STEP;
                    y0 = (box_y_min[box_index] <= ROI_Y_MIN) ? 0 :
                         (box_y_min[box_index] - ROI_Y_MIN + SAMPLE_STEP/2) / SAMPLE_STEP;
                    y1 = (box_y_max[box_index] <= ROI_Y_MIN) ? 0 :
                         (box_y_max[box_index] - ROI_Y_MIN + SAMPLE_STEP/2) / SAMPLE_STEP;
                    if (x0 >= COL_SAMPLES) x0 = COL_SAMPLES - 1;
                    if (x1 >= COL_SAMPLES) x1 = COL_SAMPLES - 1;
                    if (y0 >= ROW_SAMPLES) y0 = ROW_SAMPLES - 1;
                    if (y1 >= ROW_SAMPLES) y1 = ROW_SAMPLES - 1;
                    // Break the ROI conversion/division path before geometry.
                    prep_x_min <= x0;
                    prep_x_max <= x1;
                    prep_y_min <= y0;
                    prep_y_max <= y1;
                    state <= ST_PREP_GEOMETRY;
                end

                ST_PREP_GEOMETRY: begin
                    x0 = prep_x_min;
                    x1 = prep_x_max;
                    y0 = prep_y_min;
                    y1 = prep_y_max;
                    width_samples = x1 - x0 + 1;
                    height_samples = y1 - y0 + 1;
                    side_samples = (width_samples > height_samples) ?
                                   width_samples : height_samples;
                    if (side_samples > ROW_SAMPLES)
                        side_samples = ROW_SAMPLES;
                    if (side_samples > COL_SAMPLES)
                        side_samples = COL_SAMPLES;
                    center_x = (x0 + x1) / 2;
                    center_y = (y0 + y1) / 2;
                    prep_side <= side_samples;
                    prep_center_x <= center_x;
                    prep_center_y <= center_y;
                    state <= ST_PREP_ORIGIN;
                end

                ST_PREP_ORIGIN: begin
                    side_samples = prep_side;
                    center_x = prep_center_x;
                    center_y = prep_center_y;
                    crop_x = center_x - ((side_samples - 1) / 2);
                    crop_y = center_y - ((side_samples - 1) / 2);
                    if (crop_x < 0) crop_x = 0;
                    if (crop_y < 0) crop_y = 0;
                    if (crop_x + side_samples > COL_SAMPLES)
                        crop_x = COL_SAMPLES - side_samples;
                    if (crop_y + side_samples > ROW_SAMPLES)
                        crop_y = ROW_SAMPLES - side_samples;
                    square_x_min[box_index] <= crop_x;
                    square_y_min[box_index] <= crop_y;
                    square_side[box_index] <= side_samples;
                    crop_pixel_addr <= 10'd0;
                    crop_x_pos <= 5'd0;
                    map_start_value <= map_initial_value;
                    map_start_remainder <= map_initial_remainder;
                    map_x_value <= map_initial_value;
                    map_y_value <= map_initial_value;
                    map_x_remainder <= map_initial_remainder;
                    map_y_remainder <= map_initial_remainder;
                    state <= ST_CROP_REQ;
                end

                ST_CROP_REQ: state <= ST_CROP_WAIT;

                ST_CROP_WAIT: begin
                    if (crop_pixel_addr == PIXELS_PER_BOX - 1) begin
                        if (box_index == box_count - 1'b1) begin
                            O_box_index <= {BOX_INDEX_W{1'b0}};
                            O_pixel_addr <= 10'd0;
                            state <= ST_READ_REQ;
                        end else begin
                            box_index <= box_index + 1'b1;
                            state <= ST_PREP_BOX;
                        end
                    end else begin
                        crop_pixel_addr <= crop_pixel_addr + 1'b1;
                        if (crop_x_pos == OUTPUT_SIZE - 1) begin
                            crop_x_pos <= 5'd0;
                            map_x_value <= map_start_value;
                            map_x_remainder <= map_start_remainder;
                            map_y_value <= map_y_value + map_step_delta;
                            map_y_remainder <= map_step_remainder;
                        end else begin
                            crop_x_pos <= crop_x_pos + 1'b1;
                            map_x_value <= map_x_value + map_step_delta;
                            map_x_remainder <= map_step_remainder;
                        end
                        state <= ST_CROP_REQ;
                    end
                end

                ST_READ_REQ: begin
                    state <= ST_READ_WAIT;
                end

                ST_READ_WAIT: begin
                    O_pixel <= {1'b0, result_read_data[7:0], 2'b00};
                    O_valid <= 1'b1;
                    O_box_start <= (O_pixel_addr == 0);
                    O_box_end <= (O_pixel_addr == PIXELS_PER_BOX - 1);
                    O_source_slot <= source_slot[O_box_index];
                    state <= ST_HOLD;
                end

                ST_HOLD: begin
                    if (O_valid && I_ready) begin
                        O_valid <= 1'b0;
                        if (O_pixel_addr == PIXELS_PER_BOX - 1) begin
                            if (O_box_index == box_count - 1'b1) begin
                                O_batch_done <= 1'b1;
                                state <= ST_IDLE;
                            end else begin
                                O_box_index <= O_box_index + 1'b1;
                                O_pixel_addr <= 10'd0;
                                state <= ST_READ_REQ;
                            end
                        end else begin
                            O_pixel_addr <= O_pixel_addr + 1'b1;
                            state <= ST_READ_REQ;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

module bbox_gray_result_ram_adapter #(
    parameter integer USE_ERAM_IP = 1
) (
    input  wire        I_clk,
    input  wire [7:0]  I_write_data,
    input  wire [12:0] I_write_addr,
    input  wire        I_write_en,
    input  wire [12:0] I_read_addr,
    output wire [7:0]  O_read_data
);
    generate
        if (USE_ERAM_IP) begin : g_eram
            bbox_gray_result_ram_ip u_ram (
                .dia   (I_write_data),
                .addra (I_write_addr),
                .wea   (I_write_en),
                .clka  (I_clk),
                .dob   (O_read_data),
                .addrb (I_read_addr)
            );
        end else begin : g_model
            reg [7:0] memory [0:8191];
            reg [7:0] read_data;
            always @(posedge I_clk) begin
                if (I_write_en)
                    memory[I_write_addr] <= I_write_data;
                read_data <= memory[I_read_addr];
            end
            assign O_read_data = read_data;
        end
    endgenerate
endmodule
