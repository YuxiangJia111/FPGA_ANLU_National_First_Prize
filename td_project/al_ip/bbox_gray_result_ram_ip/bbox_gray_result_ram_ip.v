/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 02 2026 21:41:27
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module bbox_gray_result_ram_ip
(
  input   [7:0]                 dia,
  input   [12:0]                addra,
  input                         wea,
  input                         clka,
  output  [7:0]                 dob,
  input   [12:0]                addrb
);

  ram_768546b6a57c
  #(
      .DATA_WIDTH_A(8),
      .ADDR_WIDTH_A(13),
      .DATA_DEPTH_A(8192),
      .DATA_WIDTH_B(8),
      .ADDR_WIDTH_B(13),
      .DATA_DEPTH_B(8192),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_768546b6a57c_Inst
  (
      .dia(dia),
      .addra(addra),
      .wea(wea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb)
  );
endmodule
