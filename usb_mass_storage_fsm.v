// Corrected USB Mass Storage FSM for robust hardware implementation
module usb_mass_storage_fsm (
    input wire clk,             // Clock input (60 MHz)
    input wire reset,           // Active-high reset
    // ULPI interface
    input wire [7:0] rx_data,   // Data from ULPI PHY
    input wire rx_valid,        // Data valid from ULPI PHY
    output reg [7:0] tx_data,   // Data to ULPI PHY
    output reg tx_valid,        // Data valid to ULPI PHY
    input wire tx_ready,        // ULPI PHY ready for data
    // SCSI interface
    input wire start_read,      // Signal to initiate SCSI read
    input wire start_write,     // Signal to initiate SCSI write
    input wire [7:0] cdb_0,     // SCSI CDB bytes
    input wire [7:0] cdb_1,
    input wire [7:0] cdb_2,
    input wire [7:0] cdb_3,
    input wire [7:0] cdb_4,
    input wire [7:0] cdb_5,
    input wire [7:0] cdb_6,
    input wire [7:0] cdb_7,
    input wire [7:0] cdb_8,
    input wire [7:0] cdb_9,
    input wire scsi_valid,      // Indicates valid CDB
    // Memory interface
    output reg [7:0] mem_data_out,  // Data to memory
    output reg mem_we,          // Memory write enable
    input wire [7:0] mem_data_in,   // Data from memory
    output reg done             // Operation complete
);
    
    // Internal registers
    reg [3:0] state;
    reg [8:0] index;
    reg [31:0] timeout_counter;
    reg [7:0] cbw[0:30];
    reg [4:0] cbw_index;
    reg [7:0] csw[0:12];
    reg [3:0] csw_index;
    reg is_read;
    reg [8:0] data_count;
    
    // State machine parameters
    localparam [3:0]
        IDLE = 4'd0,
        SEND_CBW = 4'd1,
        WAIT_ACK_AFTER_CBW = 4'd2,
        BULK_IN = 4'd3,
        BULK_OUT = 4'd4,
        WAIT_CSW = 4'd5,
        CHECK_CSW = 4'd6,
        FINISH = 4'd7,
        ERROR_STATE = 4'd8;

    // A single always block for all sequential logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            index <= 9'd0;
            timeout_counter <= 32'd0;
            cbw_index <= 5'd0;
            csw_index <= 4'd0;
            tx_valid <= 1'b0;
            mem_we <= 1'b0;
            done <= 1'b0;
            tx_data <= 8'd0;
            mem_data_out <= 8'd0;
            is_read <= 1'b0;
            data_count <= 9'd0;
        end else begin
            // Default assignments to prevent latches
            tx_valid <= 1'b0;
            mem_we <= 1'b0;
            done <= 1'b0;
            
            // Increment timeout counter every clock cycle
            timeout_counter <= timeout_counter + 1;
            
            // State machine logic
            case (state)
                IDLE: begin
                    if (scsi_valid && (start_read || start_write)) begin
                        is_read <= start_read;
                        // Prepare CBW (31 bytes)
                        cbw[0] <= 8'h55; // dCBWSignature: USBC
                        cbw[1] <= 8'h53;
                        cbw[2] <= 8'h42;
                        cbw[3] <= 8'h43;
                        cbw[4] <= 8'h12; // dCBWTag (arbitrary)
                        cbw[5] <= 8'h34;
                        cbw[6] <= 8'h56;
                        cbw[7] <= 8'h78;
                        cbw[8] <= 8'h00; // dCBWDataTransferLength: 512 bytes
                        cbw[9] <= 8'h02;
                        cbw[10] <= 8'h00;
                        cbw[11] <= 8'h00;
                        cbw[12] <= start_read ? 8'h80 : 8'h00; // bmCBWFlags: 0x80 for IN, 0x00 for OUT
                        cbw[13] <= 8'h00; // bCBWLUN
                        cbw[14] <= 8'd10; // bCBWCBLength: 10 bytes
                        cbw[15] <= cdb_0; // CDB
                        cbw[16] <= cdb_1;
                        cbw[17] <= cdb_2;
                        cbw[18] <= cdb_3;
                        cbw[19] <= cdb_4;
                        cbw[20] <= cdb_5;
                        cbw[21] <= cdb_6;
                        cbw[22] <= cdb_7;
                        cbw[23] <= cdb_8;
                        cbw[24] <= cdb_9;
                        
                        state <= SEND_CBW;
                        cbw_index <= 5'd0;
                        timeout_counter <= 32'd0;
                    end
                end
                
                SEND_CBW: begin
                    if (tx_ready) begin
                        if (cbw_index < 31) begin
                            tx_data <= cbw[cbw_index];
                            tx_valid <= 1'b1;
                            cbw_index <= cbw_index + 1;
                            state <= SEND_CBW;
                        end else begin
                            state <= WAIT_ACK_AFTER_CBW;
                            timeout_counter <= 32'd0;
                        end
                    end else begin
                        state <= SEND_CBW;
                    end
                end
                
                WAIT_ACK_AFTER_CBW: begin
                    if (rx_valid) begin
                        if (is_read) begin
                            state <= BULK_IN;
                            data_count <= 9'd0;
                        end else begin
                            state <= BULK_OUT;
                            data_count <= 9'd0;
                        end
                        timeout_counter <= 32'd0;
                    end else if (timeout_counter >= 32'd10000000) begin
                        state <= ERROR_STATE;
                    end else begin
                        state <= WAIT_ACK_AFTER_CBW;
                    end
                end
                
                BULK_IN: begin
                    if (rx_valid) begin
                        mem_data_out <= rx_data;
                        mem_we <= 1'b1;
                        data_count <= data_count + 1;
                        timeout_counter <= 32'd0;
                    end
                    if (data_count >= 512) begin
                        state <= WAIT_CSW;
                        csw_index <= 4'd0;
                        timeout_counter <= 32'd0;
                    end else if (timeout_counter >= 32'd10000000) begin
                        state <= ERROR_STATE;
                    end else begin
                        state <= BULK_IN;
                    end
                end
                
                BULK_OUT: begin
                    if (tx_ready) begin
                        if (data_count < 512) begin
                            tx_data <= mem_data_in;
                            tx_valid <= 1'b1;
                            data_count <= data_count + 1;
                            timeout_counter <= 32'd0;
                            state <= BULK_OUT;
                        end else begin
                            state <= WAIT_CSW;
                            csw_index <= 4'd0;
                            timeout_counter <= 32'd0;
                        end
                    end else if (timeout_counter >= 32'd10000000) begin
                        state <= ERROR_STATE;
                    end else begin
                        state <= BULK_OUT;
                    end
                end
                
                WAIT_CSW: begin
                    if (rx_valid) begin
                        csw[csw_index] <= rx_data;
                        csw_index <= csw_index + 1;
                        timeout_counter <= 32'd0;
                        if (csw_index >= 12) begin
                            state <= CHECK_CSW;
                        end
                    end else if (timeout_counter >= 32'd10000000) begin
                        state <= ERROR_STATE;
                    end else begin
                        state <= WAIT_CSW;
                    end
                end
                
                CHECK_CSW: begin
                    if (csw[0] == 8'h55 && csw[1] == 8'h53 && csw[2] == 8'h42 && csw[3] == 8'h53 && csw[12] == 8'h00) begin
                        state <= FINISH;
                    end else begin
                        state <= ERROR_STATE;
                    end
                end
                
                FINISH: begin
                    done <= 1'b1;
                    state <= IDLE;
                end
                
                ERROR_STATE: begin
                    done <= 1'b0;
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule