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

    localparam [2:0] ST_INIT       = 3'd0;
    localparam [2:0] ST_COLLECT    = 3'd1;
    localparam [2:0] ST_FIND_MIN   = 3'd2;
    localparam [2:0] ST_MAP_READ   = 3'd3;
    localparam [2:0] ST_MAP_HAVE   = 3'd4;
    localparam [2:0] ST_DIVIDE     = 3'd5;
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

    // The synchronous LUT read supplies one sideband alignment stage.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_rgb   <= 24'd0;
            O_ycbcr <= 24'd0;
            O_sobel <= 8'd0;
            O_mode  <= 3'd0;
            O_vsync <= 1'b0;
            O_hsync <= 1'b0;
            O_de    <= 1'b0;
            O_user  <= 1'b0;
            O_last  <= 1'b0;
        end else begin
            O_rgb   <= I_rgb;
            O_ycbcr <= I_ycbcr;
            O_sobel <= I_sobel;
            O_mode  <= I_mode;
            O_vsync <= I_vsync;
            O_hsync <= I_hsync;
            O_de    <= I_de;
            O_user  <= I_user;
            O_last  <= I_last;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state              <= ST_INIT;
            init_addr          <= 8'd0;
            line_count         <= 10'd0;
            frame_done_pending <= 1'b0;
            hist_read_addr     <= 8'd0;
            hist_read_valid    <= 1'b0;
            last_write_addr    <= 8'd0;
            last_write_count   <= 20'd0;
            last_write_valid   <= 1'b0;
            find_issue_addr    <= 8'd0;
            find_all_issued    <= 1'b0;
            find_read_addr     <= 8'd0;
            find_read_valid    <= 1'b0;
            cdf_min            <= 20'd0;
            cdf_min_found      <= 1'b0;
            map_addr           <= 8'd0;
            cumulative_count   <= 20'd0;
            div_remainder      <= 28'd0;
            div_denominator    <= 20'd0;
            div_quotient       <= 8'd0;
            div_bit            <= 3'd0;
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

                ST_MAP_READ: state <= ST_MAP_HAVE;

                ST_MAP_HAVE: begin
                    cumulative_count <= cumulative_next_w[19:0];
                    if((denominator_w == 20'd0) ||
                       (cumulative_next_w[19:0] <= cdf_min)) begin
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
