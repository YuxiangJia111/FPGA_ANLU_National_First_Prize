`timescale 1ns / 1ps

// Fixed sidebar outside the detector ROI (ROI starts at x=198).
// Glyph selection is registered from the mixer's preceding pixel stage.
module digit_track_osd (
    input wire I_clk, I_rst_n, I_enable, I_de,
    input wire [11:0] I_x, I_y,
    input wire [7:0] I_valid,
    input wire [3:0] I_count,
    input wire [127:0] I_center_x_bcd, I_center_y_bcd,
    input wire I_motion_ready, I_motion_global,
    output reg O_hit,
    output reg [23:0] O_color
);
    wire [11:0] local_y=I_y-12'd192;
    wire [2:0] slot=local_y[8:6];
    wire [3:0] char_cell=I_x[7:4];
    wire [1:0] line=local_y[5:4];
    wire header=(I_y>=160 && I_y<176);
    wire status_line=(I_y>=176 && I_y<192);
    wire body=(I_y>=192 && I_y<704);
    wire hit=I_enable && I_de && I_x<192 && (header || status_line || body);
    reg [7:0] character;
    reg [15:0] coordinate;
    wire [15:0] glyph;
    always @(*) begin
        character=8'h20;coordinate=0;
        if(header) begin
            case(char_cell)
                0:character="T";1:character="R";2:character="A";
                3:character="C";4:character="K";6:character="N";
                7:character=":";8:character=8'h30+{4'd0,I_count};
                default:character=8'h20;
            endcase
        end else if(status_line) begin
            case(char_cell)
                0:character="D";1:character="I";2:character="F";3:character="F";4:character=":";
                5:character=I_motion_global?"L":(I_motion_ready?"R":"W");
                6:character=I_motion_global?"I":(I_motion_ready?"E":"A");
                7:character=I_motion_global?"G":(I_motion_ready?"A":"I");
                8:character=I_motion_global?"H":(I_motion_ready?"D":"T");
                9:character=I_motion_global?"T":(I_motion_ready?"Y":" ");
                default:character=8'h20;
            endcase
        end else if(body) begin
            case(line)
                0:case(char_cell)
                    0:character="I";1:character="D";2:character=":";
                    3:character=8'h31+{5'd0,slot};default:character=8'h20;
                endcase
                1,2:begin
                    coordinate=(line==1) ? I_center_x_bcd[slot*16 +: 16] :
                                          I_center_y_bcd[slot*16 +: 16];
                    case(char_cell)
                        0:character=(line==1)?"X":"Y";
                        1:character=":";
                        2:if(I_valid[slot]) character=8'h30+{4'd0,coordinate[15:12]};
                        3:if(I_valid[slot]) character=8'h30+{4'd0,coordinate[11:8]};
                        4:if(I_valid[slot]) character=8'h30+{4'd0,coordinate[7:4]};
                        5:if(I_valid[slot]) character=8'h30+{4'd0,coordinate[3:0]};
                        default:character=8'h20;
                    endcase
                end
                default:character=8'h20;
            endcase
        end
    end
    osd_char_lib u_font(.I_char(character),.I_row(I_y[3:0]),.O_row_bits(glyph));
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin O_hit<=0;O_color<=0;end
        else begin
            O_hit<=hit;
            O_color<=glyph[15-I_x[3:0]] ?
                ((header || status_line || I_valid[slot]) ? 24'h00ffff : 24'h606060) : 24'h102030;
        end
    end
endmodule
