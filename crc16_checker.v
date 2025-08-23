// crc16_checker.v
// Calculates the 16-bit CRC for USB data packets.
// The polynomial is x^16 + x^15 + x^2 + 1 (0x8005)

module crc16_checker (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [7:0] data_in,
    input wire data_valid,
    input wire data_last,
    output reg [15:0] crc_out,
    output reg crc_valid
);
    
    reg [15:0] crc_reg;
    reg [2:0] bit_count;
    reg calculating;
    
    // CRC16 polynomial: x^16 + x^15 + x^2 + 1 (0x8005)
    localparam [15:0] CRC16_POLY = 16'h8005;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            crc_reg <= 16'hFFFF;
            crc_out <= 16'h0000;
            crc_valid <= 1'b0;
            bit_count <= 3'd0;
            calculating <= 1'b0;
        end else begin
            if (start) begin
                crc_reg <= 16'hFFFF;
                crc_valid <= 1'b0;
                calculating <= 1'b1;
            end else if (calculating && data_valid) begin
                // Process each bit of the input byte
                if (bit_count == 3'd0) begin
                    // XOR input byte with CRC
                    crc_reg <= crc_reg ^ {8'h00, data_in};
                    bit_count <= 3'd7;
                end else begin
                    // Shift and apply polynomial if MSB is 1
                    if (crc_reg[15]) begin
                        crc_reg <= (crc_reg << 1) ^ CRC16_POLY;
                    end else begin
                        crc_reg <= crc_reg << 1;
                    end
                    bit_count <= bit_count - 1;
                end
                
                if (data_last && bit_count == 3'd1) begin
                    calculating <= 1'b0;
                    crc_out <= ~crc_reg;  // Invert final CRC
                    crc_valid <= 1'b1;
                end
            end
        end
    end
endmodule
