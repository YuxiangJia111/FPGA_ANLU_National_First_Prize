`timescale 1ns / 1ns

module img_processing #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [2:0]  I_mode,
    input  wire [23:0] I_rgb,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    output reg  [23:0] O_rgb,
    output wire [23:0] O_ycbcr,
    output wire        O_vsync,
    output wire        O_hsync,
    output wire        O_de,
    output wire        O_user,
    output wire        O_last
);

    wire [23:0] ycbcr_data;
    wire [23:0] rgb_from_csc;
    wire [2:0]  mode_from_csc;
    wire         vsync_from_csc;
    wire         hsync_from_csc;
    wire         de_from_csc;
    wire         user_from_csc;
    wire         last_from_csc;

    wire [7:0]  sobel_data;
    wire [23:0] rgb_aligned;
    wire [23:0] ycbcr_aligned;
    wire [2:0]  mode_aligned;
    wire         vsync_aligned;
    wire         hsync_aligned;
    wire         de_aligned;
    wire         user_aligned;
    wire         last_aligned;
    wire [23:0]  ae_ycbcr;
    wire [23:0]  ae_rgb;

    rgb2ycbcr u_rgb2ycbcr (
        .I_clk       (I_clk),
        .I_rst_n     (I_rst_n),
        .I_rgb       (I_rgb),
        .I_mode      (I_mode),
        .I_vsync     (I_vsync),
        .I_hsync     (I_hsync),
        .I_de        (I_de),
        .I_user      (I_user),
        .I_last      (I_last),
        .O_rgb       (rgb_from_csc),
        .O_ycbcr     (ycbcr_data),
        .O_mode      (mode_from_csc),
        .O_vsync     (vsync_from_csc),
        .O_hsync     (hsync_from_csc),
        .O_de        (de_from_csc),
        .O_user      (user_from_csc),
        .O_last      (last_from_csc)
    );

    sobel_edge #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT)
    ) u_sobel_edge (
        .I_clk       (I_clk),
        .I_rst_n     (I_rst_n),
        .I_rgb       (rgb_from_csc),
        .I_ycbcr     (ycbcr_data),
        .I_mode      (mode_from_csc),
        .I_vsync     (vsync_from_csc),
        .I_hsync     (hsync_from_csc),
        .I_de        (de_from_csc),
        .I_user      (user_from_csc),
        .I_last      (last_from_csc),
        .O_sobel     (sobel_data),
        .O_rgb       (rgb_aligned),
        .O_ycbcr     (ycbcr_aligned),
        .O_mode      (mode_aligned),
        .O_vsync     (vsync_aligned),
        .O_hsync     (hsync_aligned),
        .O_de        (de_aligned),
        .O_user      (user_aligned),
        .O_last      (last_aligned)
    );

    auto_exposure #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT)
    ) u_auto_exposure (
        .I_clk       (I_clk),
        .I_rst_n     (I_rst_n),
        .I_ycbcr     (ycbcr_aligned),
        .I_vsync     (vsync_aligned),
        .I_hsync     (hsync_aligned),
        .I_de        (de_aligned),
        .I_user      (user_aligned),
        .I_last      (last_aligned),
        .O_ycbcr     (ae_ycbcr),
        .O_vsync     (),
        .O_hsync     (),
        .O_de        (),
        .O_user      (),
        .O_last      (),
        .O_lut_select()
    );

    ycbcr2rgb u_ycbcr2rgb (
        .I_ycbcr (ae_ycbcr),
        .O_rgb   (ae_rgb)
    );

    always @(*) begin
        case(mode_aligned)
            3'b001: O_rgb = {3{ycbcr_aligned[23:16]}};
            3'b010: O_rgb = (ycbcr_aligned[23:16] >= 8'd128) ?
                            24'hffffff : 24'h000000;
            3'b011: O_rgb = {3{sobel_data}};
            3'b100: O_rgb = ae_rgb;
            default: O_rgb = rgb_aligned;
        endcase
    end

    assign O_ycbcr = ycbcr_aligned;
    assign O_vsync = vsync_aligned;
    assign O_hsync = hsync_aligned;
    assign O_de    = de_aligned;
    assign O_user  = user_aligned;
    assign O_last  = last_aligned;

endmodule
