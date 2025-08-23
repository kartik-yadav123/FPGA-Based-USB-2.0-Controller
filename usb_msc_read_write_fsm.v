module usb_msc_read_write_fsm (
    input wire clk,              // Clock input (assumed 60 MHz for ULPI)
    input wire reset,            // Active-high reset
    input wire direction,        // 1 for read, 0 for write
    input wire start,            // Start signal to initiate operation
    input wire [7:0] data_in,    // Input data from ULPI
    input wire data_valid,       // Data valid signal from ULPI
    input wire ulpi_nxt,         // ULPI next signal (indicates PHY ready for data)
    output reg [7:0] data_out,   // Output data to ULPI
    output reg write_en,         // Write enable for ULPI
    output reg done              // Indicates operation completion
);

    reg [3:0] state;
    reg [8:0] index;             // 9-bit index for 512-byte buffer
    reg [7:0] mem [0:511];       // 512-byte buffer for one USB MSC block
    reg [7:0] timeout_counter;   // Timeout counter for response wait
    reg [7:0] cbw [0:30];        // Command Block Wrapper (31 bytes)
    reg [4:0] cbw_index;         // Index for sending CBW bytes

    localparam [3:0]
        IDLE = 4'd0,
        SEND_CBW = 4'd1,         // Send Command Block Wrapper
        WAIT_RESP = 4'd2,        // Wait for device response (data or CSW)
        READ_DATA = 4'd3,        // Read data from device
        WRITE_DATA = 4'd4,       // Write data to device
        WAIT_CSW = 4'd5,         // Wait for Command Status Wrapper
        CHECK_CSW = 4'd6,        // Check CSW status
        FINISH = 4'd7;           // Operation complete

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            index <= 9'd0;
            timeout_counter <= 8'd0;
            cbw_index <= 5'd0;
            write_en <= 1'b0;
            data_out <= 8'd0;
            done <= 1'b0;
            
            // Initialize CBW with proper structure
            cbw[0]  <= 8'h55; cbw[1]  <= 8'h53; cbw[2]  <= 8'h42; cbw[3]  <= 8'h43; // Signature
            cbw[4]  <= 8'h12; cbw[5]  <= 8'h34; cbw[6]  <= 8'h56; cbw[7]  <= 8'h78; // Tag
            cbw[8]  <= 8'h00; cbw[9]  <= 8'h02; cbw[10] <= 8'h00; cbw[11] <= 8'h00; // Transfer length (512)
            cbw[12] <= 8'h80; // Flags (0x80 for IN, 0x00 for OUT)
            cbw[13] <= 8'h00; // LUN
            cbw[14] <= 8'h0A; // CDB Length (10)
            // CDB will be filled based on direction
            cbw[15] <= 8'h00; cbw[16] <= 8'h00; cbw[17] <= 8'h00; cbw[18] <= 8'h00; cbw[19] <= 8'h00;
            cbw[20] <= 8'h00; cbw[21] <= 8'h00; cbw[22] <= 8'h00; cbw[23] <= 8'h00; cbw[24] <= 8'h00;
            cbw[25] <= 8'h00; cbw[26] <= 8'h00; cbw[27] <= 8'h00; cbw[28] <= 8'h00; cbw[29] <= 8'h00; cbw[30] <= 8'h00;
            
            // Initialize memory
            begin
                integer i;
                for (i = 0; i < 512; i = i + 1) begin
                    mem[i] <= 8'd0;
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    index <= 9'd0;
                    timeout_counter <= 8'd0;
                    write_en <= 1'b0;
                    done <= 1'b0;
                    cbw_index <= 5'd0;
                    if (start) begin
                        // Configure CBW based on direction
                        cbw[12] <= direction ? 8'h80 : 8'h00; // Direction flag
                        cbw[15] <= direction ? 8'h28 : 8'h2A; // SCSI command (READ(10) or WRITE(10))
                        // LBA and block count would be set here in real implementation
                        state <= SEND_CBW;
                    end
                end

                SEND_CBW: begin
                    if (ulpi_nxt && cbw_index < 31) begin
                        data_out <= cbw[cbw_index];
                        write_en <= 1'b1;
                        cbw_index <= cbw_index + 1;
                    end else if (cbw_index >= 31) begin
                        write_en <= 1'b0;
                        state <= WAIT_RESP;
                        timeout_counter <= 8'd0;
                    end else begin
                        write_en <= 1'b0;
                    end
                end

                WAIT_RESP: begin
                    timeout_counter <= timeout_counter + 1;
                    if (data_valid) begin
                        state <= direction ? READ_DATA : WRITE_DATA;
                        timeout_counter <= 8'd0;
                        index <= 9'd0;
                    end else if (timeout_counter == 8'hFF) begin
                        state <= IDLE; // Timeout, retry
                        done <= 1'b0;
                    end
                end

                READ_DATA: begin
                    if (data_valid && index < 512) begin
                        mem[index] <= data_in;
                        index <= index + 1;
                    end else if (index >= 512) begin
                        state <= WAIT_CSW;
                        index <= 9'd0;
                    end
                end

                WRITE_DATA: begin
                    if (ulpi_nxt && index < 512) begin
                        data_out <= mem[index];
                        write_en <= 1'b1;
                        index <= index + 1;
                    end else begin
                        write_en <= 1'b0;
                        if (index >= 512) begin
                            state <= WAIT_CSW;
                            index <= 9'd0;
                        end
                    end
                end

                WAIT_CSW: begin
                    timeout_counter <= timeout_counter + 1;
                    if (data_valid) begin
                        // Store CSW (simplified, assumes 13-byte CSW)
                        mem[index] <= data_in;
                        index <= index + 1;
                        if (index >= 12) begin
                            state <= CHECK_CSW;
                            index <= 9'd0;
                        end
                    end else if (timeout_counter == 8'hFF) begin
                        state <= IDLE; // Timeout, retry
                        done <= 1'b0;
                    end
                end

                CHECK_CSW: begin
                    // Simplified CSW check: assume mem[0:3] is signature, mem[12] is status
                    if (mem[0] == 8'h55 && mem[1] == 8'h53 && mem[2] == 8'h42 && mem[3] == 8'h53 && mem[12] == 8'h00) begin
                        // CSW valid, status OK
                        state <= FINISH;
                    end else begin
                        // CSW invalid or failed, retry
                        state <= IDLE;
                        done <= 1'b0;
                    end
                end

                FINISH: begin
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    write_en <= 1'b0;
                    done <= 1'b0;
                end
            endcase
        end
    end

endmodule
