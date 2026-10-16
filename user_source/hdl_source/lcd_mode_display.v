`timescale 1ns / 1ns

module lcd_mode_display #(
    parameter CLK_HZ=50000000, parameter SPI_DIV=25, parameter FILL_COLOR=16'h0000
) (
    input wire I_clk, input wire I_rst_n, input wire [2:0] I_mode,
    input wire [15:0] I_latency_ms, input wire I_latency_valid,
    output wire O_scl, output wire O_sda, output wire O_rst, output wire O_dc, output wire O_cs,
    output wire O_initialized, output wire O_ready, output reg [2:0] O_displayed_mode
);
    localparam S_IDLE=3'd0, S_WINDOW_LOAD=3'd1, S_COMMAND_SEND=3'd2,
               S_GLYPH_LOAD=3'd3, S_PIXEL_LOAD=3'd4, S_BYTE_LOAD=3'd5,
               S_PIXEL_SEND=3'd6, S_LAT_CONVERT=3'd7;
    localparam LATENCY_INTERVAL = (CLK_HZ < 2) ? 32'd1 : CLK_HZ / 2;

    wire init_scl,init_sda,init_rst,init_dc,init_cs,init_done,fill_done;
    reg [2:0] mode_meta,mode_sync,mode_last,mode_stable,mode_latched;
    reg [15:0] latency_meta,latency_sync,latency_last,latency_stable,latency_latched;
    reg latency_valid_meta,latency_valid_sync,latency_valid_last,latency_valid_stable;
    reg [2:0] state;
    reg [3:0] window_index;
    reg [1:0] phase,region;
    reg [2:0] bit_index;
    reg [7:0] tx_data;
    reg [8:0] pixel_x;
    reg [5:0] pixel_y;
    reg [4:0] local_x;
    reg [3:0] local_y;
    reg [3:0] char_index;
    reg [2:0] glyph_col,glyph_row;
    reg [6:0] glyph_bits;
    reg [15:0] pixel_word;
    reg pixel_low;
    reg title_done,ready_reg;
    reg writer_scl,writer_sda,writer_rst,writer_dc,writer_cs;
    reg [5:0] divider;
    reg [31:0] latency_refresh_count;
    reg latency_rendered,latency_valid_latched;
    reg conv_request,conv_busy,conv_done;
    reg [4:0] conv_count;
    reg [15:0] conv_shift;
    reg [3:0] conv_hundreds,conv_tens,conv_ones;

    wire tick=(divider==SPI_DIV-1);
    wire mode_changed=(mode_stable!=O_displayed_mode);
    wire latency_changed=(latency_valid_stable!=latency_valid_latched) ||
                          (latency_valid_stable && (latency_stable!=latency_latched));
    wire latency_refresh_allowed=(latency_refresh_count >= LATENCY_INTERVAL-1);

    assign O_scl=fill_done?writer_scl:init_scl;
    assign O_sda=fill_done?writer_sda:init_sda;
    assign O_rst=fill_done?writer_rst:init_rst;
    assign O_dc=fill_done?writer_dc:init_dc;
    assign O_cs=fill_done?writer_cs:init_cs;
    assign O_initialized=init_done;
    assign O_ready=ready_reg;

    lcd_hw_test #(.CLK_HZ(CLK_HZ),.SPI_DIV(SPI_DIV),.FILL_COLOR(FILL_COLOR)) u_init (
        .I_clk(I_clk),.I_rst_n(I_rst_n),.O_scl(init_scl),.O_sda(init_sda),.O_rst(init_rst),
        .O_dc(init_dc),.O_cs(init_cs),.O_init_done(init_done),.O_done(fill_done));

    function [6:0] font_col;
        input [5:0] c; input [2:0] col;
        begin
            case(c)
              0:case(col)0:font_col=7'h7e;1:font_col=7'h11;2:font_col=7'h11;3:font_col=7'h11;default:font_col=7'h7e;endcase
              1:case(col)0:font_col=7'h7f;1:font_col=7'h49;2:font_col=7'h49;3:font_col=7'h49;default:font_col=7'h36;endcase
              2:case(col)0:font_col=7'h3e;1:font_col=7'h41;2:font_col=7'h41;3:font_col=7'h41;default:font_col=7'h22;endcase
              3:case(col)0:font_col=7'h7f;1:font_col=7'h41;2:font_col=7'h41;3:font_col=7'h22;default:font_col=7'h1c;endcase
              4:case(col)0:font_col=7'h7f;1:font_col=7'h49;2:font_col=7'h49;3:font_col=7'h49;default:font_col=7'h41;endcase
              5:case(col)0:font_col=7'h7f;1:font_col=7'h09;2:font_col=7'h09;3:font_col=7'h09;default:font_col=7'h01;endcase
              6:case(col)0:font_col=7'h3e;1:font_col=7'h41;2:font_col=7'h49;3:font_col=7'h49;default:font_col=7'h7a;endcase
              7:case(col)0:font_col=7'h7f;1:font_col=7'h08;2:font_col=7'h08;3:font_col=7'h08;default:font_col=7'h7f;endcase
              8:case(col)0:font_col=7'h00;1:font_col=7'h41;2:font_col=7'h7f;3:font_col=7'h41;default:font_col=7'h00;endcase
              9:case(col)0:font_col=7'h20;1:font_col=7'h40;2:font_col=7'h41;3:font_col=7'h3f;default:font_col=7'h01;endcase
              10:case(col)0:font_col=7'h7f;1:font_col=7'h08;2:font_col=7'h14;3:font_col=7'h22;default:font_col=7'h41;endcase
              11:case(col)0:font_col=7'h7f;1:font_col=7'h40;2:font_col=7'h40;3:font_col=7'h40;default:font_col=7'h40;endcase
              12:case(col)0:font_col=7'h7f;1:font_col=7'h02;2:font_col=7'h0c;3:font_col=7'h02;default:font_col=7'h7f;endcase
              13:case(col)0:font_col=7'h7f;1:font_col=7'h04;2:font_col=7'h08;3:font_col=7'h10;default:font_col=7'h7f;endcase
              14:case(col)0:font_col=7'h3e;1:font_col=7'h41;2:font_col=7'h41;3:font_col=7'h41;default:font_col=7'h3e;endcase
              15:case(col)0:font_col=7'h7f;1:font_col=7'h09;2:font_col=7'h09;3:font_col=7'h09;default:font_col=7'h06;endcase
              16:case(col)0:font_col=7'h7f;1:font_col=7'h09;2:font_col=7'h19;3:font_col=7'h29;default:font_col=7'h46;endcase
              17:case(col)0:font_col=7'h7f;1:font_col=7'h09;2:font_col=7'h19;3:font_col=7'h29;default:font_col=7'h46;endcase
              18:case(col)0:font_col=7'h46;1:font_col=7'h49;2:font_col=7'h49;3:font_col=7'h49;default:font_col=7'h31;endcase
              19:case(col)0:font_col=7'h01;1:font_col=7'h01;2:font_col=7'h7f;3:font_col=7'h01;default:font_col=7'h01;endcase
              20:case(col)0:font_col=7'h3f;1:font_col=7'h40;2:font_col=7'h40;3:font_col=7'h40;default:font_col=7'h3f;endcase
              21:case(col)0:font_col=7'h1f;1:font_col=7'h20;2:font_col=7'h40;3:font_col=7'h20;default:font_col=7'h1f;endcase
              22:case(col)0:font_col=7'h3f;1:font_col=7'h40;2:font_col=7'h38;3:font_col=7'h40;default:font_col=7'h3f;endcase
              23:case(col)0:font_col=7'h63;1:font_col=7'h14;2:font_col=7'h08;3:font_col=7'h14;default:font_col=7'h63;endcase
              24:case(col)0:font_col=7'h07;1:font_col=7'h08;2:font_col=7'h70;3:font_col=7'h08;default:font_col=7'h07;endcase
              25:case(col)0:font_col=7'h61;1:font_col=7'h51;2:font_col=7'h49;3:font_col=7'h45;default:font_col=7'h43;endcase
              26:font_col=7'h00;
              27:case(col)0:font_col=7'h3e;1:font_col=7'h41;2:font_col=7'h41;3:font_col=7'h41;default:font_col=7'h3e;endcase
              28:case(col)0:font_col=7'h06;1:font_col=7'h49;2:font_col=7'h49;3:font_col=7'h49;default:font_col=7'h30;endcase
              29:case(col)0:font_col=7'h42;1:font_col=7'h51;2:font_col=7'h49;3:font_col=7'h45;default:font_col=7'h42;endcase
              30:case(col)0:font_col=7'h22;1:font_col=7'h41;2:font_col=7'h49;3:font_col=7'h49;default:font_col=7'h3e;endcase
              31:case(col)0:font_col=7'h0f;1:font_col=7'h08;2:font_col=7'h08;3:font_col=7'h7f;default:font_col=7'h08;endcase
              32:case(col)0:font_col=7'h4f;1:font_col=7'h49;2:font_col=7'h49;3:font_col=7'h49;default:font_col=7'h79;endcase
              33:case(col)0:font_col=7'h3e;1:font_col=7'h49;2:font_col=7'h49;3:font_col=7'h79;default:font_col=7'h3a;endcase
              34:case(col)0:font_col=7'h01;1:font_col=7'h71;2:font_col=7'h09;3:font_col=7'h05;default:font_col=7'h03;endcase
              35:case(col)0:font_col=7'h36;1:font_col=7'h49;2:font_col=7'h49;3:font_col=7'h49;default:font_col=7'h36;endcase
              36:case(col)0:font_col=7'h46;1:font_col=7'h49;2:font_col=7'h49;3:font_col=7'h09;default:font_col=7'h7e;endcase
              37:case(col)0:font_col=7'h00;1:font_col=7'h36;2:font_col=7'h36;3:font_col=7'h00;default:font_col=7'h00;endcase
              38:case(col)0:font_col=7'h7c;1:font_col=7'h04;2:font_col=7'h74;3:font_col=7'h04;default:font_col=7'h78;endcase
              39:case(col)0:font_col=7'h08;1:font_col=7'h54;2:font_col=7'h54;3:font_col=7'h54;default:font_col=7'h24;endcase
              default:font_col=7'h00;
            endcase
        end
    endfunction

    function [5:0] glyph_char;
        input [1:0] r; input [2:0] m; input [3:0] i;
        input [3:0] hundreds,tens,ones;
        begin
            if(r==0) case(i) 0:glyph_char=21;1:glyph_char=8;2:glyph_char=3;3:glyph_char=4;4:glyph_char=14;5:glyph_char=26;6:glyph_char=12;7:glyph_char=14;default:glyph_char=3; endcase
            else if(r==1) case(m)
              0:case(i)0:glyph_char=14;1:glyph_char=17;2:glyph_char=8;3:glyph_char=6;4:glyph_char=8;5:glyph_char=13;6:glyph_char=0;default:glyph_char=11;endcase
              1:case(i)0:glyph_char=6;1:glyph_char=17;2:glyph_char=0;3:glyph_char=24;default:glyph_char=26;endcase
              2:case(i)0:glyph_char=1;1:glyph_char=8;2:glyph_char=13;3:glyph_char=0;4:glyph_char=17;default:glyph_char=24;endcase
              3:case(i)0:glyph_char=18;1:glyph_char=14;2:glyph_char=1;3:glyph_char=4;default:glyph_char=11;endcase
              4:case(i)0:glyph_char=0;1:glyph_char=20;2:glyph_char=19;3:glyph_char=14;4:glyph_char=26;5:glyph_char=4;6:glyph_char=23;default:glyph_char=15;endcase
              5:case(i)0:glyph_char=4;1:glyph_char=16;2:glyph_char=20;3:glyph_char=0;4:glyph_char=11;5:glyph_char=8;6:glyph_char=25;default:glyph_char=4;endcase
              6:case(i)0:glyph_char=15;1:glyph_char=17;2:glyph_char=4;3:glyph_char=21;4:glyph_char=8;5:glyph_char=4;default:glyph_char=22;endcase
              default:case(i)0:glyph_char=19;1:glyph_char=17;2:glyph_char=0;3:glyph_char=2;4:glyph_char=10;default:glyph_char=26;endcase
            endcase
            else case(i) 0:glyph_char=11;1:glyph_char=0;2:glyph_char=19;3:glyph_char=4;4:glyph_char=13;5:glyph_char=2;6:glyph_char=24;7:glyph_char=37;8:glyph_char=26;9:glyph_char=27+hundreds;10:glyph_char=27+tens;11:glyph_char=27+ones;12:glyph_char=38;default:glyph_char=39; endcase
        end
    endfunction

    function [7:0] window_byte;
        input [3:0] i; input [1:0] r;
        begin
            if(i==10) window_byte=8'h2c;
            else if(r==0) case(i)0:window_byte=8'h2a;1:window_byte=0;2:window_byte=8'h1e;3:window_byte=0;4:window_byte=8'hd1;5:window_byte=8'h2b;6:window_byte=0;7:window_byte=8'h28;8:window_byte=0;9:window_byte=8'h3c;default:window_byte=0;endcase
            else if(r==1) case(i)0:window_byte=8'h2a;1:window_byte=0;2:window_byte=8'h18;3:window_byte=0;4:window_byte=8'hd7;5:window_byte=8'h2b;6:window_byte=0;7:window_byte=8'h7d;8:window_byte=0;9:window_byte=8'h98;default:window_byte=0;endcase
            else case(i)0:window_byte=8'h2a;1:window_byte=0;2:window_byte=8'h24;3:window_byte=0;4:window_byte=8'hcb;5:window_byte=8'h2b;6:window_byte=0;7:window_byte=8'hd2;8:window_byte=0;9:window_byte=8'hdf;default:window_byte=0;endcase
        end
    endfunction
    reg [3:0] latency_hundreds,latency_tens,latency_ones;

    wire [3:0] adjusted_hundreds=(conv_hundreds>=5)?conv_hundreds+3:conv_hundreds;
    wire [3:0] adjusted_tens=(conv_tens>=5)?conv_tens+3:conv_tens;
    wire [3:0] adjusted_ones=(conv_ones>=5)?conv_ones+3:conv_ones;

    // One double-dabble bit is processed per raw clock, not per SPI tick.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            conv_busy<=0;conv_done<=0;conv_count<=0;conv_shift<=0;
            conv_hundreds<=0;conv_tens<=0;conv_ones<=0;
        end else if(conv_request && !conv_busy) begin
            conv_busy<=1;conv_done<=0;conv_count<=0;
            conv_shift<=latency_valid_latched ?
                ((latency_latched>999)?16'd999:latency_latched):16'd0;
            conv_hundreds<=0;conv_tens<=0;conv_ones<=0;
        end else if(conv_busy) begin
            conv_hundreds<={adjusted_hundreds[2:0],adjusted_tens[3]};
            conv_tens<={adjusted_tens[2:0],adjusted_ones[3]};
            conv_ones<={adjusted_ones[2:0],conv_shift[15]};
            conv_shift<=conv_shift<<1;
            if(conv_count==15) begin conv_busy<=0;conv_done<=1;end
            else conv_count<=conv_count+1'b1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            mode_meta<=0;mode_sync<=0;mode_last<=0;mode_stable<=0;
            latency_meta<=0;latency_sync<=0;latency_last<=0;latency_stable<=0;
            latency_valid_meta<=0;latency_valid_sync<=0;latency_valid_last<=0;latency_valid_stable<=0;
        end else begin
            mode_meta<=I_mode; mode_sync<=mode_meta; if(mode_sync==mode_last) mode_stable<=mode_sync; mode_last<=mode_sync;
            latency_meta<=I_latency_ms; latency_sync<=latency_meta; if(latency_sync==latency_last) latency_stable<=latency_sync; latency_last<=latency_sync;
            latency_valid_meta<=I_latency_valid; latency_valid_sync<=latency_valid_meta; if(latency_valid_sync==latency_valid_last) latency_valid_stable<=latency_valid_sync; latency_valid_last<=latency_valid_sync;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=S_IDLE;window_index<=0;phase<=0;bit_index<=0;tx_data<=0;pixel_x<=0;pixel_y<=0;
            local_x<=0;local_y<=0;char_index<=0;glyph_col<=0;glyph_row<=0;glyph_bits<=0;pixel_word<=0;pixel_low<=0;
            region<=0;title_done<=0;ready_reg<=0;O_displayed_mode<=0;writer_scl<=0;writer_sda<=0;writer_rst<=1;writer_dc<=1;writer_cs<=1;
            mode_latched<=0;latency_latched<=0;divider<=0;latency_refresh_count<=0;latency_hundreds<=0;latency_tens<=0;latency_ones<=0;latency_rendered<=0;latency_valid_latched<=0;conv_request<=0;
        end else begin
            conv_request<=0;
            if(latency_refresh_count != 32'hffffffff) latency_refresh_count<=latency_refresh_count+1'b1;
            writer_rst<=1;
            if(!tick) divider<=divider+1'b1;
            else begin
                divider<=0;
                conv_request<=0;
                if(!fill_done) begin writer_scl<=0;writer_cs<=1;writer_dc<=1;state<=S_IDLE;ready_reg<=0;end
                else case(state)
                  S_IDLE: begin
                    writer_scl<=0;writer_cs<=1;writer_dc<=1;
                    if(!title_done) begin region<=0;window_index<=0;mode_latched<=mode_stable;pixel_x<=0;pixel_y<=0;local_x<=0;local_y<=0;char_index<=0;glyph_col<=0;glyph_row<=0;pixel_low<=0;state<=S_WINDOW_LOAD;end
                    else if(!ready_reg || mode_changed) begin region<=1;window_index<=0;mode_latched<=mode_stable;pixel_x<=0;pixel_y<=0;local_x<=0;local_y<=0;char_index<=0;glyph_col<=0;glyph_row<=0;pixel_low<=0;state<=S_WINDOW_LOAD;end
                    else if(((latency_valid_stable && (!latency_rendered || latency_changed)) ||
                              (!latency_valid_stable && latency_valid_latched)) && latency_refresh_allowed) begin region<=2;window_index<=0;latency_latched<=latency_stable;latency_valid_latched<=latency_valid_stable;latency_refresh_count<=0;pixel_x<=0;pixel_y<=0;local_x<=0;local_y<=0;char_index<=0;glyph_col<=0;glyph_row<=0;pixel_low<=0;conv_request<=1;state<=S_LAT_CONVERT;end
                  end
                  S_LAT_CONVERT: begin if(conv_done) begin latency_hundreds<=conv_hundreds;latency_tens<=conv_tens;latency_ones<=conv_ones;state<=S_WINDOW_LOAD;end end
                  S_WINDOW_LOAD: begin tx_data<=window_byte(window_index,region);writer_dc<=((window_index==0)||(window_index==5)||(window_index==10))?0:1;writer_cs<=0;writer_scl<=0;bit_index<=7;phase<=0;state<=S_COMMAND_SEND;end
                  S_COMMAND_SEND: begin
                    if(phase==0) begin writer_sda<=tx_data[bit_index];writer_scl<=0;phase<=1;end
                    else if(phase==1) begin writer_scl<=1;phase<=2;end
                    else begin
                        writer_scl<=0;phase<=0;
                        if(bit_index!=0) bit_index<=bit_index-1'b1;
                        else if(window_index!=10) begin writer_cs<=1;window_index<=window_index+1'b1;state<=S_WINDOW_LOAD;end
                        else begin pixel_low<=0;state<=S_GLYPH_LOAD;end
                    end
                  end
                  S_GLYPH_LOAD: begin if(glyph_col>=5) glyph_bits<=7'h00; else glyph_bits<=font_col(glyph_char(region,mode_latched,char_index,latency_hundreds,latency_tens,latency_ones),glyph_col);state<=S_PIXEL_LOAD;end
                  S_PIXEL_LOAD: begin pixel_word<=glyph_bits[glyph_row]?((region==1)?16'hffe0:(region==2)?16'h07e0:16'h07ff):16'h0000;state<=S_BYTE_LOAD;end
                  S_BYTE_LOAD: begin tx_data<=pixel_low?pixel_word[7:0]:pixel_word[15:8];writer_dc<=1;writer_cs<=0;writer_scl<=0;bit_index<=7;phase<=0;state<=S_PIXEL_SEND;end
                  S_PIXEL_SEND: begin
                    if(phase==0) begin writer_sda<=tx_data[bit_index];writer_scl<=0;phase<=1;end
                    else if(phase==1) begin writer_scl<=1;phase<=2;end
                    else begin
                        writer_scl<=0;phase<=0;
                        if(bit_index!=0) bit_index<=bit_index-1'b1;
                        else if(!pixel_low) begin pixel_low<=1;state<=S_BYTE_LOAD;end
                        else if(((region==0)&&(pixel_x==179)&&(pixel_y==20))||((region==1)&&(pixel_x==191)&&(pixel_y==27))||((region==2)&&(pixel_x==167)&&(pixel_y==13))) begin
                            writer_cs<=1;pixel_low<=0;
                            if(region==0) title_done<=1;
                            else if(region==1) begin O_displayed_mode<=mode_latched;ready_reg<=1;end
                             else begin latency_rendered<=1;end
                            state<=S_IDLE;
                        end else begin
                            pixel_low<=0;pixel_x<=pixel_x+1'b1;
                            if((region==0 && pixel_x==179)||(region==1 && pixel_x==191)||(region==2 && pixel_x==167)) begin pixel_x<=0;pixel_y<=pixel_y+1'b1;local_x<=0;char_index<=0;glyph_col<=0; if((region==0 && local_y==20)||(region==1 && local_y==27)||(region==2 && local_y==13)) begin local_y<=0;glyph_row<=0;end else begin local_y<=local_y+1'b1; if((region==0 && ((local_y==2)||(local_y==5)||(local_y==8)||(local_y==11)||(local_y==14)||(local_y==17)))||(region==1 && ((local_y==3)||(local_y==7)||(local_y==11)||(local_y==15)||(local_y==19)||(local_y==23)))||(region==2 && ((local_y==1)||(local_y==3)||(local_y==5)||(local_y==7)||(local_y==9)||(local_y==11)))) glyph_row<=glyph_row+1'b1;end end
                            else begin local_x<=local_x+1'b1; if((region==0 && ((local_x==2)||(local_x==5)||(local_x==8)||(local_x==11)||(local_x==14)))||(region==1 && ((local_x==3)||(local_x==7)||(local_x==11)||(local_x==15)||(local_x==19)))||(region==2 && ((local_x==1)||(local_x==3)||(local_x==5)||(local_x==7)||(local_x==9)))) glyph_col<=glyph_col+1'b1; if((region==0 && local_x==17)||(region==1 && local_x==23)||(region==2 && local_x==11)) begin local_x<=0;char_index<=char_index+1'b1;glyph_col<=0;end end
                            state<=S_GLYPH_LOAD;
                        end
                    end
                  end
                  default: state<=S_IDLE;
                endcase
            end
        end
    end
endmodule
