`timescale 1ns / 1ns

module sobel_edge #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [23:0] I_rgb,
    input  wire [23:0] I_ycbcr,
    input  wire [2:0]  I_mode,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    output reg  [7:0]  O_sobel,
    output reg  [23:0] O_rgb,
    output reg  [23:0] O_ycbcr,
    output reg  [2:0]  O_mode,
    output reg         O_vsync,
    output reg         O_hsync,
    output reg         O_de,
    output reg         O_user,
    output reg         O_last
);

    reg [7:0] line_1 [0:IMG_WIDTH-1] /* synthesis ram_style="bram_fast" */;
    reg [7:0] line_2 [0:IMG_WIDTH-1] /* synthesis ram_style="bram_fast" */;

    reg [10:0] x_count;
    reg [9:0]  y_count;
    wire [10:0] pixel_x = I_user ? 11'd0 : x_count;
    wire [9:0]  pixel_y = I_user ? 10'd0 : y_count;

    reg [7:0] line_1_q;
    reg [7:0] line_2_q;
    reg [7:0] current_y_q;
    reg [10:0] x_q;
    reg [9:0] y_q;
    reg [23:0] rgb_q;
    reg [23:0] ycbcr_q;
    reg [2:0] mode_q;
    reg vsync_q, hsync_q, de_q, user_q, last_q;

    reg [7:0] top_a, top_b;
    reg [7:0] mid_a, mid_b;
    reg [7:0] bot_a, bot_b;
    reg [10:0] gx_pos_s1, gx_neg_s1;
    reg [10:0] gy_pos_s1, gy_neg_s1;
    reg border_s1;
    reg [23:0] rgb_s1, ycbcr_s1;
    reg [2:0] mode_s1;
    reg vsync_s1, hsync_s1, de_s1, user_s1, last_s1;

    wire signed [11:0] gx_diff = $signed({1'b0, gx_pos_s1}) -
                                  $signed({1'b0, gx_neg_s1});
    wire signed [11:0] gy_diff = $signed({1'b0, gy_pos_s1}) -
                                  $signed({1'b0, gy_neg_s1});
    reg [10:0] gx_abs_s2, gy_abs_s2;
    reg border_s2;
    reg [23:0] rgb_s2, ycbcr_s2;
    reg [2:0] mode_s2;
    reg vsync_s2, hsync_s2, de_s2, user_s2, last_s2;

    reg [11:0] magnitude_s3;
    reg border_s3;
    reg [23:0] rgb_s3, ycbcr_s3;
    reg [2:0] mode_s3;
    reg vsync_s3, hsync_s3, de_s3, user_s3, last_s3;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x_count <= 11'd0;
            y_count <= 10'd0;
        end else if(I_de) begin
            if(I_user) begin
                x_count <= 11'd1;
                y_count <= 10'd0;
            end else if(x_count == IMG_WIDTH - 1) begin
                x_count <= 11'd0;
                y_count <= (y_count == IMG_HEIGHT - 1) ? 10'd0 : y_count + 1'b1;
            end else begin
                x_count <= x_count + 1'b1;
            end
        end
    end

    // Read-before-write behavior supplies the previous two image rows.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            line_1_q <= 8'd0;
            line_2_q <= 8'd0;
            current_y_q <= 8'd0;
            x_q <= 11'd0;
            y_q <= 10'd0;
        end else if(I_de) begin
            line_1_q <= line_1[pixel_x];
            line_2_q <= line_2[pixel_x];
            line_1[pixel_x] <= I_ycbcr[23:16];
            line_2[pixel_x] <= line_1[pixel_x];
            current_y_q <= I_ycbcr[23:16];
            x_q <= pixel_x;
            y_q <= pixel_y;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            rgb_q <= 24'd0;
            ycbcr_q <= 24'd0;
            mode_q <= 3'd0;
            vsync_q <= 1'b0;
            hsync_q <= 1'b0;
            de_q <= 1'b0;
            user_q <= 1'b0;
            last_q <= 1'b0;
        end else begin
            rgb_q <= I_rgb;
            ycbcr_q <= I_ycbcr;
            mode_q <= I_mode;
            vsync_q <= I_vsync;
            hsync_q <= I_hsync;
            de_q <= I_de;
            user_q <= I_user;
            last_q <= I_last;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            top_a <= 8'd0;
            top_b <= 8'd0;
            mid_a <= 8'd0;
            mid_b <= 8'd0;
            bot_a <= 8'd0;
            bot_b <= 8'd0;
            gx_pos_s1 <= 11'd0;
            gx_neg_s1 <= 11'd0;
            gy_pos_s1 <= 11'd0;
            gy_neg_s1 <= 11'd0;
            border_s1 <= 1'b1;
            rgb_s1 <= 24'd0;
            ycbcr_s1 <= 24'd0;
            mode_s1 <= 3'd0;
            vsync_s1 <= 1'b0;
            hsync_s1 <= 1'b0;
            de_s1 <= 1'b0;
            user_s1 <= 1'b0;
            last_s1 <= 1'b0;
        end else begin
            if(de_q) begin
                if(x_q == 0) begin
                    top_a <= 8'd0;
                    top_b <= line_2_q;
                    mid_a <= 8'd0;
                    mid_b <= line_1_q;
                    bot_a <= 8'd0;
                    bot_b <= current_y_q;
                end else begin
                    top_a <= top_b;
                    top_b <= line_2_q;
                    mid_a <= mid_b;
                    mid_b <= line_1_q;
                    bot_a <= bot_b;
                    bot_b <= current_y_q;
                end

                gx_pos_s1 <= line_2_q + ({3'd0, line_1_q} << 1) + current_y_q;
                gx_neg_s1 <= top_a + ({3'd0, mid_a} << 1) + bot_a;
                gy_pos_s1 <= bot_a + ({3'd0, bot_b} << 1) + current_y_q;
                gy_neg_s1 <= top_a + ({3'd0, top_b} << 1) + line_2_q;
                border_s1 <= (x_q < 2) || (y_q < 2);
            end else begin
                gx_pos_s1 <= 11'd0;
                gx_neg_s1 <= 11'd0;
                gy_pos_s1 <= 11'd0;
                gy_neg_s1 <= 11'd0;
                border_s1 <= 1'b1;
            end

            rgb_s1 <= rgb_q;
            ycbcr_s1 <= ycbcr_q;
            mode_s1 <= mode_q;
            vsync_s1 <= vsync_q;
            hsync_s1 <= hsync_q;
            de_s1 <= de_q;
            user_s1 <= user_q;
            last_s1 <= last_q;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            gx_abs_s2 <= 11'd0;
            gy_abs_s2 <= 11'd0;
            border_s2 <= 1'b1;
            rgb_s2 <= 24'd0;
            ycbcr_s2 <= 24'd0;
            mode_s2 <= 3'd0;
            vsync_s2 <= 1'b0;
            hsync_s2 <= 1'b0;
            de_s2 <= 1'b0;
            user_s2 <= 1'b0;
            last_s2 <= 1'b0;
        end else begin
            gx_abs_s2 <= gx_diff[11] ? -gx_diff : gx_diff;
            gy_abs_s2 <= gy_diff[11] ? -gy_diff : gy_diff;
            border_s2 <= border_s1;
            rgb_s2 <= rgb_s1;
            ycbcr_s2 <= ycbcr_s1;
            mode_s2 <= mode_s1;
            vsync_s2 <= vsync_s1;
            hsync_s2 <= hsync_s1;
            de_s2 <= de_s1;
            user_s2 <= user_s1;
            last_s2 <= last_s1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            magnitude_s3 <= 12'd0;
            border_s3 <= 1'b1;
            rgb_s3 <= 24'd0;
            ycbcr_s3 <= 24'd0;
            mode_s3 <= 3'd0;
            vsync_s3 <= 1'b0;
            hsync_s3 <= 1'b0;
            de_s3 <= 1'b0;
            user_s3 <= 1'b0;
            last_s3 <= 1'b0;
        end else begin
            magnitude_s3 <= gx_abs_s2 + gy_abs_s2;
            border_s3 <= border_s2;
            rgb_s3 <= rgb_s2;
            ycbcr_s3 <= ycbcr_s2;
            mode_s3 <= mode_s2;
            vsync_s3 <= vsync_s2;
            hsync_s3 <= hsync_s2;
            de_s3 <= de_s2;
            user_s3 <= user_s2;
            last_s3 <= last_s2;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_sobel <= 8'd0;
            O_rgb <= 24'd0;
            O_ycbcr <= 24'd0;
            O_mode <= 3'd0;
            O_vsync <= 1'b0;
            O_hsync <= 1'b0;
            O_de <= 1'b0;
            O_user <= 1'b0;
            O_last <= 1'b0;
        end else begin
            if(border_s3 || !de_s3)
                O_sobel <= 8'd0;
            else if(magnitude_s3 > 12'd255)
                O_sobel <= 8'hff;
            else
                O_sobel <= magnitude_s3[7:0];

            O_rgb <= rgb_s3;
            O_ycbcr <= ycbcr_s3;
            O_mode <= mode_s3;
            O_vsync <= vsync_s3;
            O_hsync <= hsync_s3;
            O_de <= de_s3;
            O_user <= user_s3;
            O_last <= last_s3;
        end
    end

endmodule
