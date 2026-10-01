// RTL source: addressRAM.
module addressRAM (
    input [4:0] step,
    output reg re_RAM,
    output reg [12:0] firstaddr,
    lastaddr
);
    parameter picture_size = 0;
    parameter convolution_size = 0;

    parameter picture_storage_limit = picture_size * picture_size;
    parameter convweight = picture_storage_limit + (1 * 4 + 4 * 4 + 4 * 8 + 8 * 8) * convolution_size;

    parameter conv1 = picture_storage_limit + 1 * 4 * convolution_size;
    parameter conv2 = picture_storage_limit + (1 * 4 + 4 * 4) * convolution_size;
    parameter conv3 = picture_storage_limit + (1 * 4 + 4 * 4 + 4 * 8) * convolution_size;
    parameter conv4 = picture_storage_limit + (1 * 4 + 4 * 4 + 4 * 8 + 8 * 8) * convolution_size;
    parameter conv5 = picture_storage_limit + (1 * 4 + 4 * 4 + 4 * 8 + 8 * 8 + 8 * 16) * convolution_size;
    parameter conv6 = picture_storage_limit + (1 * 4 + 4 * 4 + 4 * 8 + 8 * 8 + 8 * 16 + 16 * 16) * convolution_size;

    parameter dense = conv6 + 176;

    always @(step)
        case (step)
            1'd1: begin
                firstaddr = 0;
                lastaddr  = picture_storage_limit;
                re_RAM    = 1;
            end
            2'd2: begin
                firstaddr = picture_storage_limit;
                lastaddr  = conv1;
                re_RAM    = 1;
            end
            3'd4: begin
                firstaddr = conv1;
                lastaddr  = conv2;
                re_RAM    = 1;
            end
            3'd6: begin
                firstaddr = conv2;
                lastaddr  = conv3;
                re_RAM    = 1;
            end
            4'd8: begin
                firstaddr = conv3;
                lastaddr  = conv4;
                re_RAM    = 1;
            end
            4'd10: begin
                firstaddr = conv4;
                lastaddr  = conv5;
                re_RAM    = 1;
            end
            4'd12: begin
                firstaddr = conv5;
                lastaddr  = conv6;
                re_RAM    = 1;
            end
            4'd14: begin
                firstaddr = conv6;
                lastaddr  = dense;
                re_RAM    = 1;
            end
            default: begin
                firstaddr = 13'd0;
                lastaddr  = 13'd0;
                re_RAM    = 1'b0;
            end
        endcase
endmodule
