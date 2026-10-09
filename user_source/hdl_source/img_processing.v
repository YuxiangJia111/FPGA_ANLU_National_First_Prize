`timescale 1ns / 1ns

// Lightweight processing path used while the multi-region downsampler and CNN
// are integrated. Sobel, histogram equalization and auto exposure are kept in
// the repository but intentionally have no active instances in this build.
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
    wire [23:0] rgb_aligned;
    wire [2:0]  mode_aligned;
    wire         vsync_aligned;
    wire         hsync_aligned;
    wire         de_aligned;
    wire         user_aligned;
    wire         last_aligned;

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
        .O_rgb       (rgb_aligned),
        .O_ycbcr     (ycbcr_data),
        .O_mode      (mode_aligned),
        .O_vsync     (vsync_aligned),
        .O_hsync     (hsync_aligned),
        .O_de        (de_aligned),
        .O_user      (user_aligned),
        .O_last      (last_aligned)
    );

    always @(*) begin
        case(mode_aligned)
            3'b001: O_rgb = {3{ycbcr_data[23:16]}};
            3'b010: O_rgb = (ycbcr_data[23:16] >= 8'd128) ?
                            24'hffffff : 24'h000000;
            default: O_rgb = rgb_aligned;
        endcase
    end

    assign O_ycbcr = ycbcr_data;
    assign O_vsync = vsync_aligned;
    assign O_hsync = hsync_aligned;
    assign O_de    = de_aligned;
    assign O_user  = user_aligned;
    assign O_last  = last_aligned;

endmodule
