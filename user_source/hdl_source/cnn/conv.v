// RTL source: conv.
module conv (
    clk,
    Y1,
    prov,
    matrix,
    matrix2,
    i,
    w1,
    w2,
    w3,
    w4,
    w5,
    w6,
    w7,
    w8,
    w9,
    w11,
    w12,
    w13,
    w14,
    w15,
    w16,
    w17,
    w18,
    w19,
    conv_en,
    dense_en
);
    parameter SIZE = 23;
    input clk;
    output reg signed [SIZE+SIZE-2:0] Y1;
    input [1:0] prov;
    input [4:0] matrix;
    input [9:0] matrix2;
    input [9:0] i;
    input signed [SIZE-1:0] w1, w2, w3, w4, w5, w6, w7, w8, w9;
    input signed [SIZE-1:0] w11, w12, w13, w14, w15, w16, w17, w18, w19;
    input conv_en;
    input dense_en;

    // Keep one product in LUT fabric so the complete design fits the 40-DSP device.
    (* dsp_style = "no" *) wire signed [SIZE+SIZE-2:0] Y_logic;
    assign Y_logic = w1 * w11;

    always @(posedge clk) begin
        if (conv_en == 1) begin
            Y1 = 0;
            Y1 = Y1 + Y_logic;

            if ((prov != 2'b10) || (dense_en == 1)) begin
                Y1 = Y1 + Y(w2, w12);
            end

            if ((prov != 2'b11) || (dense_en == 1)) begin
                Y1 = Y1 + Y(w3, w13);
            end

            if (((i < matrix2 - matrix) && (prov != 2'b11)) || (dense_en == 1)) begin
                Y1 = Y1 + Y(w4, w14);
            end

            if (((i > matrix - 1'b1) && (prov != 2'b10)) || (dense_en == 1)) begin
                Y1 = Y1 + Y(w5, w15);
            end

            if ((i < matrix2 - matrix) || (dense_en == 1)) begin
                Y1 = Y1 + Y(w6, w16);
            end

            if ((i > matrix - 1'b1) || (dense_en == 1)) begin
                Y1 = Y1 + Y(w7, w17);
            end

            if (((i < matrix2 - matrix) && (prov != 2'b10)) || (dense_en == 1)) begin
                Y1 = Y1 + Y(w8, w18);
            end

            if (((i > matrix - 1'b1) && (prov != 2'b11)) || (dense_en == 1)) begin
                Y1 = Y1 + Y(w9, w19);
            end
        end
    end

    function signed [SIZE+SIZE-2:0] Y;
        input signed [SIZE-1:0] a, b;
        begin
            Y = a * b;
        end
    endfunction

endmodule
