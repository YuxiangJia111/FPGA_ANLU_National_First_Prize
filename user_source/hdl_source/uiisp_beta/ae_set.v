`timescale 1ns / 1ns

module ae_set (
    input wire I_clk,
    input wire I_rst,
    input wire [3:0] I_key_n,
    input wire I_ae_cfg_done,
    input wire I_cam_cfg_done,
    output wire O_ae_req,
    output wire [15:0] O_ae,
    output wire [15:0] O_ag
);

localparam [15:0] AE_DEFAULT = 16'd1900;
localparam [15:0] AG_DEFAULT = 16'd89;
localparam [15:0] AE_MIN = 16'd3;
localparam [15:0] AE_MAX = 16'd1900;
localparam [15:0] AG_MIN = 16'd16;
localparam [15:0] AG_MAX = 16'd89;

reg [3:0] key_sync_1;
reg [3:0] key_sync_2;
reg [3:0] key_stable_pressed;
reg [4:0] key_debounce_count [0:3];
reg [3:0] key_press;
reg [14:0] debounce_sample_count;
reg [15:0] r_ae_set;
reg [15:0] r_ag_set;
reg [15:0] r_ae;
reg [15:0] r_ag;
reg r_ae_req;
integer i;

assign O_ae = r_ae;
assign O_ag = r_ag;
assign O_ae_req = r_ae_req;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        key_sync_1 <= 4'hf;
        key_sync_2 <= 4'hf;
        key_stable_pressed <= 4'b0000;
        key_press <= 4'b0000;
        debounce_sample_count <= 15'd0;
        for (i = 0; i < 4; i = i + 1)
            key_debounce_count[i] <= 5'd0;
    end else begin
        key_sync_1 <= I_key_n;
        key_sync_2 <= key_sync_1;
        key_press <= 4'b0000;
        if (debounce_sample_count == 15'd23999) begin
            debounce_sample_count <= 15'd0;
            for (i = 0; i < 4; i = i + 1) begin
                if ((~key_sync_2[i]) == key_stable_pressed[i]) begin
                    key_debounce_count[i] <= 5'd0;
                end else if (key_debounce_count[i] == 5'd19) begin
                    key_debounce_count[i] <= 5'd0;
                    key_stable_pressed[i] <= ~key_sync_2[i];
                    if (!key_sync_2[i])
                        key_press[i] <= 1'b1;
                end else begin
                    key_debounce_count[i] <= key_debounce_count[i] + 1'b1;
                end
            end
        end else begin
            debounce_sample_count <= debounce_sample_count + 1'b1;
        end
    end
end

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        r_ae_set <= AE_DEFAULT;
        r_ag_set <= AG_DEFAULT;
    end else begin
        if (key_press[0]) begin
            if (r_ae_set <= AE_MAX - 16'd50)
                r_ae_set <= r_ae_set + 16'd50;
            else
                r_ae_set <= AE_MAX;
        end else if (key_press[1]) begin
            if (r_ae_set >= AE_MIN + 16'd50)
                r_ae_set <= r_ae_set - 16'd50;
            else
                r_ae_set <= AE_MIN;
        end

        if (key_press[2] && (r_ag_set < AG_MAX))
            r_ag_set <= r_ag_set + 1'b1;
        else if (key_press[3] && (r_ag_set > AG_MIN))
            r_ag_set <= r_ag_set - 1'b1;
    end
end

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        r_ae_req <= 1'b0;
        r_ae <= 16'd0;
        r_ag <= 16'd0;
    end else if (r_ae_req) begin
        r_ae_req <= 1'b0;
    end else if (((r_ae != r_ae_set) || (r_ag != r_ag_set)) &&
                 I_cam_cfg_done && I_ae_cfg_done) begin
        r_ae <= r_ae_set;
        r_ag <= r_ag_set;
        r_ae_req <= 1'b1;
    end
end

endmodule
