module lcd_status_bridge (
    input wire I_sys_clk, input wire I_hdmi_clk, input wire I_rst_n,
    input wire [31:0] I_latency_us, input wire I_latency_valid,
    output reg [15:0] O_latency_ms, output reg O_latency_valid
);
    reg [31:0] status_payload;
    reg status_valid;
    reg status_req_toggle;
    reg ack_sync_1, ack_sync_2;
    reg [31:0] payload_sync_1, payload_sync_2;
    reg valid_sync_1, valid_sync_2;
    reg req_sync_1, req_sync_2;
    reg status_req_seen;
    reg ack_toggle;
    reg [31:0] dividend, quotient;
    reg [10:0] remainder;
    reg [5:0] divide_count;
    reg dividing;
    wire [10:0] shifted_remainder = {remainder[9:0], dividend[31]};
    wire [31:0] quotient_current = quotient |
                                   ((shifted_remainder >= 11'd1000) ?
                                    (32'd1 << (31-divide_count)) : 32'd0);

    always @(posedge I_hdmi_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ack_sync_1<=0; ack_sync_2<=0;
            status_payload<=0; status_valid<=0; status_req_toggle<=0;
        end else begin
            ack_sync_1<=ack_toggle;
            ack_sync_2<=ack_sync_1;
            if ((ack_sync_2 == status_req_toggle) &&
                ((I_latency_valid != status_valid) ||
                 (I_latency_valid && (I_latency_us != status_payload)))) begin
                status_payload<=I_latency_us;
                status_valid<=I_latency_valid;
                status_req_toggle<=~status_req_toggle;
            end
        end
    end

    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            payload_sync_1<=0; payload_sync_2<=0;
            valid_sync_1<=0; valid_sync_2<=0;
            req_sync_1<=0; req_sync_2<=0;
            status_req_seen<=0; ack_toggle<=0;
            dividend<=0; quotient<=0;
            remainder<=0; divide_count<=0; dividing<=0;
            O_latency_ms<=0; O_latency_valid<=0;
        end else begin
            payload_sync_1<=status_payload;
            payload_sync_2<=payload_sync_1;
            valid_sync_1<=status_valid;
            valid_sync_2<=valid_sync_1;
            req_sync_1<=status_req_toggle;
            req_sync_2<=req_sync_1;
            if (!dividing && (req_sync_2 != status_req_seen)) begin
                status_req_seen<=req_sync_2;
                ack_toggle<=req_sync_2;
                if (valid_sync_2) begin
                    dividend<=payload_sync_2; quotient<=0;
                    remainder<=0; divide_count<=0; dividing<=1;
                end else begin
                    O_latency_valid<=0;
                end
            end else if (dividing) begin
                dividend <= {dividend[30:0],1'b0};
                if (shifted_remainder >= 11'd1000) begin
                    remainder <= shifted_remainder - 11'd1000;
                    quotient[31-divide_count] <= 1'b1;
                end else remainder <= shifted_remainder;
                if (divide_count == 6'd31) begin
                    if (|quotient_current[31:16]) O_latency_ms<=16'hffff;
                    else O_latency_ms<=quotient_current[15:0];
                    O_latency_valid<=1; dividing<=0;
                end else divide_count<=divide_count+1'b1;
            end
        end
    end
endmodule
