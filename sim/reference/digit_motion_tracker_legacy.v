`timescale 1ns / 1ps
// Accepted pre-ERAM implementation, retained ONLY as a simulation reference.
// Never add this file to the Tang Dynasty synthesis project.

// Frame-result tracker, independent of the CNN batch rate and gray RAM ports.
// Slot n is displayed as ID n+1; IDs may be reused after retirement.
module digit_motion_tracker_legacy #(
    parameter integer MATCH_DISTANCE = 96,
    parameter integer SIZE_TOLERANCE = 64,
    parameter integer MAX_MISSED = 5
) (
    input wire I_clk, I_rst_n, I_enable,
    input wire I_frame_start, I_bbox_update,
    input wire [7:0] I_bbox_valid,
    input wire [95:0] I_x_min, I_x_max, I_y_min, I_y_max,
    output reg [7:0] O_valid,
    output reg [95:0] O_x_min, O_x_max, O_y_min, O_y_max,
    output reg [95:0] O_center_x, O_center_y,
    output reg [127:0] O_center_x_bcd, O_center_y_bcd,
    output reg [3:0] O_count,
    output reg O_update
);
    localparam IDLE=0, SCAN=1, PICK=2, AGE=3, ALLOC=4,
               CONV_LOAD=5, CONV_SHIFT=6, CONV_SAVE=7;
    reg [3:0] state;
    reg [7:0] active, seen, used_det, used_track, det_valid;
    reg [11:0] tx0[0:7], tx1[0:7], ty0[0:7], ty1[0:7];
    reg [11:0] cx[0:7], cy[0:7], tw[0:7], th[0:7];
    reg [3:0] missed[0:7];
    reg [11:0] dx0[0:7], dx1[0:7], dy0[0:7], dy1[0:7];
    reg [11:0] dcx[0:7], dcy[0:7], dw[0:7], dh[0:7];
    reg [2:0] ti, di, best_t, best_d, index;
    reg [12:0] best_distance;
    reg best_found;
    reg [7:0] pending_valid;
    reg [95:0] px0, px1, py0, py1, pcx, pcy;
    reg [127:0] pbcd_x, pbcd_y;
    reg [3:0] pending_count, bit_count;
    reg pending_ready;
    reg [11:0] shift_x, shift_y;
    reg [15:0] bcd_x, bcd_y;
    integer i;

    function [11:0] absdiff;
        input [11:0] a,b;
        begin absdiff = (a >= b) ? a-b : b-a; end
    endfunction
    function [11:0] center;
        input [11:0] a,b;
        reg [12:0] sum;
        begin sum={1'b0,a}+{1'b0,b}; center=sum[12:1]; end
    endfunction
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
    wire [12:0] distance_now = {1'b0,absdiff(cx[ti],dcx[di])} +
                                      {1'b0,absdiff(cy[ti],dcy[di])};
    wire candidate = active[ti] && !used_track[ti] && det_valid[di] &&
                     !used_det[di] && (distance_now <= MATCH_DISTANCE) &&
                     (absdiff(tw[ti],dw[di]) <= SIZE_TOLERANCE) &&
                     (absdiff(th[ti],dh[di]) <= SIZE_TOLERANCE);

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE; active<=0; seen<=0; used_det<=0; used_track<=0; det_valid<=0;
            ti<=0;di<=0;best_t<=0;best_d<=0;index<=0;best_distance<=13'h1fff;best_found<=0;
            pending_valid<=0;pending_count<=0;pending_ready<=0;
            px0<=0;px1<=0;py0<=0;py1<=0;pcx<=0;pcy<=0;pbcd_x<=0;pbcd_y<=0;
            shift_x<=0;shift_y<=0;bcd_x<=0;bcd_y<=0;bit_count<=0;
            O_valid<=0;O_x_min<=0;O_x_max<=0;O_y_min<=0;O_y_max<=0;
            O_center_x<=0;O_center_y<=0;O_center_x_bcd<=0;O_center_y_bcd<=0;
            O_count<=0;O_update<=0;
            for(i=0;i<8;i=i+1) begin
                tx0[i]<=0;tx1[i]<=0;ty0[i]<=0;ty1[i]<=0;cx[i]<=0;cy[i]<=0;
                tw[i]<=0;th[i]<=0;missed[i]<=0;
                dx0[i]<=0;dx1[i]<=0;dy0[i]<=0;dy1[i]<=0;
                dcx[i]<=0;dcy[i]<=0;dw[i]<=0;dh[i]<=0;
            end
        end else begin
            O_update<=0;
            if(!I_enable) begin
                state<=IDLE;active<=0;seen<=0;pending_ready<=0;
                O_valid<=0;O_count<=0;
            end else begin
                // Atomically publish only at the next video frame boundary.
                if(I_frame_start && pending_ready) begin
                    O_valid<=pending_valid; O_count<=pending_count;
                    O_x_min<=px0;O_x_max<=px1;O_y_min<=py0;O_y_max<=py1;
                    O_center_x<=pcx;O_center_y<=pcy;
                    O_center_x_bcd<=pbcd_x;O_center_y_bcd<=pbcd_y;
                    O_update<=1;pending_ready<=0;
                end
                case(state)
                    IDLE: if(I_bbox_update) begin
                        det_valid<=I_bbox_valid;used_det<=0;used_track<=0;seen<=0;
                        for(i=0;i<8;i=i+1) begin
                            dx0[i]<=I_x_min[i*12 +: 12];dx1[i]<=I_x_max[i*12 +: 12];
                            dy0[i]<=I_y_min[i*12 +: 12];dy1[i]<=I_y_max[i*12 +: 12];
                            dcx[i]<=center(I_x_min[i*12 +: 12],I_x_max[i*12 +: 12]);
                            dcy[i]<=center(I_y_min[i*12 +: 12],I_y_max[i*12 +: 12]);
                            dw[i]<=I_x_max[i*12 +: 12]-I_x_min[i*12 +: 12];
                            dh[i]<=I_y_max[i*12 +: 12]-I_y_min[i*12 +: 12];
                        end
                        ti<=0;di<=0;best_found<=0;best_distance<=13'h1fff;state<=SCAN;
                    end
                    // Global nearest eligible pair; repeat excluding assigned pairs.
                    // One pair per clock avoids a large parallel distance sorter.
                    SCAN: begin
                        if(candidate && (!best_found || distance_now<best_distance)) begin
                            best_found<=1;best_distance<=distance_now;best_t<=ti;best_d<=di;
                        end
                        if(di==7) begin
                            di<=0;
                            if(ti==7) state<=PICK; else ti<=ti+1'b1;
                        end else di<=di+1'b1;
                    end
                    PICK: begin
                        if(best_found) begin
                            used_track[best_t]<=1;used_det[best_d]<=1;seen[best_t]<=1;
                            tx0[best_t]<=dx0[best_d];tx1[best_t]<=dx1[best_d];
                            ty0[best_t]<=dy0[best_d];ty1[best_t]<=dy1[best_d];
                            cx[best_t]<=dcx[best_d];cy[best_t]<=dcy[best_d];
                            tw[best_t]<=dw[best_d];th[best_t]<=dh[best_d];missed[best_t]<=0;
                            ti<=0;di<=0;best_found<=0;best_distance<=13'h1fff;state<=SCAN;
                        end else begin index<=0;state<=AGE;end
                    end
                    AGE: begin
                        if(active[index] && !seen[index]) begin
                            if(missed[index]>=MAX_MISSED-1) begin active[index]<=0;missed[index]<=0;end
                            else missed[index]<=missed[index]+1'b1;
                        end
                        if(index==7) begin di<=0;ti<=0;state<=ALLOC;end
                        else index<=index+1'b1;
                    end
                    ALLOC: begin
                        if(det_valid[di] && !used_det[di] && !active[ti]) begin
                            active[ti]<=1;seen[ti]<=1;used_det[di]<=1;missed[ti]<=0;
                            tx0[ti]<=dx0[di];tx1[ti]<=dx1[di];ty0[ti]<=dy0[di];ty1[ti]<=dy1[di];
                            cx[ti]<=dcx[di];cy[ti]<=dcy[di];tw[ti]<=dw[di];th[ti]<=dh[di];
                        end
                        if(!det_valid[di] || used_det[di] || !active[ti] || ti==7) begin
                            ti<=0;
                            if(di==7) begin index<=0;pending_count<=0;state<=CONV_LOAD;end
                            else di<=di+1'b1;
                        end else ti<=ti+1'b1;
                    end
                    CONV_LOAD: begin
                        pending_valid[index]<=seen[index];
                        px0[index*12 +: 12]<=tx0[index];px1[index*12 +: 12]<=tx1[index];
                        py0[index*12 +: 12]<=ty0[index];py1[index*12 +: 12]<=ty1[index];
                        pcx[index*12 +: 12]<=cx[index];pcy[index*12 +: 12]<=cy[index];
                        if(seen[index]) pending_count<=pending_count+1'b1;
                        shift_x<=cx[index];shift_y<=cy[index];bcd_x<=0;bcd_y<=0;bit_count<=0;
                        state<=CONV_SHIFT;
                    end
                    CONV_SHIFT: begin
                        bcd_x<=bcd_step(bcd_x,shift_x[11]);bcd_y<=bcd_step(bcd_y,shift_y[11]);
                        shift_x<=shift_x<<1;shift_y<=shift_y<<1;
                        if(bit_count==11) state<=CONV_SAVE; else bit_count<=bit_count+1'b1;
                    end
                    CONV_SAVE: begin
                        pbcd_x[index*16 +: 16]<=bcd_x;pbcd_y[index*16 +: 16]<=bcd_y;
                        if(index==7) begin pending_ready<=1;state<=IDLE;end
                        else begin index<=index+1'b1;state<=CONV_LOAD;end
                    end
                    default: state<=IDLE;
                endcase
            end
        end
    end
endmodule
