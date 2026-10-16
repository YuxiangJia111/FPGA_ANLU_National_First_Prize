/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 15 2026 21:17:54
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module digit_tracker_state_ram_adapter
(
  input   [15:0]                dia,
  input   [7:0]                 addra,
  input                         wea,
  input                         clka,
  output  [15:0]                dob,
  input   [7:0]                 addrb
);

  ram_123e56a8af8e
  #(
      .DATA_WIDTH_A(16),
      .ADDR_WIDTH_A(8),
      .DATA_DEPTH_A(256),
      .DATA_WIDTH_B(16),
      .ADDR_WIDTH_B(8),
      .DATA_DEPTH_B(256),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_123e56a8af8e_Inst
  (
      .dia(dia),
      .addra(addra),
      .wea(wea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb)
  );
endmodule
