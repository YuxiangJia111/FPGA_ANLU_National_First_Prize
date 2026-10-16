`timescale 1ns/1ps

// Serial tracker: one 16x256 ERAM holds track/detection/result/motion records.
// One-record working state and video I/O remain in registers. Outputs load in
// blanking, then their valid mask/count commit at the next active frame start.
module digit_motion_tracker #(
    parameter integer MATCH_DISTANCE=96,
    parameter integer SIZE_TOLERANCE=64,
    parameter integer MAX_MISSED=5,
    parameter integer USE_ERAM_IP=1,
    parameter integer HISTORY_INTERVAL=4,
    parameter integer START_DISTANCE=8,
    parameter integer STOP_DISTANCE=3,
    parameter integer STOP_CONFIRM=2,
    parameter integer REQUIRE_FRAME_DIFF=0,
    parameter integer ACTIVITY_HOLD=4
) (
    input wire I_clk, I_rst_n, I_enable,
    input wire I_frame_start, I_vblank, I_bbox_update,
    input wire [7:0] I_bbox_valid,
    input wire [95:0] I_x_min, I_x_max, I_y_min, I_y_max,
    input wire [269:0] I_motion_blocks,
    input wire I_motion_ready, I_motion_global,
    output reg [7:0] O_valid,
    output reg [95:0] O_x_min, O_x_max, O_y_min, O_y_max,
    output reg [95:0] O_center_x, O_center_y,
    output reg [127:0] O_center_x_bcd, O_center_y_bcd,
    output wire [7:0] O_arrow_valid,
    output reg [23:0] O_arrow_direction,
    output reg [3:0] O_count,
    output reg O_update
);
    localparam [5:0] IDLE=0, CAPTURE=1, RAM_REQ=2, RAM_GET=3,
        SCAN_RESET=4, SCAN_TRACK=5, SCAN_DET=6, METRIC=7, SCAN_NEXT=8,
        PICK=9, WRITE_TRACK=10, AGE=11, ALLOC=12, ALLOC_NEXT=13,
        BUILD_START=14, BUILD_CHECK=15, BCD_INIT=16, BCD_SHIFT=17,
        WRITE_RESULT=18, WAIT_BLANK=19, WAIT_FRAME=20,
        MOTION_BEGIN=21, MOTION_FILTER_X=22, MOTION_FILTER_Y=23,
        MOTION_DX=24, MOTION_DY=25, MOTION_DECIDE=26, MOTION_SAVE=27,
        EVIDENCE_SCAN=28, MOTION_HISTORY=29, FUSION_COMMIT=30;
    localparam [1:0] LOAD_RECORD=0, LOAD_TRACK_METRIC=1, LOAD_DISPLAY=2, LOAD_MOTION=3;
    reg [5:0] state, read_return;
    reg [1:0] load_mode, read_region;
    reg [2:0] read_slot, read_field, read_last;
    reg [2:0] ti, di, index, field, best_t, best_d, write_slot, write_det;
    reg write_new;
    reg [7:0] active, seen, used_det, used_track, det_valid, pending_valid;
    reg [3:0] missed[0:7];
    // Exact one-edge input snapshot. Shift out one slot after its 8 writes;
    // no dynamic slot mux and no eight-way parallel center/size arithmetic.
    reg [95:0] snapshot_x0, snapshot_x1, snapshot_y0, snapshot_y1;
    reg [11:0] rx0, rx1, ry0, ry1, rcx, rcy, rw, rh;
    reg [11:0] tcx, tcy, tw, th;
    reg [1:0] metric;
    reg [11:0] delta_x;
    reg [12:0] pair_distance, best_distance;
    reg width_ok, best_found;
    reg [3:0] pending_count, bit_count;
    reg pending_ready, preloaded;
    reg [11:0] shift_x, shift_y;
    reg [15:0] bcd_x, bcd_y;
    reg [7:0] motion_reset, display_moving;
    reg [11:0] smooth_x, smooth_y, anchor_x, anchor_y, motion_dy;
    reg [3:0] motion_age, motion_quiet;
    reg motion_moving, motion_left, motion_up;
    reg [2:0] motion_direction;
    reg [269:0] evidence_blocks;
    reg evidence_ready, evidence_global, evidence_hit;
    reg [8:0] evidence_index;
    reg [4:0] evidence_col;
    reg [11:0] evidence_x, evidence_y;
    reg [3:0] activity_age;
    wire confirmed_moving=motion_moving && (!REQUIRE_FRAME_DIFF ||
        (evidence_ready && !evidence_global && activity_age!=0));
    wire [2:0] next_direction = ({1'b0,delta_x} >= ({1'b0,motion_dy}<<1)) ?
        (motion_left?3'd4:3'd0) :
        (({1'b0,motion_dy} >= ({1'b0,delta_x}<<1)) ?
         (motion_up?3'd6:3'd2) :
         (motion_up?(motion_left?3'd5:3'd7):(motion_left?3'd3:3'd1)));
    assign O_arrow_valid=O_valid & display_moving;
    integer i;

    wire filter_stage=(state==MOTION_FILTER_X || state==MOTION_FILTER_Y);
    wire [11:0] input_min=filter_stage ? ((state==MOTION_FILTER_Y)?smooth_y:smooth_x) :
        (field[0]?snapshot_y0[11:0]:snapshot_x0[11:0]);
    wire [11:0] input_max=filter_stage ? ((state==MOTION_FILTER_Y)?rcy:rcx) :
        (field[0]?snapshot_y1[11:0]:snapshot_x1[11:0]);
    wire [12:0] input_sum={1'b0,input_min}+{1'b0,input_max}+{12'd0,filter_stage};
    wire [11:0] input_span=input_max-input_min;
    reg [11:0] metric_a, metric_b;
    always @(*) begin
        if(state==MOTION_DX)begin metric_a=smooth_x;metric_b=anchor_x;end
        else if(state==MOTION_DY)begin metric_a=smooth_y;metric_b=anchor_y;end
        else case(metric)
            0:begin metric_a=tcx;metric_b=rcx;end
            1:begin metric_a=tcy;metric_b=rcy;end
            2:begin metric_a=tw;metric_b=rw;end
            default:begin metric_a=th;metric_b=rh;end
        endcase
    end
    // A single shared absolute difference datapath for X/Y/width/height.
    wire [12:0] signed_delta={1'b0,metric_a}-{1'b0,metric_b};
    wire [11:0] magnitude=signed_delta[12]?(~signed_delta[11:0]+12'd1):signed_delta[11:0];

    function [15:0] bcd_step;
        input [15:0] b;
        input next_bit;
        reg [15:0] adjusted;
        integer n;
        begin
            adjusted=b;
            for(n=0;n<4;n=n+1)
                if(b[n*4 +: 4]>=5) adjusted[n*4 +: 4]=b[n*4 +: 4]+4'd3;
            bcd_step={adjusted[14:0],next_bit};
        end
    endfunction
    reg [15:0] ram_write_data;
    reg [7:0] ram_write_addr;
    reg ram_write_en;
    wire [15:0] ram_read_data;
    wire [7:0] ram_read_addr={read_region,read_slot,read_field};
    // Regions: 00 tracks; 01 detections; 10 next display; 11 motion history.
    // Each record has eight 16-bit words. See the IP integration document.
    always @(*) begin
        ram_write_en=0;ram_write_addr=0;ram_write_data=0;
        if(I_rst_n && I_enable) begin
            case(state)
                CAPTURE:begin
                    ram_write_en=1;ram_write_addr={2'b01,index,field};
                    case(field)
                        0:ram_write_data={4'd0,snapshot_x0[11:0]};
                        1:ram_write_data={4'd0,snapshot_x1[11:0]};
                        2:ram_write_data={4'd0,snapshot_y0[11:0]};
                        3:ram_write_data={4'd0,snapshot_y1[11:0]};
                        4,5:ram_write_data={4'd0,input_sum[12:1]};
                        default:ram_write_data={4'd0,input_span};
                    endcase
                end
                WRITE_TRACK,WRITE_RESULT:begin
                    ram_write_en=1;
                    ram_write_addr=(state==WRITE_TRACK)?{2'b00,write_slot,field}:{2'b10,index,field};
                    case(field)
                        0:ram_write_data={4'd0,rx0};1:ram_write_data={4'd0,rx1};
                        2:ram_write_data={4'd0,ry0};3:ram_write_data={4'd0,ry1};
                        4:ram_write_data=(state==WRITE_TRACK)?{4'd0,rcx}:{confirmed_moving,motion_direction,rcx};
                        5:ram_write_data={4'd0,rcy};
                        6:ram_write_data=(state==WRITE_TRACK)?{4'd0,rw}:bcd_x;
                        7:ram_write_data=(state==WRITE_TRACK)?{4'd0,rh}:bcd_y;
                    endcase
                end
                MOTION_SAVE:begin
                    ram_write_en=1;ram_write_addr={2'b11,index,field};
                    case(field)
                        0:ram_write_data={4'd0,smooth_x};1:ram_write_data={4'd0,smooth_y};
                        2:ram_write_data={4'd0,anchor_x};3:ram_write_data={4'd0,anchor_y};
                        4:ram_write_data={4'd0,motion_quiet,motion_age,motion_moving,motion_direction};
                        5:ram_write_data={12'd0,activity_age};
                        default:ram_write_data=0;
                    endcase
                end
                default:begin end
            endcase
        end
    end
    // The user's generated module is named digit_tracker_state_ram_adapter.
    // Instantiate its native ports directly; no custom same-name adapter.
    generate
        if(USE_ERAM_IP) begin : g_state_eram
            digit_tracker_state_ram_adapter u_state_ram (
                .dia(ram_write_data), .addra(ram_write_addr), .wea(ram_write_en),
                .clka(I_clk), .dob(ram_read_data), .addrb(ram_read_addr)
            );
        end else begin : g_state_model
            reg [15:0] memory[0:255];
            reg [15:0] read_q;
            always @(posedge I_clk) begin
                if(ram_write_en) memory[ram_write_addr]<=ram_write_data;
                read_q<=memory[ram_read_addr];
            end
            assign ram_read_data=read_q;
        end
    endgenerate

    // Constant slices and decoded enables avoid a wide variable-write mux.
    // Outputs can change only inside the supplied vertical blanking window.
    genvar slot;
    generate for(slot=0;slot<8;slot=slot+1) begin : g_display
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                O_x_min[slot*12 +: 12]<=0;O_x_max[slot*12 +: 12]<=0;
                O_y_min[slot*12 +: 12]<=0;O_y_max[slot*12 +: 12]<=0;
                O_center_x[slot*12 +: 12]<=0;O_center_y[slot*12 +: 12]<=0;
                O_center_x_bcd[slot*16 +: 16]<=0;O_center_y_bcd[slot*16 +: 16]<=0;
                display_moving[slot]<=0;O_arrow_direction[slot*3 +: 3]<=0;
            end else if(I_enable && I_vblank && state==RAM_GET &&
                        load_mode==LOAD_DISPLAY && read_slot==slot) begin
                case(read_field)
                    0:O_x_min[slot*12 +: 12]<=ram_read_data[11:0];
                    1:O_x_max[slot*12 +: 12]<=ram_read_data[11:0];
                    2:O_y_min[slot*12 +: 12]<=ram_read_data[11:0];
                    3:O_y_max[slot*12 +: 12]<=ram_read_data[11:0];
                    4:begin
                        O_center_x[slot*12 +: 12]<=ram_read_data[11:0];
                        display_moving[slot]<=ram_read_data[15];
                        O_arrow_direction[slot*3 +: 3]<=ram_read_data[14:12];
                    end
                    5:O_center_y[slot*12 +: 12]<=ram_read_data[11:0];
                    6:O_center_x_bcd[slot*16 +: 16]<=ram_read_data;
                    7:O_center_y_bcd[slot*16 +: 16]<=ram_read_data;
                endcase
            end
        end
    end endgenerate

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;read_return<=IDLE;load_mode<=LOAD_RECORD;read_region<=0;
            read_slot<=0;read_field<=0;read_last<=0;
            ti<=0;di<=0;index<=0;field<=0;best_t<=0;best_d<=0;write_slot<=0;write_det<=0;write_new<=0;
            active<=0;seen<=0;used_det<=0;used_track<=0;det_valid<=0;pending_valid<=0;
            snapshot_x0<=0;snapshot_x1<=0;snapshot_y0<=0;snapshot_y1<=0;
            rx0<=0;rx1<=0;ry0<=0;ry1<=0;rcx<=0;rcy<=0;rw<=0;rh<=0;
            tcx<=0;tcy<=0;tw<=0;th<=0;metric<=0;delta_x<=0;pair_distance<=0;
            best_distance<=13'h1fff;width_ok<=0;best_found<=0;
            pending_count<=0;bit_count<=0;pending_ready<=0;preloaded<=0;
            shift_x<=0;shift_y<=0;bcd_x<=0;bcd_y<=0;
            evidence_blocks<=0;evidence_ready<=0;evidence_global<=0;evidence_hit<=0;
            evidence_index<=0;evidence_col<=0;evidence_x<=0;evidence_y<=0;activity_age<=0;
            motion_reset<=0;smooth_x<=0;smooth_y<=0;anchor_x<=0;anchor_y<=0;motion_dy<=0;
            motion_age<=0;motion_quiet<=0;motion_moving<=0;motion_left<=0;motion_up<=0;motion_direction<=0;
            O_valid<=0;O_count<=0;O_update<=0;
            for(i=0;i<8;i=i+1) missed[i]<=0;
        end else begin
            O_update<=0;
            if(!I_enable) begin
                state<=IDLE;active<=0;seen<=0;pending_ready<=0;preloaded<=0;
                motion_reset<=0;
                O_valid<=0;O_count<=0;
            end else if((state==RAM_REQ || state==RAM_GET) &&
                        load_mode==LOAD_DISPLAY && !I_vblank) begin
                // Short/invalid blanking: hide partial data and retry next blank.
                // The production VSYNC high window is 5*1650 clocks (>128 needed).
                preloaded<=0;O_valid<=0;O_count<=0;state<=WAIT_BLANK;
            end else case(state)
                IDLE:if(I_bbox_update) begin
                    snapshot_x0<=I_x_min;snapshot_x1<=I_x_max;
                    snapshot_y0<=I_y_min;snapshot_y1<=I_y_max;
                    evidence_blocks<=I_motion_blocks;evidence_ready<=I_motion_ready;evidence_global<=I_motion_global;
                    det_valid<=I_bbox_valid;used_det<=0;used_track<=0;seen<=0;
                    motion_reset<=0;
                    index<=0;field<=0;state<=CAPTURE;
                end
                CAPTURE:begin
                    if(field==7) begin
                        field<=0;
                        snapshot_x0<=snapshot_x0>>12;snapshot_x1<=snapshot_x1>>12;
                        snapshot_y0<=snapshot_y0>>12;snapshot_y1<=snapshot_y1>>12;
                        if(index==7) state<=SCAN_RESET;else index<=index+1'b1;
                    end else field<=field+1'b1;
                end
                RAM_REQ:state<=RAM_GET;
                RAM_GET:begin
                    if(load_mode==LOAD_TRACK_METRIC) begin
                        case(read_field)
                            4:tcx<=ram_read_data[11:0];5:tcy<=ram_read_data[11:0];
                            6:tw<=ram_read_data[11:0];7:th<=ram_read_data[11:0];
                        endcase
                    end else if(load_mode==LOAD_MOTION) begin
                        case(read_field)
                            0:smooth_x<=ram_read_data[11:0];1:smooth_y<=ram_read_data[11:0];
                            2:anchor_x<=ram_read_data[11:0];3:anchor_y<=ram_read_data[11:0];
                            4:begin
                                motion_direction<=ram_read_data[2:0];motion_moving<=ram_read_data[3];
                                motion_age<=ram_read_data[7:4];motion_quiet<=ram_read_data[11:8];
                            end
                            5:activity_age<=ram_read_data[3:0];
                        endcase
                    end else if(load_mode==LOAD_RECORD) begin
                        case(read_field)
                            0:rx0<=ram_read_data[11:0];1:rx1<=ram_read_data[11:0];
                            2:ry0<=ram_read_data[11:0];3:ry1<=ram_read_data[11:0];
                            4:rcx<=ram_read_data[11:0];5:rcy<=ram_read_data[11:0];
                            6:rw<=ram_read_data[11:0];7:rh<=ram_read_data[11:0];
                        endcase
                    end
                    if(read_field==read_last) begin
                        if(load_mode==LOAD_DISPLAY && read_slot!=7) begin
                            read_slot<=read_slot+1'b1;read_field<=0;state<=RAM_REQ;
                        end else begin
                            if(load_mode==LOAD_DISPLAY) preloaded<=1;
                            state<=read_return;
                        end
                    end else begin read_field<=read_field+1'b1;state<=RAM_REQ;end
                end
                SCAN_RESET:begin
                    ti<=0;di<=0;best_found<=0;best_distance<=13'h1fff;state<=SCAN_TRACK;
                end
                SCAN_TRACK:begin
                    if(active[ti] && !used_track[ti]) begin
                        read_region<=0;read_slot<=ti;read_field<=4;read_last<=7;
                        load_mode<=LOAD_TRACK_METRIC;read_return<=SCAN_DET;state<=RAM_REQ;
                    end else if(ti==7)state<=PICK;
                    else begin ti<=ti+1'b1;di<=0;end
                end
                SCAN_DET:begin
                    if(det_valid[di] && !used_det[di]) begin
                        read_region<=1;read_slot<=di;read_field<=4;read_last<=7;
                        load_mode<=LOAD_RECORD;read_return<=METRIC;metric<=0;state<=RAM_REQ;
                    end else state<=SCAN_NEXT;
                end
                METRIC:begin
                    case(metric)
                        0:delta_x<=magnitude;
                        1:pair_distance<={1'b0,delta_x}+{1'b0,magnitude};
                        2:width_ok<=(magnitude<=SIZE_TOLERANCE);
                        3:begin
                            if(width_ok && magnitude<=SIZE_TOLERANCE && pair_distance<=MATCH_DISTANCE &&
                               (!best_found || pair_distance<best_distance)) begin
                                best_found<=1;best_distance<=pair_distance;best_t<=ti;best_d<=di;
                            end
                        end
                    endcase
                    if(metric==3)state<=SCAN_NEXT;else metric<=metric+1'b1;
                end
                SCAN_NEXT:begin
                    if(di==7)begin
                        di<=0;
                        if(ti==7)state<=PICK;else begin ti<=ti+1'b1;state<=SCAN_TRACK;end
                    end else begin di<=di+1'b1;state<=SCAN_DET;end
                end
                PICK:begin
                    if(best_found)begin
                        read_region<=1;read_slot<=best_d;read_field<=0;read_last<=7;
                        load_mode<=LOAD_RECORD;read_return<=WRITE_TRACK;state<=RAM_REQ;
                        write_slot<=best_t;write_det<=best_d;write_new<=0;field<=0;
                    end else begin index<=0;state<=AGE;end
                end
                WRITE_TRACK:begin
                    if(field==7)begin
                        field<=0;active[write_slot]<=1;seen[write_slot]<=1;
                        motion_reset[write_slot]<=write_new || (missed[write_slot]!=0);
                        used_det[write_det]<=1;missed[write_slot]<=0;
                        if(write_new)state<=ALLOC_NEXT;
                        else begin used_track[write_slot]<=1;state<=SCAN_RESET;end
                    end else field<=field+1'b1;
                end
                AGE:begin
                    if(active[index] && !seen[index])begin
                        if(missed[index]>=MAX_MISSED-1)begin active[index]<=0;missed[index]<=0;end
                        else missed[index]<=missed[index]+1'b1;
                    end
                    if(index==7)begin di<=0;ti<=0;state<=ALLOC;end
                    else index<=index+1'b1;
                end
                ALLOC:begin
                    if(!det_valid[di] || used_det[di])state<=ALLOC_NEXT;
                    else if(!active[ti])begin
                        read_region<=1;read_slot<=di;read_field<=0;read_last<=7;
                        load_mode<=LOAD_RECORD;read_return<=WRITE_TRACK;state<=RAM_REQ;
                        write_slot<=ti;write_det<=di;write_new<=1;field<=0;
                    end else if(ti==7)state<=ALLOC_NEXT;
                    else ti<=ti+1'b1;
                end
                ALLOC_NEXT:begin
                    ti<=0;
                    if(di==7)state<=BUILD_START;
                    else begin di<=di+1'b1;state<=ALLOC;end
                end
                BUILD_START:begin
                    index<=0;field<=0;pending_count<=0;pending_valid<=seen;state<=BUILD_CHECK;
                end
                BUILD_CHECK:begin
                    field<=0;
                    if(seen[index])begin
                        read_region<=0;read_slot<=index;read_field<=0;read_last<=7;
                        load_mode<=LOAD_RECORD;read_return<=MOTION_BEGIN;state<=RAM_REQ;
                    end else begin
                        rx0<=0;rx1<=0;ry0<=0;ry1<=0;rcx<=0;rcy<=0;
                        bcd_x<=0;bcd_y<=0;state<=WRITE_RESULT;
                        motion_moving<=0;motion_direction<=0;
                    end
                end
                MOTION_BEGIN:begin
                    evidence_index<=0;evidence_col<=0;evidence_x<=198;evidence_y<=18;evidence_hit<=0;
                    state<=REQUIRE_FRAME_DIFF ? EVIDENCE_SCAN : MOTION_HISTORY;
                end
                EVIDENCE_SCAN:begin
                    // One 48x48 pixel tile per cycle; last row/column are clipped
                    // by the detector ROI. Test overlap, never pixels outside ROI.
                    if(evidence_blocks[evidence_index] && evidence_ready && !evidence_global &&
                       rx1>=evidence_x && rx0<=((evidence_col==17)?12'd1022:evidence_x+12'd47) &&
                       ry1>=evidence_y && ry0<=((evidence_y==690)?12'd702:evidence_y+12'd47))
                        evidence_hit<=1;
                    if(evidence_index==269) state<=MOTION_HISTORY;
                    else begin
                        evidence_index<=evidence_index+1'b1;
                        if(evidence_col==17)begin evidence_col<=0;evidence_x<=198;evidence_y<=evidence_y+48;end
                        else begin evidence_col<=evidence_col+1'b1;evidence_x<=evidence_x+48;end
                    end
                end
                MOTION_HISTORY:begin
                    field<=0;
                    if(motion_reset[index])begin
                        smooth_x<=rcx;smooth_y<=rcy;anchor_x<=rcx;anchor_y<=rcy;
                        motion_age<=0;motion_quiet<=0;motion_moving<=0;motion_direction<=0;
                        activity_age<=0;state<=FUSION_COMMIT;
                    end else begin
                        read_region<=3;read_slot<=index;read_field<=0;read_last<=5;
                        load_mode<=LOAD_MOTION;read_return<=MOTION_FILTER_X;state<=RAM_REQ;
                    end
                end
                MOTION_FILTER_X:begin smooth_x<=input_sum[12:1];state<=MOTION_FILTER_Y;end
                MOTION_FILTER_Y:begin
                    smooth_y<=input_sum[12:1];
                    if(motion_age>=HISTORY_INTERVAL-1)begin motion_age<=0;state<=MOTION_DX;end
                    else begin motion_age<=motion_age+1'b1;state<=FUSION_COMMIT;end
                end
                MOTION_DX:begin
                    delta_x<=magnitude;motion_left<=(smooth_x<anchor_x);state<=MOTION_DY;
                end
                MOTION_DY:begin
                    motion_dy<=magnitude;motion_up<=(smooth_y<anchor_y);
                    pair_distance<={1'b0,delta_x}+{1'b0,magnitude};state<=MOTION_DECIDE;
                end
                MOTION_DECIDE:begin
                    if(!motion_moving)begin
                        motion_quiet<=0;
                        // Keep the stopped reference until the start threshold is
                        // reached, allowing slow movement to accumulate over time.
                        if(pair_distance>=START_DISTANCE)begin
                            motion_moving<=1;motion_direction<=next_direction;
                            anchor_x<=smooth_x;anchor_y<=smooth_y;
                        end
                    end else begin
                        anchor_x<=smooth_x;anchor_y<=smooth_y;
                        if(pair_distance>STOP_DISTANCE)begin
                            motion_quiet<=0;motion_direction<=next_direction;
                        end else if(motion_quiet>=STOP_CONFIRM-1)begin
                            motion_moving<=0;motion_quiet<=0;
                        end else motion_quiet<=motion_quiet+1'b1;
                    end
                    state<=FUSION_COMMIT;
                end
                FUSION_COMMIT:begin
                    if(!evidence_ready || evidence_global || motion_reset[index])activity_age<=0;
                    else if(evidence_hit)activity_age<=ACTIVITY_HOLD;
                    else if(activity_age!=0)activity_age<=activity_age-1'b1;
                    state<=MOTION_SAVE;
                end
                MOTION_SAVE:begin
                    if(field==5)begin field<=0;state<=BCD_INIT;end
                    else field<=field+1'b1;
                end
                BCD_INIT:begin
                    shift_x<=rcx;shift_y<=rcy;bcd_x<=0;bcd_y<=0;bit_count<=0;state<=BCD_SHIFT;
                end
                BCD_SHIFT:begin
                    bcd_x<=bcd_step(bcd_x,shift_x[11]);bcd_y<=bcd_step(bcd_y,shift_y[11]);
                    shift_x<=shift_x<<1;shift_y<=shift_y<<1;
                    if(bit_count==11)state<=WRITE_RESULT;else bit_count<=bit_count+1'b1;
                end
                WRITE_RESULT:begin
                    if(field==7)begin
                        field<=0;
                        if(seen[index])pending_count<=pending_count+1'b1;
                        if(index==7)begin pending_ready<=1;state<=WAIT_BLANK;end
                        else begin index<=index+1'b1;state<=BUILD_CHECK;end
                    end else field<=field+1'b1;
                end
                WAIT_BLANK:if(I_vblank)begin
                    read_region<=2;read_slot<=0;read_field<=0;read_last<=7;
                    load_mode<=LOAD_DISPLAY;read_return<=WAIT_FRAME;state<=RAM_REQ;
                end
                WAIT_FRAME:if(I_frame_start && preloaded)begin
                    O_valid<=pending_valid;O_count<=pending_count;O_update<=1;
                    pending_ready<=0;preloaded<=0;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
