`timescale 1ns/1ps
module digit_track_ui_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,de=1;
    reg [11:0] x=0,y=0;
    reg [7:0] valid=8'h81;
    reg [3:0] count=2;
    reg motion_ready=0,motion_global=0;
    reg [127:0] bx=0,by=0;
    wire hit;wire [23:0] color;
    reg [7:0] expected_char;
    wire [15:0] expected_glyph;
    reg [3:0] switches=0,forced_keys=0;
    wire [2:0] mode;
    integer c,r;
    digit_track_osd osd(.I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_de(de),
        .I_x(x),.I_y(y),.I_valid(valid),.I_count(count),
        .I_center_x_bcd(bx),.I_center_y_bcd(by),
        .I_motion_ready(motion_ready),.I_motion_global(motion_global),.O_hit(hit),.O_color(color));
    osd_char_lib reference_font(.I_char(expected_char),.I_row(y[3:0]),.O_row_bits(expected_glyph));
    control_top ctrl(.I_clk(clk),.I_rst_n(rst_n),.I_key_n(4'hf),.I_switch(switches),
        .O_key_event(),.O_switch_state(),.O_image_mode(mode),
        .O_bbox_luma_threshold(),.O_bbox_connect_gap());
    task check(input bit ok,input string message);
        if(!ok) $fatal(1,"FAIL: %s",message);
    endtask
    task press(input [3:0] keys);
        begin
            @(negedge clk);forced_keys=keys;
            @(negedge clk);forced_keys=0;
        end
    endtask
    task glyph(input integer at_x,at_y,input [7:0] ch,input bit lit);
        begin
            expected_char=ch;
            for(r=0;r<16;r=r+1) for(c=0;c<16;c=c+1) begin
                @(negedge clk);x=at_x+c;y=at_y+r;
                @(posedge clk);#1;
                check(hit,"glyph lies inside panel");
                check(color===(expected_glyph[15-c] ? (lit?24'h00ffff:24'h606060):24'h102030),
                      "registered glyph and coordinate selection");
            end
        end
    endtask
    initial begin
        force ctrl.key_event=forced_keys;
        repeat(3) @(negedge clk);rst_n=1;
        check(mode==1,"default gray");
        for(c=2;c<=7;c=c+1) begin press(8);check(mode==c,"forward through TRACK");end
        press(8);check(mode==1,"forward wraps to gray");
        press(4);check(mode==7,"backward gray to TRACK");
        switches=8;repeat(3) @(negedge clk);check(mode==0,"SW4 original override");
        switches=0;repeat(3) @(negedge clk);check(mode==7,"release override restores TRACK");
        press(4);check(mode==6,"backward TRACK to preview");
        for(c=5;c>=1;c=c-1) begin press(4);check(mode==c,"backward through old modes");end
        release ctrl.key_event;
        bx[15:0]=16'h1279;by[15:0]=16'h0719;
        bx[127:112]=16'h0250;by[127:112]=16'h0203;
        enable=1;
        glyph(0,160,"T",1);glyph(128,160,"2",1);
        glyph(80,176,"W",1);motion_ready=1;glyph(80,176,"R",1);glyph(144,176,"Y",1);
        motion_global=1;glyph(80,176,"L",1);glyph(144,176,"T",1);motion_global=0;
        glyph(0,192,"I",1);glyph(48,192,"1",1);
        glyph(0,208,"X",1);glyph(32,208,"1",1);glyph(48,208,"2",1);
        glyph(64,208,"7",1);glyph(80,208,"9",1);
        glyph(32,224,"0",1);glyph(48,224,"7",1);glyph(64,224,"1",1);glyph(80,224,"9",1);
        glyph(48,640,"8",1);glyph(32,656,"0",1);glyph(48,656,"2",1);
        glyph(48,256,"2",0);glyph(32,272," ",0);
        @(negedge clk);x=192;y=208;@(posedge clk);#1;check(!hit,"panel outside ROI");
        @(negedge clk);x=0;y=704;@(posedge clk);#1;check(!hit,"last row ends at 703");
        @(negedge clk);enable=0;x=0;y=160;@(posedge clk);#1;check(!hit,"panel disabled in old modes");
        @(negedge clk);enable=1;de=0;@(posedge clk);#1;check(!hit,"blanking suppresses panel");
        $display("PASS: digit_track_ui mode and coordinate regression");$finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
