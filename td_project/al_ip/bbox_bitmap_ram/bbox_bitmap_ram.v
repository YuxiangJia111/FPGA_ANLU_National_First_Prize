/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 02 2026 15:12:25
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module bbox_bitmap_ram
(
  input   [31:0]                dia,
  input   [10:0]                addra,
  input                         wea,
  input                         clka,
  output  [31:0]                dob,
  input   [10:0]                addrb
);

  ram_dfdc807800d8
  #(
      .DATA_WIDTH_A(32),
      .ADDR_WIDTH_A(11),
      .DATA_DEPTH_A(2048),
      .DATA_WIDTH_B(32),
      .ADDR_WIDTH_B(11),
      .DATA_DEPTH_B(2048),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_dfdc807800d8_Inst
  (
      .dia(dia),
      .addra(addra),
      .wea(wea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb)
  );
endmodule
