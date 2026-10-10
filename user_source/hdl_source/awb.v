// Resource-efficient automatic white balance for four RGB888 pixels/clock.
//
// The original demo launched two fully-pipelined 48/32 dividers on every
// valid pixel and delayed the complete 96-bit stream by 50 clocks. AWB gains
// are frame statistics, so those per-pixel divisions are unnecessary. This
// implementation accumulates the same gray-world statistics, performs the R
// and B gain divisions sequentially during vertical blanking, and applies the
// completed gains to the following frame.
module awb #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920
)(
    input                   I_clk,
    input                   I_rst_n,
    input                   I_tlast,
    input                   I_tuser,
    input      [95:0]       I_tdata,
    input                   I_tvalid,
    output                  I_tready,
    output reg              O_tlast,
    output reg              O_tuser,
    output     [95:0]       O_tdata,
    output reg              O_tvalid,
    input                   O_tready
);

    localparam [1:0] DIV_IDLE = 2'd0;
    localparam [1:0] DIV_RED  = 2'd1;
    localparam [1:0] DIV_BLUE = 2'd2;

    wire [7:0] pixel_r0 = I_tdata[16+:8];
    wire [7:0] pixel_g0 = I_tdata[8+:8];
    wire [7:0] pixel_b0 = I_tdata[0+:8];
    wire [7:0] pixel_r1 = I_tdata[40+:8];
    wire [7:0] pixel_g1 = I_tdata[32+:8];
    wire [7:0] pixel_b1 = I_tdata[24+:8];
    wire [7:0] pixel_r2 = I_tdata[64+:8];
    wire [7:0] pixel_g2 = I_tdata[56+:8];
    wire [7:0] pixel_b2 = I_tdata[48+:8];
    wire [7:0] pixel_r3 = I_tdata[88+:8];
    wire [7:0] pixel_g3 = I_tdata[80+:8];
    wire [7:0] pixel_b3 = I_tdata[72+:8];

    // Preserve the demo's highlight rejection and its one-pixel-per-clock
    // sampling rate. The other three pixels still receive the same gain.
    wire [9:0] sample_sum = pixel_r0 + pixel_g0 + pixel_b0;
    wire       sample_en  = I_tvalid && (sample_sum < 10'd720);

    reg [31:0] sum_r;
    reg [31:0] sum_g;
    reg [31:0] sum_b;
    reg [10:0] line_count;
    reg        div_request;
    reg [47:0] request_numerator;
    reg [31:0] request_red_denominator;
    reg [31:0] request_blue_denominator;

    wire [31:0] sum_r_with_sample = sum_r + (sample_en ? pixel_r0 : 8'd0);
    wire [31:0] sum_g_with_sample = sum_g + (sample_en ? pixel_g0 : 8'd0);
    wire [31:0] sum_b_with_sample = sum_b + (sample_en ? pixel_b0 : 8'd0);

    // Statistics are finalized at the last line. Two divisions then take 96
    // clocks total, comfortably inside the normal vertical blanking.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            sum_r <= 32'd1;
            sum_g <= 32'd1;
            sum_b <= 32'd1;
            line_count <= 11'd0;
            div_request <= 1'b0;
            request_numerator <= 48'd0;
            request_red_denominator <= 32'd1;
            request_blue_denominator <= 32'd1;
        end else begin
            div_request <= 1'b0;
            if(I_tuser) begin
                sum_r <= 32'd1;
                sum_g <= 32'd1;
                sum_b <= 32'd1;
                line_count <= 11'd0;
            end else if(I_tvalid) begin
                if(sample_en) begin
                    sum_r <= sum_r_with_sample;
                    sum_g <= sum_g_with_sample;
                    sum_b <= sum_b_with_sample;
                end
                if(I_tlast) begin
                    if(line_count == IMG_HEIGHT - 1) begin
                        line_count <= 11'd0;
                        request_numerator <= {sum_g_with_sample, 16'd0};
                        request_red_denominator <= sum_r_with_sample;
                        request_blue_denominator <= sum_b_with_sample;
                        div_request <= 1'b1;
                    end else begin
                        line_count <= line_count + 11'd1;
                    end
                end
            end
        end
    end

    // Shared restoring divider. Only the low 20 quotient bits are useful
    // (Q4.16); larger results saturate exactly like the original demo.
    reg [1:0]  div_state;
    reg [5:0]  div_bit_count;
    reg [47:0] div_shift_numerator;
    reg [31:0] div_denominator;
    reg [32:0] div_remainder;
    reg [47:0] div_quotient;
    reg [47:0] blue_numerator;
    reg [31:0] blue_denominator;
    reg [19:0] red_result;
    reg [19:0] gain_r;
    reg [19:0] gain_b;
    reg [19:0] pending_gain_r;
    reg [19:0] pending_gain_b;
    reg        pending_gain_valid;

    wire [32:0] div_trial_remainder =
        {div_remainder[31:0], div_shift_numerator[47]};
    wire        div_trial_ge =
        (div_trial_remainder >= {1'b0, div_denominator});
    wire [32:0] div_next_remainder = div_trial_ge ?
        (div_trial_remainder - {1'b0, div_denominator}) :
        div_trial_remainder;
    wire [47:0] div_next_quotient =
        {div_quotient[46:0], div_trial_ge};

    function [19:0] clamp_gain;
        input [47:0] quotient;
        begin
            clamp_gain = (|quotient[47:20]) ? 20'hfffff : quotient[19:0];
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            div_state <= DIV_IDLE;
            div_bit_count <= 6'd0;
            div_shift_numerator <= 48'd0;
            div_denominator <= 32'd1;
            div_remainder <= 33'd0;
            div_quotient <= 48'd0;
            blue_numerator <= 48'd0;
            blue_denominator <= 32'd1;
            red_result <= 20'h10000;
            gain_r <= 20'h10000;
            gain_b <= 20'h10000;
            pending_gain_r <= 20'h10000;
            pending_gain_b <= 20'h10000;
            pending_gain_valid <= 1'b0;
        end else begin
            // Commit both gains at a frame boundary so a displayed frame
            // never contains two different AWB settings.
            if(I_tuser && pending_gain_valid) begin
                gain_r <= pending_gain_r;
                gain_b <= pending_gain_b;
                pending_gain_valid <= 1'b0;
            end

            if((div_state == DIV_IDLE) && div_request) begin
                div_state <= DIV_RED;
                div_bit_count <= 6'd47;
                div_shift_numerator <= request_numerator;
                div_denominator <= request_red_denominator;
                div_remainder <= 33'd0;
                div_quotient <= 48'd0;
                blue_numerator <= request_numerator;
                blue_denominator <= request_blue_denominator;
            end else if(div_state != DIV_IDLE) begin
                div_shift_numerator <= {div_shift_numerator[46:0], 1'b0};
                div_remainder <= div_next_remainder;
                div_quotient <= div_next_quotient;
                if(div_bit_count == 0) begin
                    if(div_state == DIV_RED) begin
                        red_result <= clamp_gain(div_next_quotient);
                        div_state <= DIV_BLUE;
                        div_bit_count <= 6'd47;
                        div_shift_numerator <= blue_numerator;
                        div_denominator <= blue_denominator;
                        div_remainder <= 33'd0;
                        div_quotient <= 48'd0;
                    end else begin
                        pending_gain_r <= red_result;
                        pending_gain_b <= clamp_gain(div_next_quotient);
                        pending_gain_valid <= 1'b1;
                        div_state <= DIV_IDLE;
                    end
                end else begin
                    div_bit_count <= div_bit_count - 6'd1;
                end
            end
        end
    end

    reg [27:0] scaled_r0, scaled_b0;
    reg [27:0] scaled_r1, scaled_b1;
    reg [27:0] scaled_r2, scaled_b2;
    reg [27:0] scaled_r3, scaled_b3;
    reg [7:0] delayed_g0, delayed_g1, delayed_g2, delayed_g3;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            scaled_r0 <= 28'd0;
            scaled_b0 <= 28'd0;
            scaled_r1 <= 28'd0;
            scaled_b1 <= 28'd0;
            scaled_r2 <= 28'd0;
            scaled_b2 <= 28'd0;
            scaled_r3 <= 28'd0;
            scaled_b3 <= 28'd0;
            delayed_g0 <= 8'd0;
            delayed_g1 <= 8'd0;
            delayed_g2 <= 8'd0;
            delayed_g3 <= 8'd0;
            O_tvalid <= 1'b0;
            O_tuser <= 1'b0;
            O_tlast <= 1'b0;
        end else begin
            O_tvalid <= I_tvalid;
            O_tuser <= I_tuser;
            O_tlast <= I_tlast;
            if(I_tvalid) begin
                scaled_r0 <= gain_r * pixel_r0;
                scaled_b0 <= gain_b * pixel_b0;
                scaled_r1 <= gain_r * pixel_r1;
                scaled_b1 <= gain_b * pixel_b1;
                scaled_r2 <= gain_r * pixel_r2;
                scaled_b2 <= gain_b * pixel_b2;
                scaled_r3 <= gain_r * pixel_r3;
                scaled_b3 <= gain_b * pixel_b3;
                delayed_g0 <= pixel_g0;
                delayed_g1 <= pixel_g1;
                delayed_g2 <= pixel_g2;
                delayed_g3 <= pixel_g3;
            end
        end
    end

    wire [7:0] out_r0 = (|scaled_r0[27:24]) ? 8'hff : scaled_r0[23:16];
    wire [7:0] out_b0 = (|scaled_b0[27:24]) ? 8'hff : scaled_b0[23:16];
    wire [7:0] out_r1 = (|scaled_r1[27:24]) ? 8'hff : scaled_r1[23:16];
    wire [7:0] out_b1 = (|scaled_b1[27:24]) ? 8'hff : scaled_b1[23:16];
    wire [7:0] out_r2 = (|scaled_r2[27:24]) ? 8'hff : scaled_r2[23:16];
    wire [7:0] out_b2 = (|scaled_b2[27:24]) ? 8'hff : scaled_b2[23:16];
    wire [7:0] out_r3 = (|scaled_r3[27:24]) ? 8'hff : scaled_r3[23:16];
    wire [7:0] out_b3 = (|scaled_b3[27:24]) ? 8'hff : scaled_b3[23:16];

    assign O_tdata = O_tvalid ?
        {out_r3, delayed_g3, out_b3,
         out_r2, delayed_g2, out_b2,
         out_r1, delayed_g1, out_b1,
         out_r0, delayed_g0, out_b0} : 96'd0;
    assign I_tready = O_tready;

    wire _unused_img_width = (IMG_WIDTH == 0);

endmodule
