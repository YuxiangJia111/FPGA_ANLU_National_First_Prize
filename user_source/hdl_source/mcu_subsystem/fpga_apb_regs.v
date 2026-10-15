`timescale 1ns / 1ps

module fpga_apb_regs #(
    parameter integer HEARTBEAT_TIMEOUT_CYCLES = 10000000,
    parameter integer UPTIME_DIVISOR = 50000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [19:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    input  wire [3:0]  pstrb,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    output wire        irq,
    output wire        safe_enable
);
    reg [31:0] scratch;
    reg [4:0]  irq_status;
    reg [4:0]  irq_enable;
    reg [31:0] heartbeat_last;
    reg [31:0] heartbeat_counter;
    reg        heartbeat_seen;
    reg        armed;
    reg        timeout_fault;
    reg [31:0] uptime_divider;
    reg [31:0] pl_uptime_ms;
    reg        valid_addr;
    integer lane;

    wire access = psel && penable;
    wire heartbeat_refresh = access && pwrite && !pslverr &&
                             (paddr == 20'h00020) && (|pstrb) &&
                             (!heartbeat_seen || pwdata != heartbeat_last);
    wire read_only = (paddr == 20'h00000 || paddr == 20'h00004 ||
                      paddr == 20'h00008 || paddr == 20'h0000C ||
                      paddr == 20'h00018 || paddr == 20'h0001C ||
                      paddr == 20'h00028);

    assign pready = 1'b1;
    assign pslverr = access && (!valid_addr || (pwrite && read_only));
    assign irq = |(irq_status & irq_enable);
    assign safe_enable = armed && !timeout_fault;

    always @(*) begin
        valid_addr = 1'b1;
        prdata = 32'd0;
        case (paddr)
            20'h00000: prdata = 32'h56504C43; // "VPLC"
            20'h00004: prdata = 32'h00020000; // S3 register map
            20'h00008: prdata = 32'h00030801; // 3 axes, 8 targets, tool present
            20'h0000C: prdata = 32'h20261015;
            20'h00010: prdata = {27'd0, irq_status};
            20'h00014: prdata = {27'd0, irq_enable};
            20'h00018: prdata = {28'd0, irq, heartbeat_seen,
                                  safe_enable, armed};
            20'h0001C: prdata = {31'd0, timeout_fault};
            20'h00020: prdata = heartbeat_last;
            20'h00024: prdata = {31'd0, armed};
            20'h00028: prdata = pl_uptime_ms;
            20'h0002C: prdata = 32'd0; // write-only debug IRQ injection
            20'h00030: prdata = scratch;
            default:   valid_addr = 1'b0;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            scratch <= 32'd0;
            irq_status <= 5'd0;
            irq_enable <= 5'd0;
            heartbeat_last <= 32'd0;
            heartbeat_counter <= 32'd0;
            heartbeat_seen <= 1'b0;
            armed <= 1'b0;
            timeout_fault <= 1'b0;
            uptime_divider <= 32'd0;
            pl_uptime_ms <= 32'd0;
        end else begin
            if (uptime_divider == UPTIME_DIVISOR - 1) begin
                uptime_divider <= 32'd0;
                pl_uptime_ms <= pl_uptime_ms + 32'd1;
            end else begin
                uptime_divider <= uptime_divider + 32'd1;
            end

            if (access && pwrite && !pslverr) begin
                case (paddr)
                    20'h00010: if (pstrb[0])
                        irq_status <= irq_status & ~pwdata[4:0];
                    20'h00014: if (pstrb[0])
                        irq_enable <= pwdata[4:0];
                    20'h00020: if (|pstrb) begin
                        if (!heartbeat_seen || pwdata != heartbeat_last)
                            heartbeat_counter <= 32'd0;
                        heartbeat_last <= pwdata;
                        heartbeat_seen <= 1'b1;
                    end
                    20'h00024: if (pstrb[0]) begin
                        if (pwdata[2])
                            armed <= 1'b0;
                        if (pwdata[1]) begin
                            timeout_fault <= 1'b0;
                            heartbeat_counter <= 32'd0;
                            irq_status[2] <= 1'b0;
                        end
                        if (pwdata[0] && heartbeat_seen && !timeout_fault) begin
                            armed <= 1'b1;
                            heartbeat_counter <= 32'd0;
                        end
                    end
                    20'h0002C: if (pstrb[0])
                        irq_status <= irq_status | pwdata[4:0];
                    20'h00030: for (lane = 0; lane < 4; lane = lane + 1)
                        if (pstrb[lane])
                            scratch[lane*8 +: 8] <= pwdata[lane*8 +: 8];
                    default: begin end
                endcase
            end

            if (armed && !timeout_fault) begin
                // A changed heartbeat has priority over the watchdog increment.
                // Without this branch, the later increment in this always block
                // overwrites the counter reset performed by the APB write case.
                if (heartbeat_refresh) begin
                    heartbeat_counter <= 32'd0;
                end else if (heartbeat_counter >= HEARTBEAT_TIMEOUT_CYCLES - 1) begin
                    timeout_fault <= 1'b1;
                    armed <= 1'b0;
                    irq_status[2] <= 1'b1;
                end else begin
                    heartbeat_counter <= heartbeat_counter + 32'd1;
                end
            end
        end
    end
endmodule
