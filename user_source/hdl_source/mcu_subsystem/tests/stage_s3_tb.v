`timescale 1ns / 1ps

module stage_s3_tb;
    reg ahb_clk = 0;
    reg apb_clk = 0;
    always #3.333 ahb_clk = !ahb_clk;
    always #10 apb_clk = !apb_clk;

    reg reset = 1;
    reg [1:0] htrans = 0;
    reg hwrite = 0;
    reg [30:0] haddr = 0;
    reg [2:0] hsize = 3'b010;
    reg [31:0] hwdata = 0;
    wire [31:0] hrdata;
    wire irq;
    wire safe_enable;
    reg [31:0] value;
    reg [31:0] expected;
    integer i;
    integer elapsed;
    integer transactions = 0;

    fpga_apb_bridge #(
        .HEARTBEAT_TIMEOUT_CYCLES(100),
        .UPTIME_DIVISOR(5)
    ) dut (
        .ahb_clk(ahb_clk), .ahb_reset(reset), .htrans(htrans),
        .hwrite(hwrite), .haddr(haddr), .hsize(hsize), .hwdata(hwdata),
        .hrdata(hrdata), .apb_clk(apb_clk), .apb_reset(reset),
        .irq(irq), .safe_enable(safe_enable)
    );

    task ahb_write;
        input [30:0] addr;
        input [31:0] data;
        begin
            @(negedge ahb_clk);
            haddr = addr; htrans = 2'b10; hwrite = 1;
            hwdata = 32'hDEADBEEF;
            @(negedge ahb_clk);
            htrans = 0; hwrite = 0; hwdata = data;
            @(negedge ahb_clk);
            hwdata = 0;
        end
    endtask

    task ahb_read;
        input [30:0] addr;
        output [31:0] data;
        begin
            @(negedge ahb_clk);
            haddr = addr; htrans = 2'b10; hwrite = 0;
            @(negedge ahb_clk);
            data = hrdata; htrans = 0;
            @(negedge ahb_clk);
        end
    endtask

    task transfer;
        input [19:0] addr;
        input wr;
        input [3:0] strobes;
        input [31:0] data;
        input error_expected;
        output [31:0] response;
        reg [31:0] status;
        integer poll;
        begin
            ahb_write('h100, addr);
            ahb_write('h104, data);
            ahb_write('h114, strobes);
            ahb_write('h108, wr ? 3 : 1);
            status = 0;
            poll = 0;
            while (status[1:0] != 2'b10 && poll < 100) begin
                ahb_read('h110, status);
                poll = poll + 1;
            end
            if (poll == 100 || status[2] !== error_expected)
                $fatal(1, "APB completion/error failure addr=%h status=%h", addr, status);
            ahb_read('h10C, response);
            transactions = transactions + 1;
        end
    endtask

    initial begin
        #100; reset = 0;
        if (safe_enable !== 0) $fatal(1, "Safety output active after reset");

        transfer('h000, 0, 0, 0, 0, value);
        if (value !== 32'h56504C43) $fatal(1, "ID mismatch");
        transfer('h004, 0, 0, 0, 0, value);
        if (value !== 32'h00020000) $fatal(1, "VERSION mismatch");

        expected = 0;
        for (i = 0; i < 4; i = i + 1) begin
            expected = expected | (32'hA5 << (i * 8));
            transfer('h030, 1, 1 << i, 32'hA5A5A5A5, 0, value);
            transfer('h030, 0, 0, 0, 0, value);
            if (value !== expected) $fatal(1, "Byte strobe mismatch");
        end
        transfer('h000, 1, 15, 0, 1, value);
        transfer('h034, 0, 0, 0, 1, value);

        transfer('h02C, 1, 1, 32'h10, 0, value);
        if (irq !== 0) $fatal(1, "Masked IRQ asserted");
        transfer('h010, 0, 0, 0, 0, value);
        if (value !== 32'h10) $fatal(1, "Masked IRQ event lost");
        transfer('h014, 1, 1, 32'h1F, 0, value);
        if (irq !== 1) $fatal(1, "Enabled IRQ did not assert");
        transfer('h010, 1, 1, 32'h10, 0, value);
        if (irq !== 0) $fatal(1, "W1C failed");

        transfer('h020, 1, 15, 32'h1, 0, value);
        transfer('h024, 1, 1, 32'h1, 0, value);
        if (safe_enable !== 1) $fatal(1, "ARM did not enable safety output");

        repeat (40) @(posedge apb_clk);
        transfer('h020, 1, 15, 32'h2, 0, value);
        repeat (40) @(posedge apb_clk);
        transfer('h020, 1, 15, 32'h3, 0, value);
        if (safe_enable !== 1) $fatal(1, "Changing heartbeat did not keep ARM alive");

        elapsed = 0;
        while (safe_enable && elapsed < 120) begin
            @(posedge apb_clk);
            elapsed = elapsed + 1;
        end
        if (elapsed < 99 || elapsed > 101)
            $fatal(1, "Heartbeat timeout cycles=%0d expected 100", elapsed);
        if (safe_enable !== 0 || irq !== 1)
            $fatal(1, "Timeout did not force safe state and IRQ");
        transfer('h01C, 0, 0, 0, 0, value);
        if (value !== 1) $fatal(1, "Timeout fault not latched");

        transfer('h024, 1, 1, 32'h1, 0, value);
        if (safe_enable !== 0) $fatal(1, "ARM bypassed latched fault");
        transfer('h024, 1, 1, 32'h2, 0, value);
        transfer('h020, 1, 15, 32'h4, 0, value);
        transfer('h024, 1, 1, 32'h1, 0, value);
        if (safe_enable !== 1) $fatal(1, "Clear-heartbeat-ARM recovery failed");

        repeat (60) @(posedge apb_clk);
        transfer('h020, 1, 15, 32'h4, 0, value);
        repeat (45) @(posedge apb_clk);
        if (safe_enable !== 0)
            $fatal(1, "Unchanged heartbeat incorrectly refreshed watchdog");

        reset = 1;
        #100; reset = 0;
        if (safe_enable !== 0 || irq !== 0)
            $fatal(1, "Reset did not force safe state");
        transfer('h028, 0, 0, 0, 0, value);
        if (value === 0) $fatal(1, "PL uptime did not advance");

        $display("STAGE_S3_SIM PASS: IRQ/W1C, 100-cycle watchdog, explicit recovery, unchanged-heartbeat fault, reset-safe; transactions=%0d", transactions);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
