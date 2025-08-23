// crc5_checker.v
// Calculates the 5-bit CRC for USB token packets.
// The polynomial is x^5 + x^2 + 1 (0x05)

module crc5_checker (
    input wire clk,
    input wire reset,
    input wire [10:0] data_in,  // 7-bit addr + 4-bit endpoint
    output reg [4:0] crc_out
);
    
    reg [4:0] crc_reg;
    integer i;
    
    // CRC5 polynomial: x^5 + x^2 + 1 (0x05)
    localparam [4:0] CRC5_POLY = 5'b00101;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            crc_reg <= 5'b11111;
            crc_out <= 5'b00000;
        end else begin
            crc_reg <= 5'b11111;  // Initialize
            
            // Process each bit of the 11-bit input
            for (i = 10; i >= 0; i = i - 1) begin
                if (crc_reg[4] ^ data_in[i]) begin
                    crc_reg <= (crc_reg << 1) ^ CRC5_POLY;
                end else begin
                    crc_reg <= crc_reg << 1;
                end
            end
            
            crc_out <= ~crc_reg;  // Invert final CRC
        end
    end
endmodule
