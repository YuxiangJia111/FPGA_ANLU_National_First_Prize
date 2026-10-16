`timescale 1ns/1ps
module motion_gray_reuse_tb;
    parameter USE_ERAM=1;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1,de=0,user=0,last=0,crop_busy=0,read_bank=0;
    reg [7:0] luma=192;
    reg [15:0] read_addr=0;
    wire [3:0] gray,baseline_gray,cur,ref_gray;
    wire sv,rv,fe;
    wire [11:0] sx,sy;
    wire [7:0] bv,bv0;
    wire [95:0] bx0,bx1,by0,by1,bx00,bx10,by00,by10;
    wire fv,fv0;
    wire [24:0] blocks;wire ready,global_change;
    wire [24:0] completed_blocks;
    wire completed_valid,completed_ready,completed_global;
    wire [269:0] bbox_motion;
    wire bbox_ready,bbox_global;
    // Independent source-frame oracle: expectations come from the stimulus
    // table, not the DUT completed result or its metadata pipeline.
    reg [269:0] golden_blocks[0:63];
    reg [1:0] golden_flags[0:63];
    integer source_frame=-1, accepted_frame=-1, published_frame=-1, output_frame=-1;
    integer aligned_results=0;
    reg [3:0] history[0:1][0:65535];
    reg [1:0] seeded=0;
    reg expected_sample,expected_valid;
    reg [3:0] expected_current,expected_reference;
    reg [11:0] expected_x,expected_y;
    integer samples=0,valid_samples=0,crop_samples=0;
    integer xx,yy,scene;
    digit_multi_bbox #(.IMG_WIDTH(64),.IMG_HEIGHT(60),.ROI_X_MIN(3),.ROI_X_MAX(57),
        .ROI_Y_MIN(3),.ROI_Y_MAX(54),.SAMPLE_STEP(3),.USE_GRAY_ERAM_IP(USE_ERAM)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_luma(luma),.I_luma_threshold(8'd55),.I_connect_gap(3'd4),
        .I_crop_busy(crop_busy),.I_gray_read_addr(read_addr),.I_gray_read_bank(read_bank),.O_gray_read_data(gray),
        .I_completed_blocks({245'd0,completed_blocks}),.I_completed_valid(completed_valid),
        .I_completed_ready(completed_ready),.I_completed_global(completed_global),
        .O_bbox_motion_blocks(bbox_motion),.O_bbox_motion_ready(bbox_ready),.O_bbox_motion_global(bbox_global),
        .I_motion_enable(enable),.O_motion_sample_valid(sv),.O_motion_reference_valid(rv),
        .O_motion_current(cur),.O_motion_reference(ref_gray),.O_motion_sample_x(sx),.O_motion_sample_y(sy),
        .O_motion_frame_end(fe),.I_de(de),.I_user(user),.I_last(last),
        .O_bbox_valid(bv),.O_x_min(bx0),.O_x_max(bx1),.O_y_min(by0),.O_y_max(by1),.O_bbox_frame_valid(fv),
        .O_crop_frame_valid(),.O_crop_bank(),.O_crop_bbox_valid(),.O_crop_x_min(),.O_crop_x_max(),.O_crop_y_min(),.O_crop_y_max());
    // Identical detector with motion disabled checks bank/write/CNN invariance.
    digit_multi_bbox #(.IMG_WIDTH(64),.IMG_HEIGHT(60),.ROI_X_MIN(3),.ROI_X_MAX(57),
        .ROI_Y_MIN(3),.ROI_Y_MAX(54),.SAMPLE_STEP(3),.USE_GRAY_ERAM_IP(USE_ERAM)) baseline(
        .I_clk(clk),.I_rst_n(rst_n),.I_luma(luma),.I_luma_threshold(8'd55),.I_connect_gap(3'd4),
        .I_crop_busy(crop_busy),.I_gray_read_addr(read_addr),.I_gray_read_bank(read_bank),.O_gray_read_data(baseline_gray),
        .I_completed_blocks(270'd0),.I_completed_valid(1'b0),.I_completed_ready(1'b0),.I_completed_global(1'b0),
        .O_bbox_motion_blocks(),.O_bbox_motion_ready(),.O_bbox_motion_global(),
        .I_motion_enable(1'b0),.O_motion_sample_valid(),.O_motion_reference_valid(),
        .O_motion_current(),.O_motion_reference(),.O_motion_sample_x(),.O_motion_sample_y(),.O_motion_frame_end(),
        .I_de(de),.I_user(user),.I_last(last),
        .O_bbox_valid(bv0),.O_x_min(bx00),.O_x_max(bx10),.O_y_min(by00),.O_y_max(by10),.O_bbox_frame_valid(fv0),
        .O_crop_frame_valid(),.O_crop_bank(),.O_crop_bbox_valid(),.O_crop_x_min(),.O_crop_x_max(),.O_crop_y_min(),.O_crop_y_max());
    frame_diff_motion #(.SAMPLE_COLS(19),.SAMPLE_ROWS(18),.BLOCK_SHIFT(2),.MIN_CHANGED(4)) motion(
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_frame_start(user),.I_frame_end(fe),
        .I_sample_valid(sv),.I_reference_valid(rv),.I_current(cur),.I_reference(ref_gray),
        .I_sample_x(sx),.I_sample_y(sy),.O_completed_blocks(completed_blocks),.O_completed_ready(completed_ready),
        .O_completed_global(completed_global),.O_completed_valid(completed_valid),
        .O_blocks(blocks),.O_reference_ready(ready),.O_global_change(global_change));
    task check(input bit ok,input string msg);if(!ok)$fatal(1,"FAIL: %s",msg);endtask
    always @(posedge clk) if(rst_n) begin
        expected_sample=enable && dut.motion_frame_enabled && dut.capture_sample;
        expected_valid=expected_sample && seeded[dut.write_bank] &&
                       (!crop_busy || read_bank!=dut.write_bank);
        expected_current=luma[7:4];expected_reference=history[dut.write_bank][dut.capture_addr];
        expected_x=dut.sample_col;expected_y=dut.sample_row;
        if(!enable)seeded=0;
        else if(dut.capture_state==2 && de && last && dut.pixel_y==59 && dut.motion_frame_enabled)
            seeded[dut.write_bank]=1;
        if(dut.gray_write_enable)
            history[dut.gray_write_bank][dut.gray_write_addr]=dut.gray_write_data;
        if(dut.process_start)accepted_frame=source_frame;
        if(dut.process_state==6)published_frame=accepted_frame;
        if(user && dut.result_seen!=dut.result_toggle)output_frame=published_frame;
        #1;
        if(enable && fv && output_frame>=0)begin
            check(bbox_motion===golden_blocks[output_frame] && {bbox_ready,bbox_global}===golden_flags[output_frame],
                "bbox metadata matches stimulus source frame despite crop stalls/warm-up");
            aligned_results=aligned_results+1;
        end
        check(sv===expected_sample,"sample-valid alignment");
        if(sv)begin
            samples=samples+1;
            check(rv===expected_valid,"reference warm-up and port arbitration");
            check(cur===expected_current && sx==expected_x && sy==expected_y,"sample data/coordinates");
            if(rv)begin
                valid_samples=valid_samples+1;
                check(ref_gray===expected_reference,"old pixel read before existing RAM write");
            end
            if(crop_busy)crop_samples=crop_samples+1;
        end
        check({dut.gray_write_enable,dut.gray_write_bank,dut.gray_write_addr,dut.gray_write_data}===
              {baseline.gray_write_enable,baseline.gray_write_bank,baseline.gray_write_addr,baseline.gray_write_data},
              "gray writes unchanged");
        check({dut.bitmap_write_enable,dut.bitmap_write_bank,dut.bitmap_write_addr,dut.bitmap_write_data}===
              {baseline.bitmap_write_enable,baseline.bitmap_write_bank,baseline.bitmap_write_addr,baseline.bitmap_write_data},
              "bitmap writes unchanged");
        check({dut.write_bank,dut.process_bank,dut.process_state}===
              {baseline.write_bank,baseline.process_bank,baseline.process_state},"analysis scheduling unchanged");
        check({bv,bx0,bx1,by0,by1,fv}==={bv0,bx00,bx10,by00,by10,fv0},"detector results unchanged");
        if(crop_busy)check(gray===baseline_gray,"CNN read port preserved every clock while busy");
    end
    // Exercise all CNN read addresses, including during motion prefetch edges.
    always @(negedge clk) if(rst_n)read_addr<=(read_addr==341)?0:read_addr+1'b1;
    task send_frame(input integer pattern,input [24:0] expected,input bit er,eg);
        integer a,b;
        begin
            if(source_frame>=0)begin
                golden_blocks[source_frame]={245'd0,expected};golden_flags[source_frame]={er,eg};
            end
            source_frame=source_frame+1;
            @(negedge clk);user=1;de=0;last=0;
            @(negedge clk);user=0;
            check(blocks===expected && ready===er && global_change===eg,"integrated published frame result");
            for(b=0;b<60;b=b+1)begin
                for(a=0;a<64;a=a+1)begin
                    de=1;last=(a==63);luma=192;
                    if(pattern==1 && a>=3 && a<15 && b>=3 && b<15)luma=32;
                    if(pattern==2 && a>=27 && a<39 && b>=27 && b<39)luma=32;
                    if(pattern==3)luma=32;
                    @(negedge clk);
                end
                de=0;last=0;repeat(2)@(negedge clk);
            end
            repeat(1200)@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
        send_frame(0,0,0,0);send_frame(0,0,0,0);send_frame(1,0,0,0);
        send_frame(1,25'h1,1,0);send_frame(1,25'h1,1,0);send_frame(2,0,1,0);
        send_frame(2,25'h1001,1,0);
        crop_busy=1;read_bank=~dut.write_bank;
        send_frame(2,25'h1001,1,0);send_frame(1,0,1,0);send_frame(1,25'h1001,1,0);
        send_frame(3,0,1,0);send_frame(3,0,1,1);send_frame(3,0,1,0);
        // Bad ownership is rejected for motion, never by stealing the CNN port.
        read_bank=dut.write_bank;
        send_frame(3,0,1,0);read_bank=~dut.write_bank;
        send_frame(3,0,0,0);send_frame(3,0,1,0);
        enable=0;repeat(2)@(negedge clk);check(blocks==0 && !ready,"mode exit clears motion state");
        send_frame(0,0,0,0);enable=1;
        send_frame(0,0,0,0);send_frame(0,0,0,0);send_frame(0,0,1,0);
        check(aligned_results>5,"aligned bbox/difference publication coverage");
        check(samples>5000 && valid_samples>3000 && crop_samples>2000,"RAM reuse/crop coverage");
        $display("PASS: gray reuse USE_ERAM=%0d, %0d valid references, CNN reads/writes/bbox unchanged",USE_ERAM,valid_samples);
        $finish;
    end
    initial begin #5000000;$fatal(1,"timeout");end
endmodule
