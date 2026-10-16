`timescale 1ns/1ps

// Eight fixed 32x32 arrow sprites share one small geometry renderer.
// Stage 1 selects the target/tile; stage 2 renders its glyph. Feed raw mixer
// coordinates so O_hit aligns with S_x_2d/S_y_2d and the existing video data.
module digit_motion_arrow_osd #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720
) (
    input wire I_clk, I_rst_n, I_enable, I_vblank, I_de,
    input wire [11:0] I_x, I_y,
    input wire [7:0] I_box_valid, I_arrow_valid,
    input wire [23:0] I_direction,
    input wire [95:0] I_x_min, I_x_max, I_y_min,
    output reg O_hit
);
    localparam [11:0] MAX_X=IMG_WIDTH-32, MAX_Y=IMG_HEIGHT-32;
    // Match the mixer's latency HUD: x=width-336..width-17, y=16..47.
    localparam [11:0] HUD_X=IMG_WIDTH-336;
    reg [11:0] origin_x[0:7], origin_y[0:7];
    wire [11:0] dx[0:7], dy[0:7];
    wire [7:0] tile_hit;
    reg selected;
    reg [4:0] tile_x, tile_y;
    reg [2:0] tile_direction;
    reg selected_q;
    reg [4:0] x_q,y_q;
    reg [2:0] direction_q;
    reg [4:0] gx,gy;
    wire [5:0] sum_xy={1'b0,gx}+{1'b0,gy};
    wire [5:0] x_ext={1'b0,gx}, y_ext={1'b0,gy};
    reg glyph;
    genvar s;
    generate for(s=0;s<8;s=s+1)begin : g_tile
        wire [11:0] place_x=(I_x_max[s*12+:12]<=IMG_WIDTH-40)?I_x_max[s*12+:12]+12'd8:
            ((I_x_min[s*12+:12]>=40)?
             ((I_x_min[s*12+:12]-12'd40>MAX_X)?MAX_X:I_x_min[s*12+:12]-12'd40):12'd0);
        wire [11:0] place_y=(I_y_min[s*12+:12]>MAX_Y)?MAX_Y:I_y_min[s*12+:12];
        wire overlaps_hud=(IMG_WIDTH>=336) && (place_x<IMG_WIDTH-16) &&
            (place_x+12'd31>=HUD_X) && (place_y<48) && (place_y+12'd31>=16);
        always @(posedge I_clk or negedge I_rst_n)begin
            if(!I_rst_n)begin origin_x[s]<=0;origin_y[s]<=0;end
            else if(I_vblank)begin
                // Prefer the box's right side. Near the right edge, move the
                // entire sprite to its left; clamp vertical position to screen.
                origin_x[s]<=place_x;
                // Keep arrows visible below the right-top latency HUD.
                origin_y[s]<=overlaps_hud?((MAX_Y<52)?MAX_Y:12'd52):place_y;
            end
        end
        assign dx[s]=I_x-origin_x[s];
        assign dy[s]=I_y-origin_y[s];
        assign tile_hit[s]=I_box_valid[s] && I_arrow_valid[s] &&
            (I_x>=origin_x[s]) && (I_y>=origin_y[s]) && (dx[s]<32) && (dy[s]<32);
    end endgenerate
    integer i;
    always @(*)begin
        selected=0;tile_x=0;tile_y=0;tile_direction=0;
        // Lowest ID wins an overlapping sprite window.
        for(i=0;i<8;i=i+1)if(tile_hit[i] && !selected)begin
            selected=1;tile_x=dx[i][4:0];tile_y=dy[i][4:0];tile_direction=I_direction[i*3+:3];
        end
        // 0 R, 1 DR, 2 D, 3 DL, 4 L, 5 UL, 6 U, 7 UR.
        // Bitwise complements perform exact 31-coordinate rotations.
        case(direction_q[2:1])
            0:begin gx=x_q;gy=y_q;end
            1:begin gx=y_q;gy=~x_q;end
            2:begin gx=~x_q;gy=~y_q;end
            default:begin gx=~y_q;gy=x_q;end
        endcase
        if(!direction_q[0])begin
            glyph=((gx>=4 && gx<=28) && (gy>=15 && gy<=17)) ||
                ((gx>=20 && gx<=28 && gy>=8 && gy<=16) && (x_ext>=y_ext+11 && x_ext<=y_ext+13)) ||
                ((gx>=20 && gx<=28 && gy>=16 && gy<=24) && (sum_xy>=43 && sum_xy<=45));
        end else begin
            glyph=((gx>=6 && gx<=26 && gy>=6 && gy<=26) &&
                   (x_ext+1>=y_ext && y_ext+1>=x_ext)) ||
                (gx>=16 && gx<=27 && gy>=25 && gy<=27) ||
                (gy>=16 && gy<=27 && gx>=25 && gx<=27);
        end
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin selected_q<=0;x_q<=0;y_q<=0;direction_q<=0;O_hit<=0;end
        else begin
            selected_q<=I_enable && I_de && I_x<IMG_WIDTH && I_y<IMG_HEIGHT && selected;
            x_q<=tile_x;y_q<=tile_y;direction_q<=tile_direction;
            O_hit<=selected_q && glyph;
        end
    end
endmodule
