module usb_clock_and_bitstuff (
    input wire clk,          // Clock input (assumed 60 MHz for ULPI)
    input wire reset,        // Active-high reset
    input wire nrzi_in,      // NRZI-encoded input bitstream
    output reg [7:0] byte_out, // Decoded and destuffed byte output
    output reg valid_out     // Indicates valid byte output
);

    reg prev;                // Previous NRZI input for decoding
    reg [7:0] shift;         // Shift register for byte assembly
    reg [2:0] bit_cnt;       // Bit counter for byte assembly
    reg [2:0] one_count;     // Counter for consecutive '1's
    reg [2:0] state;         // State machine for SYNC detection and data processing
    reg decoded_bit;         // Decoded NRZI bit

    localparam [2:0]
        IDLE = 3'd0,         // Waiting for SYNC pattern
        SYNC = 3'd1,         // Detecting SYNC pattern (00000001)
        DATA = 3'd2;         // Processing data bits

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            prev <= 1'b1;        // Initialize to USB idle state (high)
            shift <= 8'd0;
            bit_cnt <= 3'd0;
            one_count <= 3'd0;
            valid_out <= 1'b0;
            state <= IDLE;
            byte_out <= 8'd0;
            decoded_bit <= 1'b0;
        end else begin
            // Default outputs
            valid_out <= 1'b0;

            // NRZI decoding
            decoded_bit = (nrzi_in == prev) ? 1'b1 : 1'b0; // No transition = '1', transition = '0'
            prev <= nrzi_in;

            case (state)
                IDLE: begin
                    bit_cnt <= 3'd0;
                    one_count <= 3'd0;
                    shift <= 8'd0;
                    // Wait for SYNC pattern start (first '0' after NRZI decode)
                    if (decoded_bit == 1'b0) begin
                        shift <= {7'd0, decoded_bit};
                        bit_cnt <= 3'd1;
                        state <= SYNC;
                    end
                end

                SYNC: begin
                    if (bit_cnt < 7) begin
                        shift <= {shift[6:0], decoded_bit};
                        bit_cnt <= bit_cnt + 1;
                        one_count <= (decoded_bit == 1'b0) ? 3'd0 : one_count + 1;
                    end else begin
                        // Check for SYNC pattern: 00000001
                        if (shift == 8'b00000001) begin
                            state <= DATA;
                            bit_cnt <= 3'd0;
                            shift <= 8'd0;
                            one_count <= 3'd0;
                        end else begin
                            state <= IDLE; // Invalid SYNC, return to IDLE
                        end
                    end
                end

                DATA: begin
                    // Bitstuffing removal
                    if (one_count == 6 && decoded_bit == 1'b0) begin
                        one_count <= 3'd0; // Skip stuffed '0'
                    end else begin
                        // Update one_count
                        one_count <= (decoded_bit == 1'b0) ? 3'd0 : one_count + 1;

                        // Shift in decoded bit
                        shift <= {shift[6:0], decoded_bit};
                        bit_cnt <= bit_cnt + 1;

                        // Output byte when 8 bits are collected
                        if (bit_cnt == 7) begin
                            byte_out <= {shift[6:0], decoded_bit};
                            valid_out <= 1'b1;
                            bit_cnt <= 3'd0;
                        end
                    end

                    // Detect end of packet (simplified SE0: two consecutive '0's)
                    if (nrzi_in == 1'b0 && prev == 1'b0) begin
                        state <= IDLE;
                        bit_cnt <= 3'd0;
                        one_count <= 3'd0;
                        shift <= 8'd0;
                    end
                end

                default: begin
                    state <= IDLE;
                    bit_cnt <= 3'd0;
                    one_count <= 3'd0;
                    shift <= 8'd0;
                end
            endcase
        end
    end

endmodule