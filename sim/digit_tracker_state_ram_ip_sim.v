`timescale 1ns/1ps

// Simulation-only binding until the user generates the real TD IP.
// Uses the same vendor primitive/configuration as the required generated IP.
// NEVER add this file to the synthesis project.
module digit_tracker_state_ram_adapter (
    input wire [15:0] dia,
    input wire [7:0] addra,
    input wire wea, clka,
    output wire [15:0] dob,
    input wire [7:0] addrb
);
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(8), .ADDR_WIDTH_B(8),
        .DATA_DEPTH_A(256), .DATA_DEPTH_B(256),
        .MODE("PDPW"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K"), .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
        .CLKMODE("SYNC"), .SSROVERCE("DISABLE"),
        .OREGSET_A("SET"), .OREGSET_B("SET"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("SYNC"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE")
    ) u_vendor_ram (
        .dia(dia), .dib(16'd0), .addra(addra), .addrb(addrb),
        .cea(1'b1), .ceb(1'b1), .ocea(1'b0), .oceb(1'b0),
        .clka(clka), .clkb(clka), .wea(wea), .web(1'b0),
        .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0),
        .ecc_sbiterr(), .ecc_dbiterr(), .ecc_sbiterrinj(), .ecc_dbiterrinj(),
        .doa(), .dob(dob)
    );
endmodule
