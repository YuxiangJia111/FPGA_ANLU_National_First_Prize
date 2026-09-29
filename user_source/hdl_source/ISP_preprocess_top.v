`timescale 1ns / 1ns

module ISP_preprocess_top (
    input  wire         I_clk,
    input  wire         I_rst_n,
    input  wire [39:0]  I_tdata,
    input  wire         I_tlast,
    input  wire         I_tuser,
    input  wire         I_tvalid,
    output wire [127:0] O_tdata,
    output wire         O_tlast,
    output wire         O_tuser,
    output wire         O_tvalid
);

wire unused_input_ready;

isp_top u_isp_top (
    .axi4s_video_aclk (I_clk),
    .I_rst_n          (I_rst_n),
    .I_tlast          (I_tlast),
    .I_tuser          (I_tuser),
    .I_tdata          (I_tdata),
    .I_tvalid         (I_tvalid),
    .I_tdest          (10'd0),
    .O_tready         (1'b1),
    .O_tdata          (O_tdata),
    .O_tlast          (O_tlast),
    .O_tuser          (O_tuser),
    .O_tvalid         (O_tvalid),
    .I_tready         (unused_input_ready)
);

endmodule
