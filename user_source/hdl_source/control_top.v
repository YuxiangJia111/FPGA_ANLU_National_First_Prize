`timescale 1ns / 1ns

module control_top (
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [3:0] I_key_n,
    input  wire [3:0] I_switch,
    output wire [3:0] O_key_event,
    output wire [3:0] O_switch_state,
    output wire [2:0] O_image_mode
);

    localparam [2:0] MODE_ORIGINAL = 3'b000;
    localparam [2:0] MODE_GRAY     = 3'b001;
    localparam [2:0] MODE_BINARY   = 3'b010;
    localparam [2:0] MODE_SOBEL    = 3'b011;
    localparam [2:0] MODE_AUTO_EXP = 3'b100;
    localparam [2:0] MODE_EQUALIZE = 3'b101;

    wire [3:0] key_event;
    reg  [3:0] switch_sync_1;
    reg  [3:0] switch_sync_2;
    reg  [2:0] selected_mode;

    key_remove_shakes u_key1_debounce (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_key_in       (I_key_n[0]),
        .O_key_trig_out (key_event[0])
    );

    key_remove_shakes u_key2_debounce (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_key_in       (I_key_n[1]),
        .O_key_trig_out (key_event[1])
    );

    key_remove_shakes u_key3_debounce (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_key_in       (I_key_n[2]),
        .O_key_trig_out (key_event[2])
    );

    key_remove_shakes u_key4_debounce (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_key_in       (I_key_n[3]),
        .O_key_trig_out (key_event[3])
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            switch_sync_1 <= 4'b0000;
            switch_sync_2 <= 4'b0000;
        end else begin
            switch_sync_1 <= I_switch;
            switch_sync_2 <= switch_sync_1;
        end
    end

    // KEY4 moves forward and KEY3 moves backward through active algorithms.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            selected_mode <= MODE_GRAY;
        else if(key_event[3]) begin
            case(selected_mode)
                MODE_GRAY:   selected_mode <= MODE_BINARY;
                MODE_BINARY: selected_mode <= MODE_SOBEL;
                MODE_SOBEL:  selected_mode <= MODE_AUTO_EXP;
                MODE_AUTO_EXP: selected_mode <= MODE_EQUALIZE;
                MODE_EQUALIZE: selected_mode <= MODE_GRAY;
                default:     selected_mode <= MODE_GRAY;
            endcase
        end else if(key_event[2]) begin
            case(selected_mode)
                MODE_GRAY:   selected_mode <= MODE_EQUALIZE;
                MODE_EQUALIZE: selected_mode <= MODE_AUTO_EXP;
                MODE_SOBEL:  selected_mode <= MODE_BINARY;
                MODE_BINARY: selected_mode <= MODE_GRAY;
                MODE_AUTO_EXP: selected_mode <= MODE_SOBEL;
                default:     selected_mode <= MODE_SOBEL;
            endcase
        end
    end

    assign O_key_event    = key_event;
    assign O_switch_state = switch_sync_2;
    assign O_image_mode   = switch_sync_2[3] ? MODE_ORIGINAL : selected_mode;

endmodule
