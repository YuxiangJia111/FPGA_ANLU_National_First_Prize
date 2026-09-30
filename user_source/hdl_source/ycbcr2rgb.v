`timescale 1ns / 1ns

module ycbcr2rgb (
    input  wire [23:0] I_ycbcr,
    output reg  [23:0] O_rgb
);

    integer y_value;
    integer cb_offset;
    integer cr_offset;
    integer red_value;
    integer green_value;
    integer blue_value;

    function [7:0] clip8;
        input integer value;
        begin
            if (value < 0)
                clip8 = 8'd0;
            else if (value > 255)
                clip8 = 8'd255;
            else
                clip8 = value[7:0];
        end
    endfunction

    always @(*) begin
        y_value   = I_ycbcr[23:16];
        cb_offset = I_ycbcr[15:8] - 128;
        cr_offset = I_ycbcr[7:0] - 128;

        // Coefficients are scaled by 256 and implemented with shifts.
        red_value   = y_value + ((cr_offset * 359) >>> 8);
        green_value = y_value - ((cb_offset * 88) >>> 8)
                            - ((cr_offset * 183) >>> 8);
        blue_value  = y_value + ((cb_offset * 454) >>> 8);

        O_rgb = {clip8(red_value), clip8(green_value), clip8(blue_value)};
    end

endmodule
