`timescale 1ns / 1ps

module lcd_status_bridge_tb;
    reg sys_clk=0, hdmi_clk=0, rst_n=0;
    reg [31:0] latency_us=0;
    reg latency_valid=0;
    wire [15:0] latency_ms;
    wire latency_ms_valid;

    always #5 sys_clk = ~sys_clk;
    always #7 hdmi_clk = ~hdmi_clk;

    lcd_status_bridge dut (
        .I_sys_clk(sys_clk), .I_hdmi_clk(hdmi_clk), .I_rst_n(rst_n),
        .I_latency_us(latency_us), .I_latency_valid(latency_valid),
        .O_latency_ms(latency_ms), .O_latency_valid(latency_ms_valid)
    );

    task publish;
        input [31:0] value;
        input value_valid;
        begin
            latency_us=value;
            latency_valid=value_valid;
            @(posedge hdmi_clk);
        end
    endtask

    task wait_for_ms;
        input [15:0] expected;
        integer i;
        begin
            i=0;
            while ((latency_ms !== expected) && (i<300)) begin
                @(posedge sys_clk);
                i=i+1;
            end
            if (latency_ms !== expected)
                $fatal(1, "expected %0d ms, got %0d", expected, latency_ms);
        end
    endtask

    initial begin
        #31 rst_n=1;
        publish(32'd0, 1'b1);
        wait (latency_ms_valid === 1'b1);
        wait_for_ms(16'd0);
        if (!latency_ms_valid) $fatal(1, "zero payload was not marked valid");

        publish(32'd0, 1'b0);
        wait (latency_ms_valid === 1'b0);

        latency_valid=1;
        latency_us=32'd1000;
        @(posedge hdmi_clk);
        latency_us=32'd2000;
        wait_for_ms(16'd1);
        if (!latency_ms_valid) $fatal(1, "valid output dropped during newer conversion");
        wait_for_ms(16'd2);
        $display("lcd_status_bridge_tb PASS: zero, invalid, and rapid updates");
        #20 $finish;
    end
endmodule
