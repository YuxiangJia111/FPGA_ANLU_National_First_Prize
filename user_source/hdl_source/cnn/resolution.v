// RTL source: resolution.
module resolution (
    input hdmi_clk,
    input rst_n,
    input [15:0] rd_data,
    input hdmi_rd_en,
    output [15:0] data_out,
    output reg gray_clk,
    output reg reso_en,
    output [11:0] x_t_img,
    output [11:0] y_t_img
);

    parameter mid = 'b10;

    parameter x_imgin_end = 12'd1279;
    parameter y_imgin_end = 12'd719;

    parameter x_imgout_start = 12'd159;
    parameter x_imgout_end = 12'd1119;
    parameter y_imgout_start = 12'd0;
    parameter y_imgout_end = 12'd719;

    reg [ 2:0] i;
    reg [ 2:0] j;
    reg [15:0] d_out;

    reg [11:0] x_img;
    reg [11:0] y_img;

    reg        start_img_out;

    assign data_out = d_out;
    assign x_t_img  = x_img;
    assign y_t_img  = y_img;

    initial begin

        gray_clk = 0;
        i        = 0;
        j        = 0;
        d_out    = 0;
        x_img    = 0;
        y_img    = 0;
        reso_en  = 0;

    end

    always @(posedge hdmi_clk or negedge rst_n) begin

        if (!rst_n) begin

            gray_clk = 0;
            i        = 0;
            d_out    = 0;

        end else begin
            if (hdmi_rd_en) begin
                if (start_img_out) begin

                    if (i == mid && j == mid) begin
                        d_out <= rd_data;

                        reso_en = 1;
                        gray_clk <= 1;
                    end

                end

                if (x_img == x_imgin_end) begin
                    x_img <= 10'd0;

                    if (y_img == y_imgin_end) begin
                        reso_en = 0;
                        y_img <= 10'd0;
                    end else begin
                        y_img <= y_img + 1'b1;
                        j     <= j + 1'b1;
                        if (j > 'd1) j <= 0;
                    end
                end else begin
                    x_img <= x_img + 1'b1;
                    i     <= i + 1'b1;
                    if (i > 'd1) i <= 0;
                    if (i == 'd1) gray_clk <= 0;
                end

                if ((x_img >= x_imgout_start) && (x_img <= x_imgout_end)&&(y_img >= y_imgout_start)&&(y_img <= y_imgout_end))
                    start_img_out = 1'b1;
                else start_img_out = 1'b0;
                if (y_img == y_imgin_end) begin
                    i <= 0;
                    j <= 0;
                end

            end
        end

    end

endmodule

