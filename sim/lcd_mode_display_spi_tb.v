`timescale 1ns / 1ns

// The initialization block is intentionally stubbed here.  This test is for
// the post-initialization writer and does not wait through the hardware fill.
module lcd_hw_test #(
    parameter CLK_HZ=1000, parameter SPI_DIV=1, parameter FILL_COLOR=16'h0000
) (
    input wire I_clk, input wire I_rst_n,
    output wire O_scl, output wire O_sda, output wire O_rst,
    output wire O_dc, output wire O_cs, output wire O_init_done, output wire O_done
);
    assign O_scl=1'b0;
    assign O_sda=1'b0;
    assign O_rst=I_rst_n;
    assign O_dc=1'b1;
    assign O_cs=1'b1;
    assign O_init_done=I_rst_n;
    assign O_done=I_rst_n;
endmodule

module lcd_mode_display_spi_tb;
    reg clk=0;
    reg rst_n=0;
    reg [2:0] mode=3'd0;
    reg [15:0] latency=16'd0;
    reg latency_valid=1'b1;
    wire scl,sda,lcd_rst,dc,cs,initialized,ready;
    wire [2:0] displayed_mode;
    reg [7:0] bytes [0:65535];
    reg [7:0] shift;
    integer bit_count;
    integer byte_count;
    integer i,j,latency_window;

    always #5 clk=~clk;

    lcd_mode_display #(.CLK_HZ(1000),.SPI_DIV(1)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_mode(mode),
        .I_latency_ms(latency), .I_latency_valid(latency_valid),
        .O_scl(scl), .O_sda(sda), .O_rst(lcd_rst), .O_dc(dc), .O_cs(cs),
        .O_initialized(initialized), .O_ready(ready), .O_displayed_mode(displayed_mode)
    );

    // The DUT changes SDA before the rising SPI edge, so this is a protocol
    // decoder rather than a hierarchy-dependent internal-state check.
    always @(posedge scl or negedge rst_n) begin
        if(!rst_n) begin
            shift<=0; bit_count<=0; byte_count<=0;
        end else if(!cs) begin
            shift<={shift[6:0],sda};
            if(bit_count==7) begin
                bytes[byte_count]<= {shift[6:0],sda};
                byte_count<=byte_count+1;
                bit_count<=0;
            end else bit_count<=bit_count+1;
        end else begin
            bit_count<=0;
        end
    end

    initial begin
        #20 rst_n=1;
        wait(byte_count>=13);
        if(bytes[0]!==8'h2a || bytes[1]!==8'h00 || bytes[2]!==8'h1e ||
           bytes[3]!==8'h00 || bytes[4]!==8'hd1)
            $fatal(1,"title CASET rectangle is incorrect");
        if(bytes[5]!==8'h2b || bytes[6]!==8'h00 || bytes[7]!==8'h28 ||
           bytes[8]!==8'h00 || bytes[9]!==8'h3c)
            $fatal(1,"title PASET rectangle is incorrect");
        if(bytes[10]!==8'h2c)
            $fatal(1,"RAMWR was not emitted at window byte 10: %02x",bytes[10]);
        if(bytes[11]!==8'h07 || bytes[12]!==8'hff)
            $fatal(1,"first RGB565 pixel was not high-byte then low-byte: %02x %02x",bytes[11],bytes[12]);
        wait(ready);
        if(displayed_mode!==3'd0)
            $fatal(1,"mode region did not complete");
        // Zero is valid input.  After the mode region, the latency region
        // must still be emitted and its first glyph pixel is green.
        #10000000;
        latency_window=0;
        for(j=13;j<byte_count-10;j=j+1)
            if(bytes[j]===8'h2a && bytes[j+1]===8'h00 && bytes[j+2]===8'h24 &&
               bytes[j+3]===8'h00 && bytes[j+4]===8'hcb && bytes[j+5]===8'h2b &&
               bytes[j+6]===8'h00 && bytes[j+7]===8'hd2 && bytes[j+8]===8'h00 &&
               bytes[j+9]===8'hdf && bytes[j+10]===8'h2c) latency_window=j;
        if(latency_window==0)
            $fatal(1,"zero-latency window was not emitted");
        if(bytes[latency_window+11]!==8'h07 || bytes[latency_window+12]!==8'he0)
            $fatal(1,"zero-latency first pixel ordering/color is incorrect");
        $display("lcd_mode_display_spi_tb PASS: rectangles, RAMWR, RGB565 order, zero latency");
        #20 $finish;
    end
endmodule
