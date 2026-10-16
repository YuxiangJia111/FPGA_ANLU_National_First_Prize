`timescale 1ns / 1ns

module lcd_hw_test #(
    parameter CLK_HZ = 50000000,
    parameter SPI_DIV = 25,
    parameter FILL_COLOR = 16'hf800
) (
    input wire I_clk, input wire I_rst_n,
    output reg O_scl, output reg O_sda, output reg O_rst,
    output reg O_dc, output reg O_cs,
    output wire O_init_done, output wire O_done
);
    localparam S_RST_LOW=3'd0, S_RST_WAIT=3'd1, S_LOAD=3'd2,
               S_SEND=3'd3, S_DELAY=3'd4, S_FILL=3'd5, S_DONE=3'd6;
    localparam TICKS_PER_MS = CLK_HZ / SPI_DIV / 1000;
    reg [2:0] state;
    reg [5:0] divider;
    reg [18:0] delay_count;
    reg [6:0] init_index;
    reg [7:0] tx_data;
    reg [2:0] bit_index;
    reg [1:0] phase;
    reg [16:0] pixel_count;
    reg pixel_low;
    wire tick = (divider == SPI_DIV - 1);

    assign O_init_done = (init_index >= 7'd62) && (state >= S_LOAD);
    assign O_done = (state == S_DONE);

    function init_dc;
        input [6:0] index;
        begin
            case (index)
                0,1,2,4,6,12,14,16,18,20,22,24,26,29,44,59,60,61,62,67,72: init_dc=1'b0;
                default: init_dc=1'b1;
            endcase
        end
    endfunction

    function [7:0] init_byte;
        input [6:0] index;
        begin
            case (index)
              0:init_byte=8'h01; 1:init_byte=8'h11; 2:init_byte=8'h36; 3:init_byte=8'h00;
              4:init_byte=8'h3a; 5:init_byte=8'h55; 6:init_byte=8'hb2; 7:init_byte=8'h0c;
              8:init_byte=8'h0c; 9:init_byte=8'h00; 10:init_byte=8'h33; 11:init_byte=8'h33;
              12:init_byte=8'hb7; 13:init_byte=8'h35; 14:init_byte=8'hbb; 15:init_byte=8'h19;
              16:init_byte=8'hc0; 17:init_byte=8'h2c; 18:init_byte=8'hc2; 19:init_byte=8'h01;
              20:init_byte=8'hc3; 21:init_byte=8'h12; 22:init_byte=8'hc4; 23:init_byte=8'h20;
              24:init_byte=8'hc6; 25:init_byte=8'h0f; 26:init_byte=8'hd0; 27:init_byte=8'ha4;
              28:init_byte=8'ha1; 29:init_byte=8'he0; 30:init_byte=8'hd0; 31:init_byte=8'h04;
              32:init_byte=8'h0d; 33:init_byte=8'h11; 34:init_byte=8'h13; 35:init_byte=8'h2b;
              36:init_byte=8'h3f; 37:init_byte=8'h54; 38:init_byte=8'h4c; 39:init_byte=8'h18;
              40:init_byte=8'h0d; 41:init_byte=8'h0b; 42:init_byte=8'h1f; 43:init_byte=8'h23;
              44:init_byte=8'he1; 45:init_byte=8'hd0; 46:init_byte=8'h04; 47:init_byte=8'h0c;
              48:init_byte=8'h11; 49:init_byte=8'h13; 50:init_byte=8'h2c; 51:init_byte=8'h3f;
              52:init_byte=8'h44; 53:init_byte=8'h51; 54:init_byte=8'h2f; 55:init_byte=8'h1f;
              56:init_byte=8'h1f; 57:init_byte=8'h20; 58:init_byte=8'h23; 59:init_byte=8'h20;
              60:init_byte=8'h13; 61:init_byte=8'h29; 62:init_byte=8'h2a; 63:init_byte=8'h00;
              64:init_byte=8'h00; 65:init_byte=8'h00; 66:init_byte=8'hef; 67:init_byte=8'h2b;
              68:init_byte=8'h00; 69:init_byte=8'h00; 70:init_byte=8'h01; 71:init_byte=8'h3f;
              default:init_byte=8'h2c;
            endcase
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state<=S_RST_LOW; divider<=0; delay_count<=0; init_index<=0;
            tx_data<=0; bit_index<=0; phase<=0; pixel_count<=0; pixel_low<=0;
            O_scl<=0; O_sda<=0; O_rst<=0; O_dc<=1; O_cs<=1;
        end else if (!tick) divider <= divider + 1'b1;
        else begin
            divider <= 0;
            case (state)
              S_RST_LOW: begin O_rst<=0;
                if (delay_count == TICKS_PER_MS*20-1) begin delay_count<=0; O_rst<=1; state<=S_RST_WAIT; end
                else delay_count<=delay_count+1'b1;
              end
              S_RST_WAIT: begin
                if (delay_count == TICKS_PER_MS*120-1) begin delay_count<=0; init_index<=0; state<=S_LOAD; end
                else delay_count<=delay_count+1'b1;
              end
              S_LOAD: begin tx_data<=init_byte(init_index); O_dc<=init_dc(init_index); O_cs<=0; O_scl<=0; bit_index<=7; phase<=0; state<=S_SEND; end
              S_SEND: begin
                if (phase==0) begin O_sda<=tx_data[bit_index]; O_scl<=0; phase<=1; end
                else if (phase==1) begin O_scl<=1; phase<=2; end
                else begin
                    O_scl<=0; phase<=0;
                    if (bit_index!=0) bit_index<=bit_index-1'b1;
                    else begin
                        O_cs<=1;
                        if (init_index==0 || init_index==1 || init_index==61) begin delay_count<=0; state<=S_DELAY; end
                        else if (init_index==72) begin O_dc<=1; O_cs<=0; tx_data<=FILL_COLOR[15:8]; bit_index<=7; pixel_count<=0; pixel_low<=0; state<=S_FILL; end
                        else begin init_index<=init_index+1'b1; state<=S_LOAD; end
                    end
                end
              end
              S_DELAY: begin
                if ((init_index==0 && delay_count==TICKS_PER_MS*150-1) ||
                    (init_index==1 && delay_count==TICKS_PER_MS*120-1) ||
                    (init_index==61 && delay_count==TICKS_PER_MS*20-1)) begin
                    delay_count<=0; init_index<=init_index+1'b1; state<=S_LOAD;
                end else delay_count<=delay_count+1'b1;
              end
              S_FILL: begin
                if (phase==0) begin O_sda<=tx_data[bit_index]; O_scl<=0; phase<=1; end
                else if (phase==1) begin O_scl<=1; phase<=2; end
                else begin
                    O_scl<=0; phase<=0;
                    if (bit_index!=0) bit_index<=bit_index-1'b1;
                    else if (!pixel_low) begin pixel_low<=1; tx_data<=FILL_COLOR[7:0]; bit_index<=7; end
                    else if (pixel_count==17'd76799) begin O_cs<=1; state<=S_DONE; end
                    else begin pixel_count<=pixel_count+1'b1; pixel_low<=0; tx_data<=FILL_COLOR[15:8]; bit_index<=7; end
                end
              end
              default: begin O_scl<=0; O_cs<=1; O_dc<=1; O_rst<=1; end
            endcase
        end
    end
endmodule
