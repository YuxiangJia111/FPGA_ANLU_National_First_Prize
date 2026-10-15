/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 12 2026 19:47:17
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ps/1ps 
module RISCV_F6F1D1P0_0
(
  output                        core_sysrst,
  output                        uart0_tx,
  input                         uart0_rx,
  output                        ahb_clk,
  output  [1:0]                 htrans,
  output                        hwrite,
  output  [30:0]                haddr,
  output  [2:0]                 hsize,
  output  [2:0]                 hburst,
  output  [3:0]                 hprot,
  output                        hmastlock,
  output  [31:0]                hwdata,
  input   [31:0]                hrdata,
  input   [1:0]                 hresp,
  input                         hready,
  input                         apb_clk,
  input                         apb_rst,
  output  [19:0]                paddr,
  output                        psel,
  output                        penable,
  output                        pwrite,
  output  [31:0]                pwdata,
  output  [3:0]                 pstrobe,
  output  [2:0]                 pprot,
  input   [31:0]                prdata,
  input                         pready,
  input                         pslverr,
  input                         core_clk,
  input                         timer_clk,
  input                         core_reset,
  input                         por_reset,
  input                         nmi,
  input   [22:0]                clic_irq
);

  MCU_a31158358f1d
  #(
      .MCU_JTAG_SEL("0"),
      .MCU_RESET_VECTOR('h20E00000),
      .AHB_FREQ("150.0"),
      .MCU_DPLL_POST_DIV(4),
      .MCU_DPLL_BYPASS("DISABLE")
  )MCU_a31158358f1d_Inst
  (
      .core_sysrst(core_sysrst),
      .uart0_tx(uart0_tx),
      .uart0_rx(uart0_rx),
      .ahb_clk(ahb_clk),
      .htrans(htrans),
      .hwrite(hwrite),
      .haddr(haddr),
      .hsize(hsize),
      .hburst(hburst),
      .hprot(hprot),
      .hmastlock(hmastlock),
      .hwdata(hwdata),
      .hrdata(hrdata),
      .hresp(hresp),
      .hready(hready),
      .apb_clk(apb_clk),
      .apb_rst(apb_rst),
      .paddr(paddr),
      .psel(psel),
      .penable(penable),
      .pwrite(pwrite),
      .pwdata(pwdata),
      .pstrobe(pstrobe),
      .pprot(pprot),
      .prdata(prdata),
      .pready(pready),
      .pslverr(pslverr),
      .core_clk(core_clk),
      .timer_clk(timer_clk),
      .core_reset(core_reset),
      .por_reset(por_reset),
      .nmi(nmi),
      .clic_irq(clic_irq)
  );
endmodule
