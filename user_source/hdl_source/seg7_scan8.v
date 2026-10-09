`timescale 1ns / 1ns

module seg7_scan8 #(
    parameter integer SCAN_DIV = 24000,
    parameter SEG_ACTIVE_LOW = 1'b1,
    parameter SEL_ACTIVE_LOW = 1'b1
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire [15:0] I_param_a,
    input wire [15:0] I_param_b,
    output wire [7:0] O_DIG,
    output wire [7:0] O_SEL
);

reg [15:0] scan_count;
reg [2:0] scan_digit;
reg [7:0] seg_on;
reg [7:0] sel_on;
reg [3:0] digit_value;
    wire [19:0] param_a_bcd = bin16_to_bcd(I_param_a);
    wire [19:0] param_b_bcd = bin16_to_bcd(I_param_b);

function [19:0] bin16_to_bcd;
    input [15:0] value;
    integer bit_index;
    integer digit_index;
    reg [19:0] bcd;
    begin
        bcd = 20'd0;
        for (bit_index = 15; bit_index >= 0; bit_index = bit_index - 1) begin
            for (digit_index = 0; digit_index < 5; digit_index = digit_index + 1)
                if (bcd[digit_index * 4 +: 4] >= 4'd5)
                    bcd[digit_index * 4 +: 4] = bcd[digit_index * 4 +: 4] + 4'd3;
            bcd = {bcd[18:0], value[bit_index]};
        end
        bin16_to_bcd = bcd;
    end
endfunction

function [6:0] F_hex7seg;
    input [3:0] value;
    begin
        case (value)
            4'd0: F_hex7seg = 7'b0111111;
            4'd1: F_hex7seg = 7'b0000110;
            4'd2: F_hex7seg = 7'b1011011;
            4'd3: F_hex7seg = 7'b1001111;
            4'd4: F_hex7seg = 7'b1100110;
            4'd5: F_hex7seg = 7'b1101101;
            4'd6: F_hex7seg = 7'b1111101;
            4'd7: F_hex7seg = 7'b0000111;
            4'd8: F_hex7seg = 7'b1111111;
            4'd9: F_hex7seg = 7'b1101111;
            4'ha: F_hex7seg = 7'b1110111;
            4'hb: F_hex7seg = 7'b1111100;
            4'hc: F_hex7seg = 7'b0111001;
            4'hd: F_hex7seg = 7'b1011110;
            4'he: F_hex7seg = 7'b1111001;
            4'hf: F_hex7seg = 7'b1110001;
            default: F_hex7seg = 7'b0000000;
        endcase
    end
endfunction

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        scan_count <= 16'd0;
        scan_digit <= 3'd0;
    end else if (scan_count == SCAN_DIV - 1) begin
        scan_count <= 16'd0;
        scan_digit <= scan_digit + 1'b1;
    end else begin
        scan_count <= scan_count + 1'b1;
    end
end

always @(*) begin
    case (scan_digit)
        3'd0: digit_value = param_a_bcd[15:12];
        3'd1: digit_value = param_a_bcd[11:8];
        3'd2: digit_value = param_a_bcd[7:4];
        3'd3: digit_value = param_a_bcd[3:0];
        3'd4: digit_value = param_b_bcd[15:12];
        3'd5: digit_value = param_b_bcd[11:8];
        3'd6: digit_value = param_b_bcd[7:4];
        default: digit_value = param_b_bcd[3:0];
    endcase

    seg_on = {1'b0, F_hex7seg(digit_value)};
    if (scan_digit == 3'd3)
        seg_on[7] = 1'b1;
    sel_on = 8'b00000001 << scan_digit;
end

assign O_DIG = SEG_ACTIVE_LOW ? ~seg_on : seg_on;
assign O_SEL = SEL_ACTIVE_LOW ? ~sel_on : sel_on;

endmodule
