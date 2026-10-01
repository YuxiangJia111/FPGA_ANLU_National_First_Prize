`timescale 1ns / 1ns

module y_lut (
    input  wire [1:0] lut_select,
    input  wire [7:0] y_in,
    output reg  [7:0] y_out
);
    reg [7:0] lut_rom [0:767];
    integer i;

    function [7:0] brighten_curve;
        input integer value;
        integer result;
        begin
            if (value < 32) result = (value * 3) / 2;
            else if (value < 64) result = 48 + ((value - 32) * 36) / 32;
            else if (value < 96) result = 84 + ((value - 64) * 32) / 32;
            else if (value < 128) result = 116 + ((value - 96) * 32) / 32;
            else if (value < 160) result = 148 + ((value - 128) * 28) / 32;
            else if (value < 192) result = 176 + ((value - 160) * 28) / 32;
            else if (value < 224) result = 204 + ((value - 192) * 28) / 32;
            else result = 232 + ((value - 224) * 23) / 31;
            brighten_curve = (result > 255) ? 8'hff : result[7:0];
        end
    endfunction

    function [7:0] darken_curve;
        input integer value;
        integer result;
        begin
            if (value < 32) result = (value * 3) / 4;
            else if (value < 64) result = 24 + ((value - 32) * 24) / 32;
            else if (value < 96) result = 48 + ((value - 64) * 32) / 32;
            else if (value < 128) result = 80 + ((value - 96) * 32) / 32;
            else if (value < 160) result = 112 + ((value - 128) * 32) / 32;
            else if (value < 192) result = 144 + ((value - 160) * 32) / 32;
            else if (value < 224) result = 176 + ((value - 192) * 32) / 32;
            else result = 208 + ((value - 224) * 32) / 31;
            darken_curve = (result > 255) ? 8'hff : result[7:0];
        end
    endfunction

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            lut_rom[i]       = brighten_curve(i);
            lut_rom[256 + i] = i[7:0];
            lut_rom[512 + i] = darken_curve(i);
        end
    end

    always @(*) begin
        case (lut_select)
            2'd0: y_out = lut_rom[y_in];
            2'd2: y_out = lut_rom[512 + y_in];
            default: y_out = lut_rom[256 + y_in];
        endcase
    end
endmodule
