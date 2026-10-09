`timescale 1ns / 1ns

// Multi-object detector for separated dark digits on a bright background.
// The input frame is reduced to a binary 3x3-sampled bitmap.  A run-based
// connected-component pass then tracks independent objects without stopping
// the live video stream.
module digit_multi_bbox #(
    parameter integer IMG_WIDTH       = 1280,
    parameter integer IMG_HEIGHT      = 720,
    parameter integer ROI_X_MIN       = 198,
    parameter integer ROI_X_MAX       = 1022,
    parameter integer ROI_Y_MIN       = 18,
    parameter integer ROI_Y_MAX       = 702,
    parameter integer LUMA_THRESHOLD  = 35,
    parameter integer SAMPLE_STEP     = 3,
    parameter integer MAX_BOXES        = 8,
    parameter integer CONNECT_GAP      = 1,
    parameter integer MAX_ROW_GAP      = 1,
    parameter integer MIN_RUN_WIDTH    = 2,
    parameter integer MIN_BOX_WIDTH    = 4,
    parameter integer MIN_BOX_HEIGHT   = 8,
    parameter integer MIN_AREA         = 8,
    parameter integer BOX_MARGIN       = 4,
    parameter integer USE_GRAY_ERAM_IP = 0
) (
    input  wire                         I_clk,
    input  wire                         I_rst_n,
    input  wire [7:0]                    I_luma,
    input  wire [7:0]                    I_luma_threshold,
    input  wire [2:0]                    I_connect_gap,
    input  wire                          I_crop_busy,
    input  wire [15:0]                   I_gray_read_addr,
    input  wire                          I_gray_read_bank,
    output wire [3:0]                    O_gray_read_data,
    input  wire                         I_de,
    input  wire                         I_user,
    input  wire                         I_last,
    output reg  [MAX_BOXES-1:0]         O_bbox_valid,
    output reg  [MAX_BOXES*12-1:0]      O_x_min,
    output reg  [MAX_BOXES*12-1:0]      O_x_max,
    output reg  [MAX_BOXES*12-1:0]      O_y_min,
    output reg  [MAX_BOXES*12-1:0]      O_y_max,
    output reg                          O_bbox_frame_valid,
    output reg                          O_crop_frame_valid,
    output reg                          O_crop_bank,
    output wire [MAX_BOXES-1:0]         O_crop_bbox_valid,
    output wire [MAX_BOXES*12-1:0]      O_crop_x_min,
    output wire [MAX_BOXES*12-1:0]      O_crop_x_max,
    output wire [MAX_BOXES*12-1:0]      O_crop_y_min,
    output wire [MAX_BOXES*12-1:0]      O_crop_y_max
);

    localparam integer COL_SAMPLES = ((ROI_X_MAX - ROI_X_MIN) / SAMPLE_STEP) + 1;
    localparam integer ROW_SAMPLES = ((ROI_Y_MAX - ROI_Y_MIN) / SAMPLE_STEP) + 1;
    localparam integer BITMAP_SIZE = COL_SAMPLES * ROW_SAMPLES;
    localparam integer COL_W = (COL_SAMPLES <= 2) ? 1 : $clog2(COL_SAMPLES);
    localparam integer ROW_W = (ROW_SAMPLES <= 2) ? 1 : $clog2(ROW_SAMPLES);
    localparam integer BOX_W = (MAX_BOXES <= 2) ? 1 : $clog2(MAX_BOXES);
    localparam integer ADDR_W = (BITMAP_SIZE <= 2) ? 1 : $clog2(BITMAP_SIZE);
    localparam integer WORD_COUNT = (BITMAP_SIZE + 31) / 32;
    localparam integer LAST_WORD_BITS = BITMAP_SIZE - ((WORD_COUNT - 1) * 32);
    localparam integer MIN_COL_SAMPLES = (MIN_BOX_WIDTH + SAMPLE_STEP - 1) / SAMPLE_STEP;
    localparam integer MIN_ROW_SAMPLES = (MIN_BOX_HEIGHT + SAMPLE_STEP - 1) / SAMPLE_STEP;

    localparam [3:0] ST_CLEAR = 4'd0;
    localparam [3:0] ST_WAIT  = 4'd1;
    localparam [3:0] ST_CAP   = 4'd2;

    localparam [3:0] PR_IDLE      = 4'd0;
    localparam [3:0] PR_CLEAR     = 4'd1;
    localparam [3:0] PR_SCAN      = 4'd2;
    localparam [3:0] PR_MATCH     = 4'd3;
    localparam [3:0] PR_FINISH    = 4'd4;
    localparam [3:0] PR_AGE       = 4'd5;
    localparam [3:0] PR_PUBLISH   = 4'd6;
    localparam [3:0] PR_WORD_WAIT = 4'd7;

    reg write_bank;
    reg process_bank;
    reg frame_seen;
    reg process_start;

    reg [3:0] capture_state;
    reg [11:0] pixel_x;
    reg [11:0] pixel_y;
    reg [1:0] x_phase;
    reg [1:0] y_phase;
    reg [COL_W-1:0] sample_col;
    reg [ROW_W-1:0] sample_row;
    reg [ADDR_W-1:0] capture_addr;
    reg [31:0] capture_word;
    reg [4:0] capture_bit;
    reg [10:0] capture_word_addr;
    reg [31:0] bitmap_write_data;
    reg [10:0] bitmap_write_addr;
    reg bitmap_write_enable;
    reg bitmap_write_bank;
    reg [3:0] gray_write_data;
    reg [15:0] gray_write_addr;
    reg gray_write_enable;
    reg gray_write_bank;

    reg [3:0] process_state;
    reg [ROW_W-1:0] process_row;
    reg [COL_W-1:0] process_col;
    reg [ADDR_W-1:0] process_addr;
    reg [COL_W-1:0] pending_run_start;
    reg [COL_W-1:0] pending_run_end;
    reg run_active;
    reg [COL_W-1:0] run_start;
    reg [COL_W-1:0] run_end;
    reg after_match_row_end;
    reg [BOX_W-1:0] process_box;
    reg [BOX_W-1:0] match_box;
    reg match_found;

    reg component_live [0:MAX_BOXES-1];
    reg component_done [0:MAX_BOXES-1];
    reg component_seen [0:MAX_BOXES-1];
    reg [COL_W-1:0] component_x_min [0:MAX_BOXES-1];
    reg [COL_W-1:0] component_x_max [0:MAX_BOXES-1];
    reg [ROW_W-1:0] component_y_min [0:MAX_BOXES-1];
    reg [ROW_W-1:0] component_y_max [0:MAX_BOXES-1];
    reg [15:0] component_area [0:MAX_BOXES-1];
    reg [2:0] component_age [0:MAX_BOXES-1];
    reg [MAX_BOXES-1:0] pending_bbox_valid;
    reg [MAX_BOXES*12-1:0] pending_x_min;
    reg [MAX_BOXES*12-1:0] pending_x_max;
    reg [MAX_BOXES*12-1:0] pending_y_min;
    reg [MAX_BOXES*12-1:0] pending_y_max;
    reg result_toggle;
    reg result_seen;

    integer i;
    integer area_value;
    integer free_box;

    wire pixel_is_dark = I_luma <= I_luma_threshold;

    wire [31:0] bitmap0_read_data;
    wire [31:0] bitmap1_read_data;
    wire [15:0] process_addr_ext = {{(16-ADDR_W){1'b0}}, process_addr};
    wire [10:0] bitmap_read_addr = process_addr_ext[15:5];
    wire [31:0] selected_bitmap_word = process_bank ? bitmap1_read_data : bitmap0_read_data;
    wire process_pixel = selected_bitmap_word[process_addr[4:0]];
    wire [31:0] capture_word_next = {pixel_is_dark, capture_word[31:1]};
    assign O_crop_bbox_valid = pending_bbox_valid;
    assign O_crop_x_min = pending_x_min;
    assign O_crop_x_max = pending_x_max;
    assign O_crop_y_min = pending_y_min;
    assign O_crop_y_max = pending_y_max;

    wire [3:0] gray_bank0_read_data;
    wire [3:0] gray_bank1_read_data;
    assign O_gray_read_data = I_gray_read_bank ? gray_bank1_read_data : gray_bank0_read_data;

    bbox_bitmap_ram u_bbox_bitmap_bank0 (
        .dia   (bitmap_write_data),
        .addra (bitmap_write_addr),
        .wea   (bitmap_write_enable && !bitmap_write_bank),
        .clka  (I_clk),
        .dob   (bitmap0_read_data),
        .addrb (bitmap_read_addr)
    );

    bbox_bitmap_ram u_bbox_bitmap_bank1 (
        .dia   (bitmap_write_data),
        .addra (bitmap_write_addr),
        .wea   (bitmap_write_enable && bitmap_write_bank),
        .clka  (I_clk),
        .dob   (bitmap1_read_data),
        .addrb (bitmap_read_addr)
    );

    bbox_gray_frame_ram_adapter #(
        .USE_ERAM_IP (USE_GRAY_ERAM_IP)
    ) u_bbox_gray_bank0 (
        .I_clk        (I_clk),
        .I_write_data (gray_write_data),
        .I_write_addr (gray_write_addr),
        .I_write_en   (gray_write_enable && !gray_write_bank),
        .I_read_addr  (I_gray_read_addr),
        .O_read_data  (gray_bank0_read_data)
    );

    bbox_gray_frame_ram_adapter #(
        .USE_ERAM_IP (USE_GRAY_ERAM_IP)
    ) u_bbox_gray_bank1 (
        .I_clk        (I_clk),
        .I_write_data (gray_write_data),
        .I_write_addr (gray_write_addr),
        .I_write_en   (gray_write_enable && gray_write_bank),
        .I_read_addr  (I_gray_read_addr),
        .O_read_data  (gray_bank1_read_data)
    );

    function integer F_scale_sample;
        input integer I_sample;
        integer scale_i;
        begin
            F_scale_sample = 0;
            for (scale_i = 0; scale_i < SAMPLE_STEP; scale_i = scale_i + 1)
                F_scale_sample = F_scale_sample + I_sample;
        end
    endfunction

    function [11:0] F_x_min;
        input [COL_W-1:0] I_sample;
        integer v;
        begin
            v = ROI_X_MIN + F_scale_sample(I_sample) - BOX_MARGIN;
            if (v < 0) v = 0;
            F_x_min = v[11:0];
        end
    endfunction

    function [11:0] F_x_max;
        input [COL_W-1:0] I_sample;
        integer v;
        begin
            v = ROI_X_MIN + F_scale_sample(I_sample) + SAMPLE_STEP - 1 + BOX_MARGIN;
            if (v >= IMG_WIDTH) v = IMG_WIDTH - 1;
            F_x_max = v[11:0];
        end
    endfunction

    function [11:0] F_y_min;
        input [ROW_W-1:0] I_sample;
        integer v;
        begin
            v = ROI_Y_MIN + F_scale_sample(I_sample) - BOX_MARGIN;
            if (v < 0) v = 0;
            F_y_min = v[11:0];
        end
    endfunction

    function [11:0] F_y_max;
        input [ROW_W-1:0] I_sample;
        integer v;
        begin
            v = ROI_Y_MIN + F_scale_sample(I_sample) + SAMPLE_STEP - 1 + BOX_MARGIN;
            if (v >= IMG_HEIGHT) v = IMG_HEIGHT - 1;
            F_y_max = v[11:0];
        end
    endfunction

    // Capture always runs at the video rate. The processing pass reads the
    // other bitmap bank, so component analysis cannot introduce video gaps.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            write_bank    <= 1'b0;
            process_bank  <= 1'b0;
            frame_seen    <= 1'b0;
            capture_state <= ST_CLEAR;
            pixel_x       <= 12'd0;
            pixel_y       <= 12'd0;
            x_phase       <= 2'd0;
            y_phase       <= 2'd0;
            sample_col    <= {COL_W{1'b0}};
            sample_row    <= {ROW_W{1'b0}};
            capture_addr  <= {ADDR_W{1'b0}};
            capture_word  <= 32'd0;
            capture_bit   <= 5'd0;
            capture_word_addr <= 11'd0;
            bitmap_write_data <= 32'd0;
            bitmap_write_addr <= 11'd0;
            bitmap_write_enable <= 1'b0;
            bitmap_write_bank <= 1'b0;
            gray_write_data <= 4'd0;
            gray_write_addr <= 16'd0;
            gray_write_enable <= 1'b0;
            gray_write_bank <= 1'b0;
            process_start <= 1'b0;
        end else begin
            process_start <= 1'b0;
            bitmap_write_enable <= 1'b0;
            gray_write_enable <= 1'b0;
            case (capture_state)
                ST_CLEAR: begin
                    capture_state <= ST_WAIT;
                end

                ST_WAIT: begin
                    if (I_user) begin
                        pixel_x       <= 12'd0;
                        pixel_y       <= 12'd0;
                        x_phase       <= 2'd0;
                        y_phase       <= 2'd0;
                        sample_col    <= {COL_W{1'b0}};
                        sample_row    <= {ROW_W{1'b0}};
                        capture_addr  <= {ADDR_W{1'b0}};
                        capture_word  <= 32'd0;
                        capture_bit   <= 5'd0;
                        capture_word_addr <= 11'd0;
                        capture_state <= ST_CAP;
                    end
                end

                ST_CAP: begin
                    if (I_de) begin
                        if ((pixel_x >= ROI_X_MIN) && (pixel_x <= ROI_X_MAX) &&
                            (pixel_y >= ROI_Y_MIN) && (pixel_y <= ROI_Y_MAX)) begin
                            if ((x_phase == 2'd0) && (y_phase == 2'd0)) begin
                                gray_write_data <= I_luma[7:4];
                                gray_write_addr <= capture_addr;
                                gray_write_enable <= 1'b1;
                                gray_write_bank <= write_bank;
                                if ((capture_bit == 5'd31) ||
                                    (capture_addr == BITMAP_SIZE - 1)) begin
                                    if (capture_bit == 5'd31)
                                        bitmap_write_data <= capture_word_next;
                                    else
                                        bitmap_write_data <= capture_word_next >> (32 - LAST_WORD_BITS);
                                    bitmap_write_addr <= capture_word_addr;
                                    bitmap_write_enable <= 1'b1;
                                    bitmap_write_bank <= write_bank;
                                    capture_word <= 32'd0;
                                    capture_bit <= 5'd0;
                                    if (capture_word_addr != 11'd2047)
                                        capture_word_addr <= capture_word_addr + 1'b1;
                                end else begin
                                    capture_word <= capture_word_next;
                                    capture_bit <= capture_bit + 1'b1;
                                end
                                capture_addr <= capture_addr + 1'b1;

                                if (sample_col != COL_SAMPLES - 1)
                                    sample_col <= sample_col + 1'b1;
                            end

                            if (x_phase == SAMPLE_STEP - 1)
                                x_phase <= 2'd0;
                            else
                                x_phase <= x_phase + 1'b1;
                        end

                        if (I_last) begin
                            pixel_x    <= 12'd0;
                            x_phase    <= 2'd0;
                            sample_col <= {COL_W{1'b0}};

                            if ((pixel_y >= ROI_Y_MIN) && (pixel_y < ROI_Y_MAX)) begin
                                if (y_phase == SAMPLE_STEP - 1) begin
                                    y_phase <= 2'd0;
                                    if (sample_row != ROW_SAMPLES - 1)
                                        sample_row <= sample_row + 1'b1;
                                end else begin
                                    y_phase <= y_phase + 1'b1;
                                end
                            end

                            if (pixel_y == IMG_HEIGHT - 1) begin
                                if (frame_seen && !I_crop_busy &&
                                    (process_state == PR_IDLE)) begin
                                    process_bank <= write_bank;
                                    process_start <= 1'b1;
                                end
                                frame_seen <= 1'b1;
                                // Reuse the capture bank when its peer is still
                                // owned by analysis/cropping; never overwrite it.
                                if (!I_crop_busy && (process_state == PR_IDLE))
                                    write_bank <= ~write_bank;
                                capture_state <= ST_WAIT;
                            end else begin
                                pixel_y <= pixel_y + 1'b1;
                            end
                        end else begin
                            pixel_x <= pixel_x + 1'b1;
                        end
                    end
                end

                default: capture_state <= ST_CLEAR;
            endcase
        end
    end

    // The component pass runs from the completed frame buffer. Components
    // remain live while they are connected to the current row; after the
    // configured row gap they become completed results.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            process_state        <= PR_IDLE;
            process_row          <= {ROW_W{1'b0}};
            process_col          <= {COL_W{1'b0}};
            process_addr         <= {ADDR_W{1'b0}};
            pending_run_start    <= {COL_W{1'b0}};
            pending_run_end      <= {COL_W{1'b0}};
            run_active            <= 1'b0;
            run_start             <= {COL_W{1'b0}};
            run_end               <= {COL_W{1'b0}};
            after_match_row_end   <= 1'b0;
            process_box           <= {BOX_W{1'b0}};
            match_box             <= {BOX_W{1'b0}};
            match_found           <= 1'b0;
            pending_bbox_valid    <= {MAX_BOXES{1'b0}};
            pending_x_min         <= {(MAX_BOXES*12){1'b0}};
            pending_x_max         <= {(MAX_BOXES*12){1'b0}};
            pending_y_min         <= {(MAX_BOXES*12){1'b0}};
            pending_y_max         <= {(MAX_BOXES*12){1'b0}};
            result_toggle         <= 1'b0;
            O_crop_frame_valid   <= 1'b0;
            O_crop_bank          <= 1'b0;
            for (i = 0; i < MAX_BOXES; i = i + 1) begin
                component_live[i] <= 1'b0;
                component_done[i] <= 1'b0;
                component_seen[i] <= 1'b0;
                component_x_min[i] <= {COL_W{1'b0}};
                component_x_max[i] <= {COL_W{1'b0}};
                component_y_min[i] <= {ROW_W{1'b0}};
                component_y_max[i] <= {ROW_W{1'b0}};
                component_area[i] <= 16'd0;
                component_age[i] <= 3'd0;
            end
        end else begin
            O_crop_frame_valid <= (process_state == PR_PUBLISH);
            if (process_state == PR_PUBLISH)
                O_crop_bank <= process_bank;
            case (process_state)
                PR_IDLE: begin
                    if (process_start) begin
                        process_box   <= {BOX_W{1'b0}};
                        process_row   <= {ROW_W{1'b0}};
                        process_col   <= {COL_W{1'b0}};
                        process_addr  <= {ADDR_W{1'b0}};
                        process_state <= PR_CLEAR;
                    end
                end

                PR_CLEAR: begin
                    component_live[process_box] <= 1'b0;
                    component_done[process_box] <= 1'b0;
                    component_seen[process_box] <= 1'b0;
                    component_area[process_box] <= 16'd0;
                    component_age[process_box] <= 3'd0;
                    if (process_box == MAX_BOXES - 1) begin
                        process_box  <= {BOX_W{1'b0}};
                        process_row  <= {ROW_W{1'b0}};
                        process_col  <= {COL_W{1'b0}};
                        run_active   <= 1'b0;
                        process_state <= PR_SCAN;
                    end else begin
                        process_box <= process_box + 1'b1;
                    end
                end

                PR_SCAN: begin
                    if (process_pixel) begin
                        if (!run_active) begin
                            run_active <= 1'b1;
                            run_start  <= process_col;
                            run_end    <= process_col;
                        end else begin
                            run_end <= process_col;
                        end

                        if (process_col == COL_SAMPLES - 1) begin
                            pending_run_start  <= run_active ? run_start : process_col;
                            pending_run_end    <= process_col;
                            after_match_row_end <= 1'b1;
                            run_active          <= 1'b0;
                            process_box         <= {BOX_W{1'b0}};
                            match_found         <= 1'b0;
                            process_state       <= PR_MATCH;
                        end else begin
                            process_col <= process_col + 1'b1;
                            if (process_addr != BITMAP_SIZE - 1) begin
                                process_addr <= process_addr + 1'b1;
                                if (process_addr[4:0] == 5'd31)
                                    process_state <= PR_WORD_WAIT;
                            end
                        end
                    end else if (run_active) begin
                        pending_run_start   <= run_start;
                        pending_run_end     <= run_end;
                        after_match_row_end <= (process_col == COL_SAMPLES - 1);
                        run_active           <= 1'b0;
                        process_box          <= {BOX_W{1'b0}};
                        match_found          <= 1'b0;
                        process_state        <= PR_MATCH;
                    end else if (process_col == COL_SAMPLES - 1) begin
                        process_col   <= {COL_W{1'b0}};
                        if (process_addr != BITMAP_SIZE - 1)
                            process_addr <= process_addr + 1'b1;
                        process_state <= PR_AGE;
                        process_box   <= {BOX_W{1'b0}};
                    end else begin
                        process_col <= process_col + 1'b1;
                        if (process_addr != BITMAP_SIZE - 1) begin
                            process_addr <= process_addr + 1'b1;
                            if (process_addr[4:0] == 5'd31)
                                process_state <= PR_WORD_WAIT;
                        end
                    end
                end

                PR_MATCH: begin
                    if ((pending_run_end - pending_run_start + 1'b1) < MIN_RUN_WIDTH) begin
                        if (after_match_row_end) begin
                            process_col   <= {COL_W{1'b0}};
                            if (process_addr != BITMAP_SIZE - 1)
                                process_addr <= process_addr + 1'b1;
                            process_box   <= {BOX_W{1'b0}};
                            process_state <= PR_AGE;
                        end else begin
                            process_col   <= process_col + 1'b1;
                            process_addr  <= process_addr + 1'b1;
                            process_state <= (process_addr[4:0] == 5'd31) ?
                                             PR_WORD_WAIT : PR_SCAN;
                        end
                    end else begin
                        if (component_live[process_box] &&
                            (pending_run_end + I_connect_gap >= component_x_min[process_box]) &&
                            (pending_run_start <= component_x_max[process_box] + I_connect_gap)) begin
                            if (!match_found) begin
                                match_found <= 1'b1;
                                match_box   <= process_box;
                            end else if (process_box != match_box) begin
                                if (component_x_min[process_box] < component_x_min[match_box])
                                    component_x_min[match_box] <= component_x_min[process_box];
                                if (component_x_max[process_box] > component_x_max[match_box])
                                    component_x_max[match_box] <= component_x_max[process_box];
                                if (component_y_min[process_box] < component_y_min[match_box])
                                    component_y_min[match_box] <= component_y_min[process_box];
                                if (component_y_max[process_box] > component_y_max[match_box])
                                    component_y_max[match_box] <= component_y_max[process_box];
                                component_area[match_box] <= component_area[match_box] + component_area[process_box];
                                component_live[process_box] <= 1'b0;
                                component_done[process_box] <= 1'b0;
                            end
                        end

                        if (process_box == MAX_BOXES - 1) begin
                            process_state <= PR_FINISH;
                        end else begin
                            process_box <= process_box + 1'b1;
                        end
                    end
                end

                PR_FINISH: begin
                    if (match_found) begin
                        component_seen[match_box] <= 1'b1;
                        component_age[match_box] <= 3'd0;
                        if (pending_run_start < component_x_min[match_box])
                            component_x_min[match_box] <= pending_run_start;
                        if (pending_run_end > component_x_max[match_box])
                            component_x_max[match_box] <= pending_run_end;
                        if (process_row < component_y_min[match_box])
                            component_y_min[match_box] <= process_row;
                        if (process_row > component_y_max[match_box])
                            component_y_max[match_box] <= process_row;
                        component_area[match_box] <= component_area[match_box] +
                                                     pending_run_end - pending_run_start + 1'b1;
                    end else begin
                        free_box = MAX_BOXES;
                        for (i = MAX_BOXES-1; i >= 0; i = i - 1) begin
                            if (!component_live[i] && !component_done[i])
                                free_box = i;
                        end
                        if (free_box < MAX_BOXES) begin
                            component_live[free_box] <= 1'b1;
                            component_done[free_box] <= 1'b0;
                            component_seen[free_box] <= 1'b1;
                            component_x_min[free_box] <= pending_run_start;
                            component_x_max[free_box] <= pending_run_end;
                            component_y_min[free_box] <= process_row;
                            component_y_max[free_box] <= process_row;
                            component_area[free_box] <= pending_run_end - pending_run_start + 1'b1;
                            component_age[free_box] <= 3'd0;
                        end
                    end

                    if (after_match_row_end) begin
                        process_col   <= {COL_W{1'b0}};
                        if (process_addr != BITMAP_SIZE - 1)
                            process_addr <= process_addr + 1'b1;
                        process_box   <= {BOX_W{1'b0}};
                        process_state <= PR_AGE;
                    end else begin
                        process_col   <= process_col + 1'b1;
                        if (process_addr != BITMAP_SIZE - 1) begin
                            process_addr <= process_addr + 1'b1;
                            process_state <= (process_addr[4:0] == 5'd31) ?
                                             PR_WORD_WAIT : PR_SCAN;
                        end
                    end
                end

                PR_WORD_WAIT: begin
                    process_state <= PR_SCAN;
                end

                PR_AGE: begin
                    if (component_live[process_box]) begin
                        if (component_seen[process_box]) begin
                            component_seen[process_box] <= 1'b0;
                            component_age[process_box] <= 3'd0;
                        end else if (component_age[process_box] >= MAX_ROW_GAP) begin
                            component_live[process_box] <= 1'b0;
                            if ((((component_x_max[process_box] - component_x_min[process_box]) + 1) >= MIN_COL_SAMPLES) &&
                                (((component_y_max[process_box] - component_y_min[process_box]) + 1) >= MIN_ROW_SAMPLES) &&
                                (component_area[process_box] >= MIN_AREA))
                                component_done[process_box] <= 1'b1;
                            else
                                component_done[process_box] <= 1'b0;
                        end else begin
                            component_age[process_box] <= component_age[process_box] + 1'b1;
                        end
                    end

                    if (process_box == MAX_BOXES - 1) begin
                        if (process_row == ROW_SAMPLES - 1) begin
                            process_state <= PR_PUBLISH;
                        end else begin
                            process_row   <= process_row + 1'b1;
                            process_col   <= {COL_W{1'b0}};
                            process_box   <= {BOX_W{1'b0}};
                            run_active    <= 1'b0;
                            process_state <= PR_SCAN;
                        end
                    end else begin
                        process_box <= process_box + 1'b1;
                    end
                end

                PR_PUBLISH: begin
                    pending_bbox_valid <= {MAX_BOXES{1'b0}};
                    for (i = 0; i < MAX_BOXES; i = i + 1) begin
                        area_value = component_area[i];
                        if ((component_live[i] || component_done[i]) &&
                            ((component_x_max[i] - component_x_min[i] + 1) >= MIN_COL_SAMPLES) &&
                            ((component_y_max[i] - component_y_min[i] + 1) >= MIN_ROW_SAMPLES) &&
                            (area_value >= MIN_AREA)) begin
                            pending_bbox_valid[i] <= 1'b1;
                            pending_x_min[i*12 +: 12] <= F_x_min(component_x_min[i]);
                            pending_x_max[i*12 +: 12] <= F_x_max(component_x_max[i]);
                            pending_y_min[i*12 +: 12] <= F_y_min(component_y_min[i]);
                            pending_y_max[i*12 +: 12] <= F_y_max(component_y_max[i]);
                        end
                    end
                    result_toggle <= ~result_toggle;
                    process_state <= PR_IDLE;
                end

                default: process_state <= PR_IDLE;
            endcase
        end
    end

    // Commit a complete result set only at a frame boundary so the overlay
    // cannot change halfway through a displayed frame.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_bbox_valid       <= {MAX_BOXES{1'b0}};
            O_x_min            <= {(MAX_BOXES*12){1'b0}};
            O_x_max            <= {(MAX_BOXES*12){1'b0}};
            O_y_min            <= {(MAX_BOXES*12){1'b0}};
            O_y_max            <= {(MAX_BOXES*12){1'b0}};
            O_bbox_frame_valid <= 1'b0;
            result_seen        <= 1'b0;
        end else begin
            O_bbox_frame_valid <= 1'b0;
            if (I_user && (result_seen != result_toggle)) begin
                O_bbox_valid       <= pending_bbox_valid;
                O_x_min            <= pending_x_min;
                O_x_max            <= pending_x_max;
                O_y_min            <= pending_y_min;
                O_y_max            <= pending_y_max;
                O_bbox_frame_valid <= 1'b1;
                result_seen        <= result_toggle;
            end
        end
    end

endmodule

// Generate bbox_gray_frame_ram_ip as a 4-bit x 65536 simple dual-port RAM,
// common synchronous clock, no output register. USE_ERAM_IP selects that IP.
module bbox_gray_frame_ram_adapter #(
    parameter integer USE_ERAM_IP = 0
) (
    input  wire        I_clk,
    input  wire [3:0]  I_write_data,
    input  wire [15:0] I_write_addr,
    input  wire        I_write_en,
    input  wire [15:0] I_read_addr,
    output wire [3:0]  O_read_data
);
    generate
        if (USE_ERAM_IP) begin : g_eram
            bbox_gray_frame_ram_ip u_ram (
                .dia   (I_write_data),
                .addra (I_write_addr),
                .wea   (I_write_en),
                .clka  (I_clk),
                .dob   (O_read_data),
                .addrb (I_read_addr)
            );
        end else begin : g_model
            reg [3:0] memory [0:65535];
            reg [3:0] read_data;
            always @(posedge I_clk) begin
                if (I_write_en)
                    memory[I_write_addr] <= I_write_data;
                read_data <= memory[I_read_addr];
            end
            assign O_read_data = read_data;
        end
    endgenerate
endmodule
