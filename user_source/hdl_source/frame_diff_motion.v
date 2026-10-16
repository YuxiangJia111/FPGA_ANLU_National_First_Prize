`timescale 1ns/1ps

// Streaming 4-bit frame difference over the detector's sampled ROI.
// Only one row of saturating block counters is needed; no new frame RAM.
module frame_diff_motion #(
    parameter integer SAMPLE_COLS=275,
    parameter integer SAMPLE_ROWS=229,
    parameter integer BLOCK_SHIFT=4,
    parameter integer DIFF_THRESHOLD=3,
    parameter integer MIN_CHANGED=16,
    parameter integer BLOCK_COLS=(SAMPLE_COLS+(1<<BLOCK_SHIFT)-1)>>BLOCK_SHIFT,
    parameter integer BLOCK_ROWS=(SAMPLE_ROWS+(1<<BLOCK_SHIFT)-1)>>BLOCK_SHIFT
) (
    input wire I_clk, I_rst_n, I_enable, I_frame_start, I_frame_end,
    input wire I_sample_valid, I_reference_valid,
    input wire [3:0] I_current, I_reference,
    input wire [11:0] I_sample_x, I_sample_y,
    output reg [BLOCK_COLS*BLOCK_ROWS-1:0] O_blocks,
    output wire [BLOCK_COLS*BLOCK_ROWS-1:0] O_completed_blocks,
    output wire O_completed_ready, O_completed_global,
    output reg O_completed_valid,
    output reg O_reference_ready, O_global_change
);
    localparam integer BLOCK_SIZE=1<<BLOCK_SHIFT;
    localparam integer TOTAL=SAMPLE_COLS*SAMPLE_ROWS;
    localparam integer COUNT_W=$clog2(MIN_CHANGED+1);
    localparam integer COL_W=(BLOCK_COLS<2)?1:$clog2(BLOCK_COLS);
    localparam integer INDEX_W=(BLOCK_COLS*BLOCK_ROWS<2)?1:$clog2(BLOCK_COLS*BLOCK_ROWS);
    localparam integer TAIL_COLS=SAMPLE_COLS-(BLOCK_COLS-1)*BLOCK_SIZE;
    localparam integer TAIL_ROWS=SAMPLE_ROWS-(BLOCK_ROWS-1)*BLOCK_SIZE;
    localparam integer MIN_HITS=(MIN_CHANGED<2)?MIN_CHANGED:2;
    localparam integer RIGHT_RAW=(MIN_CHANGED*TAIL_COLS+BLOCK_SIZE-1)/BLOCK_SIZE;
    localparam integer BOTTOM_RAW=(MIN_CHANGED*TAIL_ROWS+BLOCK_SIZE-1)/BLOCK_SIZE;
    localparam integer CORNER_RAW=(MIN_CHANGED*TAIL_COLS*TAIL_ROWS+BLOCK_SIZE*BLOCK_SIZE-1)/(BLOCK_SIZE*BLOCK_SIZE);
    localparam integer RIGHT_FLOOR=(TAIL_COLS*BLOCK_SIZE<MIN_HITS)?TAIL_COLS*BLOCK_SIZE:MIN_HITS;
    localparam integer BOTTOM_FLOOR=(TAIL_ROWS*BLOCK_SIZE<MIN_HITS)?TAIL_ROWS*BLOCK_SIZE:MIN_HITS;
    localparam integer CORNER_FLOOR=(TAIL_COLS*TAIL_ROWS<MIN_HITS)?TAIL_COLS*TAIL_ROWS:MIN_HITS;
    // Partial tiles preserve density sensitivity, but reject one isolated hit
    // whenever their population and MIN_CHANGED permit at least two hits.
    localparam integer RIGHT_MIN=(RIGHT_RAW<RIGHT_FLOOR)?RIGHT_FLOOR:RIGHT_RAW;
    localparam integer BOTTOM_MIN=(BOTTOM_RAW<BOTTOM_FLOOR)?BOTTOM_FLOOR:BOTTOM_RAW;
    localparam integer CORNER_MIN=(CORNER_RAW<CORNER_FLOOR)?CORNER_FLOOR:CORNER_RAW;
    reg [COUNT_W-1:0] counts[0:BLOCK_COLS-1];
    reg [BLOCK_COLS*BLOCK_ROWS-1:0] working_blocks, pending_blocks;
    reg [16:0] sample_count, changed_count;
    reg frame_good, collecting, finish_pending, pending_ready;
    reg pending_reference_ready, pending_global_change;
    wire [3:0] difference=(I_current>=I_reference)?I_current-I_reference:I_reference-I_current;
    wire changed=I_reference_valid && (difference>=DIFF_THRESHOLD);
    wire [COL_W-1:0] block_col=I_sample_x>>BLOCK_SHIFT;
    wire [INDEX_W-1:0] block_index=(I_sample_y>>BLOCK_SHIFT)*BLOCK_COLS+block_col;
    wire last_col=(block_col==BLOCK_COLS-1);
    wire last_row=((I_sample_y>>BLOCK_SHIFT)==BLOCK_ROWS-1);
    wire [COUNT_W-1:0] threshold=last_col ? (last_row?CORNER_MIN:RIGHT_MIN) :
                                                         (last_row?BOTTOM_MIN:MIN_CHANGED);
    wire [COUNT_W-1:0] count_next=(changed && counts[block_col]<MIN_CHANGED)?
                                   counts[block_col]+1'b1:counts[block_col];
    wire block_x_end=((&I_sample_x[BLOCK_SHIFT-1:0]) || I_sample_x==SAMPLE_COLS-1);
    wire block_y_end=((&I_sample_y[BLOCK_SHIFT-1:0]) || I_sample_y==SAMPLE_ROWS-1);
    assign O_completed_blocks=pending_blocks;
    assign O_completed_ready=pending_reference_ready;
    assign O_completed_global=pending_global_change;
    integer i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_blocks<=0;O_reference_ready<=0;O_global_change<=0;O_completed_valid<=0;
            working_blocks<=0;pending_blocks<=0;sample_count<=0;changed_count<=0;
            frame_good<=0;collecting<=0;finish_pending<=0;pending_ready<=0;
            pending_reference_ready<=0;pending_global_change<=0;
            for(i=0;i<BLOCK_COLS;i=i+1) counts[i]<=0;
        end else if(!I_enable) begin
            O_blocks<=0;O_reference_ready<=0;O_global_change<=0;O_completed_valid<=0;
            collecting<=0;finish_pending<=0;pending_ready<=0;
        end else begin
            O_completed_valid<=0;
            finish_pending<=I_frame_end && collecting;
            if(I_frame_start) begin
                if(pending_ready) begin
                    O_blocks<=pending_blocks;
                    O_reference_ready<=pending_reference_ready;O_global_change<=pending_global_change;
                    pending_ready<=0;
                end
                working_blocks<=0;sample_count<=0;changed_count<=0;frame_good<=1;collecting<=1;
                for(i=0;i<BLOCK_COLS;i=i+1) counts[i]<=0;
            end else if(I_sample_valid && collecting) begin
                sample_count<=sample_count+1'b1;
                if(!I_reference_valid) frame_good<=0;
                if(changed) changed_count<=changed_count+1'b1;
                if(I_sample_x<SAMPLE_COLS && I_sample_y<SAMPLE_ROWS) begin
                    counts[block_col]<=count_next;
                    if(block_x_end && block_y_end) begin
                        working_blocks[block_index]<=(count_next>=threshold);
                        counts[block_col]<=0;
                    end
                end else frame_good<=0;
            end
            // An extra edge includes the final sample even when end/sample coincide.
            if(finish_pending) begin
                pending_reference_ready<=frame_good && (sample_count==TOTAL);
                pending_global_change<=frame_good && (sample_count==TOTAL) && (changed_count>TOTAL*3/4);
                pending_blocks<=(frame_good && sample_count==TOTAL && changed_count<=TOTAL*3/4)?working_blocks:0;
                pending_ready<=1;collecting<=0;O_completed_valid<=1;
            end
        end
    end
endmodule
