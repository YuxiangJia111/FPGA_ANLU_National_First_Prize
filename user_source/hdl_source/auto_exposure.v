`timescale 1ns / 1ns

module auto_exposure #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [23:0] I_ycbcr,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    output wire [23:0] O_ycbcr,
    output wire        O_vsync,
    output wire        O_hsync,
    output wire        O_de,
    output wire        O_user,
    output wire        O_last,
    output wire [1:0]  O_lut_select
);

    localparam [1:0] LUT_BRIGHTEN = 2'd0;
    localparam [1:0] LUT_NORMAL   = 2'd1;
    localparam [1:0] LUT_DARKEN   = 2'd2;

    localparam integer SAMPLE_COUNT = (IMG_WIDTH / 2) * (IMG_HEIGHT / 2);
    localparam integer DARK_ENTER   = (SAMPLE_COUNT * 40) / 100;
    localparam integer DARK_EXIT    = (SAMPLE_COUNT * 25) / 100;
    localparam integer BRIGHT_ENTER = (SAMPLE_COUNT * 25) / 100;
    localparam integer BRIGHT_EXIT  = (SAMPLE_COUNT * 15) / 100;

    reg [17:0] histogram [0:15];
    reg [17:0] dark_count;
    reg [17:0] bright_count;
    reg [10:0] pixel_x;
    reg        line_odd;
    reg        frame_seen;
    reg [1:0]  lut_select;
    reg [1:0]  dark_confirm;
    reg [1:0]  bright_confirm;
    integer i;

    wire [7:0] y_in = I_ycbcr[23:16];
    wire sample_pixel = I_de && !line_odd && !pixel_x[0];
    wire dark_scene = (dark_count >= DARK_ENTER) &&
                      (bright_count < (SAMPLE_COUNT * 15) / 100);
    wire bright_scene = (bright_count >= BRIGHT_ENTER) &&
                        (dark_count < (SAMPLE_COUNT * 20) / 100);

    wire [7:0] adjusted_y;
    wire [23:0] lut_ycbcr;

    y_lut u_y_lut (
        .lut_select (lut_select),
        .y_in       (y_in),
        .y_out      (adjusted_y)
    );

    assign lut_ycbcr = {adjusted_y, I_ycbcr[15:0]};
    assign O_ycbcr = lut_ycbcr;
    assign O_vsync = I_vsync;
    assign O_hsync = I_hsync;
    assign O_de    = I_de;
    assign O_user  = I_user;
    assign O_last  = I_last;
    assign O_lut_select = lut_select;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            dark_count    <= 18'd0;
            bright_count  <= 18'd0;
            pixel_x       <= 11'd0;
            line_odd      <= 1'b0;
            frame_seen    <= 1'b0;
            lut_select    <= LUT_NORMAL;
            dark_confirm  <= 2'd0;
            bright_confirm <= 2'd0;
            for (i = 0; i < 16; i = i + 1)
                histogram[i] <= 18'd0;
        end else begin
            // I_user marks the first valid pixel of a new frame. The old
            // frame's statistics are consumed before its counters are reset.
            if (I_user) begin
                if (frame_seen) begin
                    case (lut_select)
                        LUT_NORMAL: begin
                            if (dark_scene) begin
                                bright_confirm <= 2'd0;
                                if (dark_confirm == 2'd2) begin
                                    lut_select   <= LUT_BRIGHTEN;
                                    dark_confirm <= 2'd0;
                                end else begin
                                    dark_confirm <= dark_confirm + 1'b1;
                                end
                            end else if (bright_scene) begin
                                dark_confirm <= 2'd0;
                                if (bright_confirm == 2'd2) begin
                                    lut_select     <= LUT_DARKEN;
                                    bright_confirm <= 2'd0;
                                end else begin
                                    bright_confirm <= bright_confirm + 1'b1;
                                end
                            end else begin
                                dark_confirm   <= 2'd0;
                                bright_confirm <= 2'd0;
                            end
                        end
                        LUT_BRIGHTEN: begin
                            if (dark_count < DARK_EXIT) begin
                                if (bright_confirm == 2'd2) begin
                                    lut_select     <= LUT_NORMAL;
                                    bright_confirm <= 2'd0;
                                end else begin
                                    bright_confirm <= bright_confirm + 1'b1;
                                end
                            end else begin
                                bright_confirm <= 2'd0;
                            end
                        end
                        default: begin
                            if (bright_count < BRIGHT_EXIT) begin
                                if (dark_confirm == 2'd2) begin
                                    lut_select   <= LUT_NORMAL;
                                    dark_confirm <= 2'd0;
                                end else begin
                                    dark_confirm <= dark_confirm + 1'b1;
                                end
                            end else begin
                                dark_confirm <= 2'd0;
                            end
                        end
                    endcase
                end

                frame_seen   <= 1'b1;
                pixel_x      <= I_de ? 11'd1 : 11'd0;
                line_odd     <= 1'b0;
                dark_count   <= (I_de && (y_in < 64)) ? 18'd1 : 18'd0;
                bright_count <= (I_de && (y_in >= 224)) ? 18'd1 : 18'd0;
                for (i = 0; i < 16; i = i + 1)
                    histogram[i] <= 18'd0;
                if (I_de)
                    histogram[y_in[7:4]] <= 18'd1;
            end else begin
                if (sample_pixel) begin
                    histogram[y_in[7:4]] <= histogram[y_in[7:4]] + 1'b1;
                    if (y_in < 64)
                        dark_count <= dark_count + 1'b1;
                    if (y_in >= 224)
                        bright_count <= bright_count + 1'b1;
                end

                if (I_de)
                    pixel_x <= (pixel_x == IMG_WIDTH - 1) ? 11'd0 : pixel_x + 1'b1;
                if (I_last) begin
                    pixel_x  <= 11'd0;
                    line_odd <= ~line_odd;
                end
            end
        end
    end

endmodule
