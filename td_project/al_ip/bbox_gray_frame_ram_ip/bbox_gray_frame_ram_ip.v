/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 08 2026 18:46:05
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module bbox_gray_frame_ram_ip
(
  input   [3:0]                 dia,
  input   [15:0]                addra,
  input                         wea,
  input                         clka,
  output  [3:0]                 dob,
  input   [15:0]                addrb
);

  ram_e78534da668e
  #(
      .DATA_WIDTH_A(4),
      .ADDR_WIDTH_A(16),
      .DATA_DEPTH_A(65536),
      .DATA_WIDTH_B(4),
      .ADDR_WIDTH_B(16),
      .DATA_DEPTH_B(65536),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_e78534da668e_Inst
  (
      .dia(dia),
      .addra(addra),
      .wea(wea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb)
  );
endmodule
