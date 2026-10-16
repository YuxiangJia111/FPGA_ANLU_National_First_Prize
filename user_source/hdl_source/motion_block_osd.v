`timescale 1ns/1ps

// Two pipeline stages from the mixer's un-delayed coordinate stage.
// Constant interval decoders avoid pixel-rate division/modulo by 48.
module motion_block_osd #(
    parameter integer ROI_X_MIN=198, ROI_X_MAX=1022,
    parameter integer ROI_Y_MIN=18, ROI_Y_MAX=702,
    parameter integer SAMPLE_STEP=3, BLOCK_SHIFT=4,
    parameter integer BLOCK_COLS=18, BLOCK_ROWS=15
) (
    input wire I_clk, I_rst_n, I_enable, I_de,
    input wire [11:0] I_x, I_y,
    input wire [BLOCK_COLS*BLOCK_ROWS-1:0] I_blocks,
    output reg O_hit
);
    localparam integer PIXELS_PER_BLOCK=SAMPLE_STEP*(1<<BLOCK_SHIFT);
    wire [BLOCK_COLS-1:0] col_inside, col_edge;
    wire [BLOCK_ROWS-1:0] row_inside, row_edge;
    reg [BLOCK_COLS-1:0] selected_row;
    reg [BLOCK_COLS-1:0] row_q, col_q, edge_q;
    reg horizontal_edge_q, visible_q;
    genvar c,r;
    generate
        for(c=0;c<BLOCK_COLS;c=c+1) begin : g_col
            localparam integer X0=ROI_X_MIN+c*PIXELS_PER_BLOCK;
            localparam integer X1=(X0+PIXELS_PER_BLOCK-1>ROI_X_MAX)?ROI_X_MAX:X0+PIXELS_PER_BLOCK-1;
            assign col_inside[c]=(I_x>=X0 && I_x<=X1);
            assign col_edge[c]=col_inside[c] && (I_x<X0+2 || I_x>X1-2);
        end
        for(r=0;r<BLOCK_ROWS;r=r+1) begin : g_row
            localparam integer Y0=ROI_Y_MIN+r*PIXELS_PER_BLOCK;
            localparam integer Y1=(Y0+PIXELS_PER_BLOCK-1>ROI_Y_MAX)?ROI_Y_MAX:Y0+PIXELS_PER_BLOCK-1;
            assign row_inside[r]=(I_y>=Y0 && I_y<=Y1);
            assign row_edge[r]=row_inside[r] && (I_y<Y0+2 || I_y>Y1-2);
        end
    endgenerate
    integer i;
    always @(*) begin
        selected_row=0;
        for(i=0;i<BLOCK_ROWS;i=i+1)
            selected_row=selected_row | ({BLOCK_COLS{row_inside[i]}} & I_blocks[i*BLOCK_COLS +: BLOCK_COLS]);
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            row_q<=0;col_q<=0;edge_q<=0;horizontal_edge_q<=0;visible_q<=0;O_hit<=0;
        end else begin
            row_q<=selected_row;col_q<=col_inside;edge_q<=col_edge;
            horizontal_edge_q<=|row_edge;visible_q<=I_enable && I_de;
            O_hit<=visible_q && (|(row_q & col_q & (edge_q | {BLOCK_COLS{horizontal_edge_q}})));
        end
    end
endmodule
