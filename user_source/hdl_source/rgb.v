`timescale 1ns / 1ns

module rgb2ycbcr (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [23:0] I_rgb,
    input  wire [2:0]  I_mode,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    output reg  [23:0] O_rgb,
    output reg  [23:0] O_ycbcr,
    output reg  [2:0]  O_mode,
    output reg         O_vsync,
    output reg         O_hsync,
    output reg         O_de,
    output reg         O_user,
    output reg         O_last
);

    reg [14:0] y_r_mul_1;
    reg [15:0] y_g_mul_1;
    reg [12:0] y_b_mul_1;
    reg signed [16:0] cb_r_mul_1;
    reg signed [16:0] cb_g_mul_1;
    reg signed [17:0] cb_b_mul_1;
    reg signed [17:0] cr_r_mul_1;
    reg signed [17:0] cr_g_mul_1;
    reg signed [16:0] cr_b_mul_1;
    reg [23:0] rgb_1;
    reg [2:0] mode_1;
    reg vsync_1, hsync_1, de_1, user_1, last_1;

    reg [16:0] y_sum_2;
    reg signed [18:0] cb_sum_2;
    reg signed [18:0] cr_sum_2;
    reg [23:0] rgb_2;
    reg [2:0] mode_2;
    reg vsync_2, hsync_2, de_2, user_2, last_2;

    // The coefficients are constants, so shift/add networks are equivalent
    // to the original multipliers without consuming DSP blocks.
    wire signed [16:0] r_s = $signed({1'b0, I_rgb[23:16]});
    wire signed [16:0] g_s = $signed({1'b0, I_rgb[15:8]});
    wire signed [16:0] b_s = $signed({1'b0, I_rgb[7:0]});
    wire [15:0] r_u = {8'd0, I_rgb[23:16]};
    wire [15:0] g_u = {8'd0, I_rgb[15:8]};
    wire [15:0] b_u = {8'd0, I_rgb[7:0]};
    wire [14:0] y_r_const = (r_u << 6) + (r_u << 3) +
                            (r_u << 2) + r_u;
    wire [15:0] y_g_const = (g_u << 7) + (g_u << 4) +
                            (g_u << 2) + (g_u << 1);
    wire [12:0] y_b_const = (b_u << 5) - (b_u << 1) - b_u;
    wire signed [16:0] cb_r_const = -((r_s <<< 5) + (r_s <<< 3) +
                                      (r_s <<< 1) + r_s);
    wire signed [16:0] cb_g_const = -((g_s <<< 6) + (g_s <<< 4) +
                                      (g_s <<< 2) + g_s);
    wire signed [17:0] cb_b_const = b_s <<< 7;
    wire signed [17:0] cr_r_const = r_s <<< 7;
    wire signed [17:0] cr_g_const = -((g_s <<< 6) + (g_s <<< 5) +
                                      (g_s <<< 3) + (g_s <<< 1) + g_s);
    wire signed [16:0] cr_b_const = -((b_s <<< 4) + (b_s <<< 2) + b_s);

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            y_r_mul_1  <= 15'd0;
            y_g_mul_1  <= 16'd0;
            y_b_mul_1  <= 13'd0;
            cb_r_mul_1 <= 17'sd0;
            cb_g_mul_1 <= 17'sd0;
            cb_b_mul_1 <= 18'sd0;
            cr_r_mul_1 <= 18'sd0;
            cr_g_mul_1 <= 18'sd0;
            cr_b_mul_1 <= 17'sd0;
            rgb_1      <= 24'd0;
            mode_1     <= 3'd0;
            vsync_1    <= 1'b0;
            hsync_1    <= 1'b0;
            de_1       <= 1'b0;
            user_1     <= 1'b0;
            last_1     <= 1'b0;
        end else begin
            y_r_mul_1  <= y_r_const;
            y_g_mul_1  <= y_g_const;
            y_b_mul_1  <= y_b_const;
            cb_r_mul_1 <= cb_r_const;
            cb_g_mul_1 <= cb_g_const;
            cb_b_mul_1 <= cb_b_const;
            cr_r_mul_1 <= cr_r_const;
            cr_g_mul_1 <= cr_g_const;
            cr_b_mul_1 <= cr_b_const;
            rgb_1      <= I_rgb;
            mode_1     <= I_mode;
            vsync_1    <= I_vsync;
            hsync_1    <= I_hsync;
            de_1       <= I_de;
            user_1     <= I_user;
            last_1     <= I_last;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            y_sum_2  <= 17'd0;
            cb_sum_2 <= 19'sd0;
            cr_sum_2 <= 19'sd0;
            rgb_2    <= 24'd0;
            mode_2   <= 3'd0;
            vsync_2  <= 1'b0;
            hsync_2  <= 1'b0;
            de_2     <= 1'b0;
            user_2   <= 1'b0;
            last_2   <= 1'b0;
        end else begin
            y_sum_2  <= y_r_mul_1 + y_g_mul_1 + y_b_mul_1;
            cb_sum_2 <= cb_r_mul_1 + cb_g_mul_1 + cb_b_mul_1 + 19'sd32768;
            cr_sum_2 <= cr_r_mul_1 + cr_g_mul_1 + cr_b_mul_1 + 19'sd32768;
            rgb_2    <= rgb_1;
            mode_2   <= mode_1;
            vsync_2  <= vsync_1;
            hsync_2  <= hsync_1;
            de_2     <= de_1;
            user_2   <= user_1;
            last_2   <= last_1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_rgb    <= 24'd0;
            O_ycbcr  <= 24'd0;
            O_mode   <= 3'd0;
            O_vsync  <= 1'b0;
            O_hsync  <= 1'b0;
            O_de     <= 1'b0;
            O_user   <= 1'b0;
            O_last   <= 1'b0;
        end else begin
            O_rgb    <= rgb_2;
            O_ycbcr  <= {y_sum_2[15:8], cb_sum_2[15:8], cr_sum_2[15:8]};
            O_mode   <= mode_2;
            O_vsync  <= vsync_2;
            O_hsync  <= hsync_2;
            O_de     <= de_2;
            O_user   <= user_2;
            O_last   <= last_2;
        end
    end

endmodule
