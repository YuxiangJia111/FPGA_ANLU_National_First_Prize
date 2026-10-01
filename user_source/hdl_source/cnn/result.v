// RTL source: result.
module result (
    clk,
    enable,
    STOP,
    memstartp,
    read_addressp,
    qp,
    re,
    RESULT
);

    parameter SIZE_1 = 0;
    parameter SIZE_2 = 0;
    parameter SIZE_3 = 0;
    parameter SIZE_4 = 0;
    parameter SIZE_address_pix = 0;

    input clk, enable;
    output reg STOP;
    input [SIZE_address_pix-1:0] memstartp;
    input [SIZE_1-1:0] qp;
    output reg re;
    output reg [SIZE_address_pix-1:0] read_addressp;
    output reg [3:0] RESULT;

    reg         [       3:0] marker;
    reg signed  [SIZE_1-1:0] buff;

    wire signed [SIZE_1-1:0] p1;
    always @(posedge clk) begin
        if (enable == 1) begin
            re = 1;
            if (marker <= 12) read_addressp = memstartp + marker;

            if (marker == 1) buff = 0;
            else if ((marker >= 2) && (marker <= 12) && (p1 >= buff)) begin
                buff   = p1;
                RESULT = marker - 2;
            end

            if (marker == 12) STOP = 1;
            else marker = marker + 1;
        end else begin
            re     = 0;
            marker = 0;
            STOP   = 0;
        end
    end

    assign p1 = qp[SIZE_1-1:0];
endmodule
