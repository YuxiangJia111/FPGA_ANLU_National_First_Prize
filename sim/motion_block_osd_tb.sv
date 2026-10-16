`timescale 1ns/1ps
module motion_block_osd_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,de=1;
    reg [11:0] x=0,y=0;
    reg [24:0] blocks=25'h1001001;
    wire hit;
    bit previous_expected=0,current_expected;
    integer xx,yy,c,r,x0,x1,y0,y1,checked=0;
    motion_block_osd #(.ROI_X_MIN(3),.ROI_X_MAX(57),.ROI_Y_MIN(3),.ROI_Y_MAX(54),
        .SAMPLE_STEP(3),.BLOCK_SHIFT(2),.BLOCK_COLS(5),.BLOCK_ROWS(5)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_de(de),.I_x(x),.I_y(y),.I_blocks(blocks),.O_hit(hit));
    always @(posedge clk) begin
        if(!rst_n) previous_expected=0;
        else begin
            current_expected=0;
            if(enable && de && x>=3 && x<=57 && y>=3 && y<=54) begin
                c=(x-3)/12;r=(y-3)/12;x0=3+c*12;y0=3+r*12;
                x1=(x0+11>57)?57:x0+11;y1=(y0+11>54)?54:y0+11;
                current_expected=blocks[r*5+c] && (x<x0+2 || x>x1-2 || y<y0+2 || y>y1-2);
            end
            #1;
            if(hit!==previous_expected)$fatal(1,"FAIL: motion OSD position/latency at %d,%d",x,y);
            previous_expected=current_expected;checked=checked+1;
        end
    end
    initial begin
        repeat(3)@(negedge clk);rst_n=1;enable=1;
        for(yy=0;yy<60;yy=yy+1)for(xx=0;xx<64;xx=xx+1)begin
            x=xx;y=yy;@(negedge clk);
        end
        enable=0;repeat(3)@(negedge clk);
        enable=1;de=0;x=3;y=3;repeat(3)@(negedge clk);
        if(checked<3840)$fatal(1,"FAIL: coverage");
        $display("PASS: motion OSD every pixel, partial edges, blanking and two-stage alignment");$finish;
    end
endmodule
