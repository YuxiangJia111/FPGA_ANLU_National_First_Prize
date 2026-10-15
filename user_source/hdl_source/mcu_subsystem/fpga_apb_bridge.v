`timescale 1ns / 1ps

// CPU AHB mailbox 0x80000100..0x80000114 -> FPGA 20-bit APB register space.
// This is the same single-outstanding-request bridge proven in FPGA_MCU.
module fpga_apb_bridge #(
    parameter integer HEARTBEAT_TIMEOUT_CYCLES = 10000000,
    parameter integer UPTIME_DIVISOR = 50000
) (
    input  wire        ahb_clk,
    input  wire        ahb_reset,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [30:0] haddr,
    input  wire [2:0]  hsize,
    input  wire [31:0] hwdata,
    output reg  [31:0] hrdata,
    input  wire        apb_clk,
    input  wire        apb_reset,
    output wire        irq,
    output wire        safe_enable
);
    reg        data_valid;
    reg        data_write;
    reg [4:0]  data_addr;
    reg [19:0] address;
    reg [31:0] write_data;
    reg [3:0]  strobes;
    reg        request_write;
    reg        request_toggle;
    reg        busy;
    reg        done;
    reg        last_error;
    reg [31:0] read_data;
    reg [1:0]  ack_sync;
    reg [1:0]  request_sync;
    reg        ack_toggle;
    reg [31:0] response_data;
    reg        response_error;
    reg [1:0]  state;

    localparam IDLE = 2'd0;
    localparam SETUP = 2'd1;
    localparam ACCESS = 2'd2;

    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire        psel = (state != IDLE);
    wire        penable = (state == ACCESS);

    fpga_apb_regs #(
        .HEARTBEAT_TIMEOUT_CYCLES(HEARTBEAT_TIMEOUT_CYCLES),
        .UPTIME_DIVISOR(UPTIME_DIVISOR)
    ) u_regs (
        .clk(apb_clk),
        .reset(apb_reset),
        .paddr(address),
        .psel(psel),
        .penable(penable),
        .pwrite(request_write),
        .pwdata(write_data),
        .pstrb(strobes),
        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),
        .irq(irq),
        .safe_enable(safe_enable)
    );

    always @(posedge ahb_clk or posedge ahb_reset) begin
        if (ahb_reset) begin
            data_valid <= 1'b0;
            data_write <= 1'b0;
            data_addr <= 5'd0;
            address <= 20'd0;
            write_data <= 32'd0;
            strobes <= 4'hF;
            request_write <= 1'b0;
            request_toggle <= 1'b0;
            ack_sync <= 2'b00;
            busy <= 1'b0;
            done <= 1'b0;
            last_error <= 1'b0;
            read_data <= 32'd0;
        end else begin
            ack_sync <= {ack_sync[0], ack_toggle};
            data_valid <= htrans[1] && haddr[30:5] == 26'h000008
                          && haddr[1:0] == 2'b00 && hsize == 3'b010;
            data_write <= hwrite;
            data_addr <= haddr[4:0];

            if (busy && ack_sync[1] == request_toggle) begin
                read_data <= response_data;
                last_error <= response_error;
                busy <= 1'b0;
                done <= 1'b1;
            end

            if (data_valid && data_write && !busy) begin
                case (data_addr)
                    5'h00: address <= hwdata[19:0];
                    5'h04: write_data <= hwdata;
                    5'h08: if (hwdata == 32'd1 || hwdata == 32'd3) begin
                        request_write <= hwdata[1];
                        request_toggle <= !request_toggle;
                        busy <= 1'b1;
                        done <= 1'b0;
                        last_error <= 1'b0;
                    end
                    5'h14: strobes <= hwdata[3:0];
                    default: begin end
                endcase
            end
        end
    end

    always @(*) begin
        hrdata = 32'd0;
        if (data_valid && !data_write) begin
            case (data_addr)
                5'h00: hrdata = {12'd0, address};
                5'h04: hrdata = write_data;
                5'h0C: hrdata = read_data;
                5'h10: hrdata = {29'd0, last_error, done, busy};
                5'h14: hrdata = {28'd0, strobes};
                default: hrdata = 32'd0;
            endcase
        end
    end

    always @(posedge apb_clk or posedge apb_reset) begin
        if (apb_reset) begin
            request_sync <= 2'b00;
            ack_toggle <= 1'b0;
            response_data <= 32'd0;
            response_error <= 1'b0;
            state <= IDLE;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            case (state)
                IDLE: if (request_sync[1] != ack_toggle) state <= SETUP;
                SETUP: state <= ACCESS;
                ACCESS: if (pready) begin
                    response_data <= pslverr ? 32'd0 : prdata;
                    response_error <= pslverr;
                    ack_toggle <= request_sync[1];
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
