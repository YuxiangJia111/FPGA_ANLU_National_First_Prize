`timescale 1ns / 1ns

module histogram_equalization #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [23:0] I_rgb,
    input  wire [23:0] I_ycbcr,
    input  wire [7:0]  I_sobel,
    input  wire [2:0]  I_mode,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    output wire [7:0]  O_equalized_y,
    output reg  [23:0] O_rgb,
    output reg  [23:0] O_ycbcr,
    output reg  [7:0]  O_sobel,
    output reg  [2:0]  O_mode,
    output reg         O_vsync,
    output reg         O_hsync,
    output reg         O_de,
    output reg         O_user,
    output reg         O_last
);

    localparam [19:0] FRAME_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    localparam [2:0] ST_INIT     = 3'd0;
    localparam [2:0] ST_COLLECT  = 3'd1;
    localparam [2:0] ST_FIND_MIN = 3'd2;
    localparam [2:0] ST_MAP_READ = 3'd3;
    localparam [2:0] ST_MAP_HAVE = 3'd4;
    localparam [2:0] ST_DIVIDE   = 3'd5;
    localparam [2:0] ST_WAIT_FRAME = 3'd6;

    reg [2:0] state;
    reg [7:0] init_addr;
    reg [9:0] line_count;
    reg       frame_done_pending;

    reg [7:0]  hist_read_addr;
    reg        hist_read_valid;
    reg [7:0]  last_write_addr;
    reg [19:0] last_write_count;
    reg        last_write_valid;

    reg [7:0]  find_issue_addr;
    reg        find_all_issued;
    reg [7:0]  find_read_addr;
    reg        find_read_valid;
    reg [19:0] cdf_min;
    reg        cdf_min_found;

    reg [7:0]  map_addr;
    reg [19:0] cumulative_count;
    reg [27:0] div_remainder;
    reg [19:0] div_denominator;
    reg [7:0]  div_quotient;
    reg [2:0]  div_bit;

    wire [7:0]  hist_mem_rd_addr;
    wire [19:0] hist_mem_rd_data;
    wire        hist_mem_wr_en;
    wire [7:0]  hist_mem_wr_addr;
    wire [19:0] hist_mem_wr_data;
    wire [7:0]  lut_mem_rd_data;
    wire        lut_mem_wr_en;
    wire [7:0]  lut_mem_wr_addr;
    wire [7:0]  lut_mem_wr_data;

    wire [19:0] histogram_increment_w =
        (last_write_valid && (hist_read_addr == last_write_addr)) ?
        last_write_count + 1'b1 : hist_mem_rd_data + 1'b1;
    wire [20:0] cumulative_next_w =
        {1'b0, cumulative_count} + {1'b0, hist_mem_rd_data};
    wire [19:0] cdf_delta_w = cumulative_next_w[19:0] - cdf_min;
    wire [27:0] numerator_w =
        ({8'd0, cdf_delta_w} << 8) - {8'd0, cdf_delta_w};
    wire [19:0] denominator_w = FRAME_PIXELS - cdf_min;
    wire [27:0] shifted_denominator_w =
        {8'd0, div_denominator} << div_bit;
    wire [7:0] divider_result_w =
        (div_remainder >= {8'd0, div_denominator}) ?
        (div_quotient | 8'd1) : div_quotient;

    assign hist_mem_rd_addr = (state == ST_FIND_MIN) ? find_issue_addr :
                              (state == ST_MAP_READ) ? map_addr :
                              I_ycbcr[23:16];
    assign hist_mem_wr_en = (state == ST_INIT) ||
                            ((state == ST_COLLECT) && hist_read_valid) ||
                            (state == ST_MAP_HAVE);
    assign hist_mem_wr_addr = (state == ST_INIT) ? init_addr :
                              (state == ST_MAP_HAVE) ? map_addr :
                              hist_read_addr;
    assign hist_mem_wr_data = ((state == ST_INIT) ||
                               (state == ST_MAP_HAVE)) ?
                              20'd0 : histogram_increment_w;

    assign lut_mem_wr_en = (state == ST_INIT) ||
                           ((state == ST_MAP_HAVE) &&
                            ((denominator_w == 20'd0) ||
                             (cumulative_next_w[19:0] <= cdf_min))) ||
                           ((state == ST_DIVIDE) && (div_bit == 3'd0));
    assign lut_mem_wr_addr = (state == ST_INIT) ? init_addr : map_addr;
    assign lut_mem_wr_data = (state == ST_INIT) ? init_addr :
                             ((state == ST_MAP_HAVE) &&
                              (denominator_w == 20'd0)) ? map_addr :
                             ((state == ST_MAP_HAVE) ? 8'd0 :
                              divider_result_w);

    ram_f84573da5ab5 #(
        .DATA_WIDTH_A (20),
        .ADDR_WIDTH_A (8),
        .DATA_DEPTH_A (256),
        .DATA_WIDTH_B (20),
        .ADDR_WIDTH_B (8),
        .DATA_DEPTH_B (256),
        .REGMODE_A    ("NOREG"),
        .REGMODE_B    ("NOREG")
    ) u_histogram_ram (
        .doa   (hist_mem_rd_data),
        .dia   (20'd0),
        .addra (hist_mem_rd_addr),
        .clka  (I_clk),
        .wea   (1'b0),
        .clkb  (I_clk),
        .web   (hist_mem_wr_en),
        .dob   (),
        .dib   (hist_mem_wr_data),
        .addrb (hist_mem_wr_addr)
    );

    ram_f84573da5ab5 #(
        .DATA_WIDTH_A (8),
        .ADDR_WIDTH_A (8),
        .DATA_DEPTH_A (256),
        .DATA_WIDTH_B (8),
        .ADDR_WIDTH_B (8),
        .DATA_DEPTH_B (256),
        .REGMODE_A    ("NOREG"),
        .REGMODE_B    ("NOREG")
    ) u_equalize_lut_ram (
        .doa   (lut_mem_rd_data),
        .dia   (8'd0),
        .addra (I_ycbcr[23:16]),
        .clka  (I_clk),
        .wea   (1'b0),
        .clkb  (I_clk),
        .web   (lut_mem_wr_en),
        .dob   (),
        .dib   (lut_mem_wr_data),
        .addrb (lut_mem_wr_addr)
    );

    assign O_equalized_y = O_de ? lut_mem_rd_data : 8'd0;

    // Synchronous LUT read also supplies one pipeline stage for all sideband data.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_rgb         <= 24'd0;
            O_ycbcr       <= 24'd0;
            O_sobel       <= 8'd0;
            O_mode        <= 3'd0;
            O_vsync       <= 1'b0;
            O_hsync       <= 1'b0;
            O_de          <= 1'b0;
            O_user        <= 1'b0;
            O_last        <= 1'b0;
        end else begin
            O_rgb         <= I_rgb;
            O_ycbcr       <= I_ycbcr;
            O_sobel       <= I_sobel;
            O_mode        <= I_mode;
            O_vsync       <= I_vsync;
            O_hsync       <= I_hsync;
            O_de          <= I_de;
            O_user        <= I_user;
            O_last        <= I_last;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state                  <= ST_INIT;
            init_addr              <= 8'd0;
            line_count             <= 10'd0;
            frame_done_pending     <= 1'b0;
            hist_read_addr         <= 8'd0;
            hist_read_valid        <= 1'b0;
            last_write_addr        <= 8'd0;
            last_write_count       <= 20'd0;
            last_write_valid       <= 1'b0;
            find_issue_addr        <= 8'd0;
            find_all_issued        <= 1'b0;
            find_read_addr         <= 8'd0;
            find_read_valid        <= 1'b0;
            cdf_min                <= 20'd0;
            cdf_min_found          <= 1'b0;
            map_addr               <= 8'd0;
            cumulative_count       <= 20'd0;
            div_remainder          <= 28'd0;
            div_denominator        <= 20'd0;
            div_quotient           <= 8'd0;
            div_bit                <= 3'd0;
        end else begin
            case(state)
                ST_INIT: begin
                    if(init_addr == 8'hff) begin
                        init_addr <= 8'd0;
                        state <= ST_WAIT_FRAME;
                    end else begin
                        init_addr <= init_addr + 1'b1;
                    end
                end

                ST_WAIT_FRAME: begin
                    hist_read_valid <= 1'b0;
                    if(I_de && I_user) begin
                        hist_read_addr  <= I_ycbcr[23:16];
                        hist_read_valid <= 1'b1;
                        line_count      <= 10'd0;
                        state           <= ST_COLLECT;
                    end
                end

                ST_COLLECT: begin
                    hist_read_valid <= I_de;
                    if(I_de) begin
                        hist_read_addr <= I_ycbcr[23:16];

                        if(I_user)
                            line_count <= 10'd0;
                        else if(I_last)
                            line_count <= line_count + 1'b1;

                        if(I_last && (line_count == IMG_HEIGHT - 1))
                            frame_done_pending <= 1'b1;
                    end

                    if(hist_read_valid) begin
                        last_write_count <= histogram_increment_w;
                        last_write_addr  <= hist_read_addr;
                        last_write_valid <= 1'b1;
                    end

                    // The final pending read-modify-write commits on this edge.
                    if(frame_done_pending && hist_read_valid) begin
                        frame_done_pending <= 1'b0;
                        hist_read_valid     <= 1'b0;
                        last_write_valid    <= 1'b0;
                        find_issue_addr     <= 8'd0;
                        find_all_issued     <= 1'b0;
                        find_read_valid     <= 1'b0;
                        cdf_min             <= 20'd0;
                        cdf_min_found       <= 1'b0;
                        state               <= ST_FIND_MIN;
                    end
                end

                ST_FIND_MIN: begin
                    if(!find_all_issued) begin
                        find_read_addr  <= find_issue_addr;
                        find_read_valid <= 1'b1;
                        if(find_issue_addr == 8'hff)
                            find_all_issued <= 1'b1;
                        else
                            find_issue_addr <= find_issue_addr + 1'b1;
                    end else begin
                        find_read_valid <= 1'b0;
                    end

                    if(find_read_valid) begin
                        if(!cdf_min_found && (hist_mem_rd_data != 20'd0)) begin
                            cdf_min       <= hist_mem_rd_data;
                            cdf_min_found <= 1'b1;
                        end

                        if(find_read_addr == 8'hff) begin
                            map_addr         <= 8'd0;
                            cumulative_count <= 20'd0;
                            state            <= ST_MAP_READ;
                        end
                    end
                end

                ST_MAP_READ: begin
                    state <= ST_MAP_HAVE;
                end

                ST_MAP_HAVE: begin
                    cumulative_count <= cumulative_next_w[19:0];

                    // A constant frame has no nonzero equalization range.
                    if(denominator_w == 20'd0) begin
                        if(map_addr == 8'hff) begin
                            last_write_valid <= 1'b0;
                            state <= ST_COLLECT;
                        end else begin
                            map_addr <= map_addr + 1'b1;
                            state <= ST_MAP_READ;
                        end
                    end else if(cumulative_next_w[19:0] <= cdf_min) begin
                        if(map_addr == 8'hff) begin
                            last_write_valid <= 1'b0;
                            state <= ST_COLLECT;
                        end else begin
                            map_addr <= map_addr + 1'b1;
                            state <= ST_MAP_READ;
                        end
                    end else begin
                        div_remainder   <= numerator_w;
                        div_denominator <= denominator_w;
                        div_quotient    <= 8'd0;
                        div_bit         <= 3'd7;
                        state           <= ST_DIVIDE;
                    end
                end

                ST_DIVIDE: begin
                    if(div_bit == 3'd0) begin
                        if(map_addr == 8'hff) begin
                            last_write_valid <= 1'b0;
                            state <= ST_COLLECT;
                        end else begin
                            map_addr <= map_addr + 1'b1;
                            state <= ST_MAP_READ;
                        end
                    end else begin
                        if(div_remainder >= shifted_denominator_w) begin
                            div_remainder <= div_remainder - shifted_denominator_w;
                            div_quotient[div_bit] <= 1'b1;
                        end
                        div_bit <= div_bit - 1'b1;
                    end
                end

                default: state <= ST_INIT;
            endcase
        end
    end

endmodule


module ycbcr2rgb_equalized (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [7:0]  I_equalized_y,
    input  wire [23:0] I_rgb,
    input  wire [23:0] I_ycbcr,
    input  wire [7:0]  I_sobel,
    input  wire [2:0]  I_mode,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    output reg  [23:0] O_equalized_rgb,
    output reg  [23:0] O_rgb,
    output reg  [23:0] O_ycbcr,
    output reg  [7:0]  O_sobel,
    output reg  [2:0]  O_mode,
    output reg         O_vsync,
    output reg         O_hsync,
    output reg         O_de,
    output reg         O_user,
    output reg         O_last
);

    wire signed [8:0] cb_delta_w =
        $signed({1'b0, I_ycbcr[15:8]}) - 9'sd128;
    wire signed [8:0] cr_delta_w =
        $signed({1'b0, I_ycbcr[7:0]}) - 9'sd128;

    reg [7:0] y_1;
    reg signed [18:0] r_term_1;
    reg signed [18:0] g_cb_term_1;
    reg signed [18:0] g_cr_term_1;
    reg signed [18:0] b_term_1;
    reg [23:0] rgb_1, ycbcr_1;
    reg [7:0] sobel_1;
    reg [2:0] mode_1;
    reg vsync_1, hsync_1, de_1, user_1, last_1;

    reg signed [19:0] r_scaled_2;
    reg signed [19:0] g_scaled_2;
    reg signed [19:0] b_scaled_2;
    reg [23:0] rgb_2, ycbcr_2;
    reg [7:0] sobel_2;
    reg [2:0] mode_2;
    reg vsync_2, hsync_2, de_2, user_2, last_2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            y_1           <= 8'd0;
            r_term_1      <= 19'sd0;
            g_cb_term_1   <= 19'sd0;
            g_cr_term_1   <= 19'sd0;
            b_term_1      <= 19'sd0;
            rgb_1         <= 24'd0;
            ycbcr_1       <= 24'd0;
            sobel_1       <= 8'd0;
            mode_1        <= 3'd0;
            vsync_1       <= 1'b0;
            hsync_1       <= 1'b0;
            de_1          <= 1'b0;
            user_1        <= 1'b0;
            last_1        <= 1'b0;
        end else begin
            y_1         <= I_equalized_y;
            r_term_1    <= cr_delta_w * 10'sd359;
            g_cb_term_1 <= cb_delta_w * 9'sd88;
            g_cr_term_1 <= cr_delta_w * 9'sd183;
            b_term_1    <= cb_delta_w * 10'sd454;
            rgb_1       <= I_rgb;
            ycbcr_1     <= I_ycbcr;
            sobel_1     <= I_sobel;
            mode_1      <= I_mode;
            vsync_1     <= I_vsync;
            hsync_1     <= I_hsync;
            de_1        <= I_de;
            user_1      <= I_user;
            last_1      <= I_last;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            r_scaled_2 <= 20'sd0;
            g_scaled_2 <= 20'sd0;
            b_scaled_2 <= 20'sd0;
            rgb_2      <= 24'd0;
            ycbcr_2    <= 24'd0;
            sobel_2    <= 8'd0;
            mode_2     <= 3'd0;
            vsync_2    <= 1'b0;
            hsync_2    <= 1'b0;
            de_2       <= 1'b0;
            user_2     <= 1'b0;
            last_2     <= 1'b0;
        end else begin
            r_scaled_2 <= $signed({1'b0, y_1, 8'd0}) + r_term_1;
            g_scaled_2 <= $signed({1'b0, y_1, 8'd0}) -
                          g_cb_term_1 - g_cr_term_1;
            b_scaled_2 <= $signed({1'b0, y_1, 8'd0}) + b_term_1;
            rgb_2      <= rgb_1;
            ycbcr_2    <= ycbcr_1;
            sobel_2    <= sobel_1;
            mode_2     <= mode_1;
            vsync_2    <= vsync_1;
            hsync_2    <= hsync_1;
            de_2       <= de_1;
            user_2     <= user_1;
            last_2     <= last_1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_equalized_rgb <= 24'd0;
            O_rgb           <= 24'd0;
            O_ycbcr         <= 24'd0;
            O_sobel         <= 8'd0;
            O_mode          <= 3'd0;
            O_vsync         <= 1'b0;
            O_hsync         <= 1'b0;
            O_de            <= 1'b0;
            O_user          <= 1'b0;
            O_last          <= 1'b0;
        end else begin
            if(r_scaled_2 < 20'sd0)
                O_equalized_rgb[23:16] <= 8'd0;
            else if(r_scaled_2 > 20'sd65280)
                O_equalized_rgb[23:16] <= 8'hff;
            else
                O_equalized_rgb[23:16] <= r_scaled_2[15:8];

            if(g_scaled_2 < 20'sd0)
                O_equalized_rgb[15:8] <= 8'd0;
            else if(g_scaled_2 > 20'sd65280)
                O_equalized_rgb[15:8] <= 8'hff;
            else
                O_equalized_rgb[15:8] <= g_scaled_2[15:8];

            if(b_scaled_2 < 20'sd0)
                O_equalized_rgb[7:0] <= 8'd0;
            else if(b_scaled_2 > 20'sd65280)
                O_equalized_rgb[7:0] <= 8'hff;
            else
                O_equalized_rgb[7:0] <= b_scaled_2[15:8];

            O_rgb   <= rgb_2;
            O_ycbcr <= ycbcr_2;
            O_sobel <= sobel_2;
            O_mode  <= mode_2;
            O_vsync <= vsync_2;
            O_hsync <= hsync_2;
            O_de    <= de_2;
            O_user  <= user_2;
            O_last  <= last_2;
        end
    end

endmodule
