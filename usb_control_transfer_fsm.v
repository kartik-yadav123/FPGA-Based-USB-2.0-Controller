// usb_control_transfer_fsm.v
// Updated with proper handshaking and state management for USB enumeration
module usb_control_transfer_fsm (
    input wire clk,               // Clock input (assumed 60 MHz for ULPI)
    input wire reset,             // Active-high reset
    output reg [63:0] setup_packet, // 8-byte SETUP packet
    output reg send_setup,        // Signal to initiate SETUP transaction
    input wire setup_done,        // Input indicating SETUP transaction completion
    output reg [1:0] enum_state   // Enumeration state output
);
    localparam [2:0] IDLE = 3'd0,
                     SEND_GET_DESC = 3'd1,
                     WAIT_GET_DESC = 3'd2,
                     SEND_SET_ADDR = 3'd3,
                     WAIT_SET_ADDR = 3'd4,
                     SEND_SET_CONFIG = 3'd5,
                     WAIT_SET_CONFIG = 3'd6,
                     ENUM_DONE = 3'd7;
    
    reg [2:0] state;
    reg [7:0] timeout_counter;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            enum_state <= 2'd0;
            send_setup <= 1'b0;
            setup_packet <= 64'h0;
            timeout_counter <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    enum_state <= 2'd0;
                    timeout_counter <= 8'd0;
                    // Build GET_DESCRIPTOR SETUP packet
                    setup_packet[7:0]   <= 8'h80; // bmRequestType: Device-to-Host, Standard, Device
                    setup_packet[15:8]  <= 8'h06; // bRequest: GET_DESCRIPTOR
                    setup_packet[23:16] <= 8'h00; // wValue[7:0]: Descriptor index
                    setup_packet[31:24] <= 8'h01; // wValue[15:8]: Device descriptor
                    setup_packet[39:32] <= 8'h00; // wIndex[7:0]: Interface index
                    setup_packet[47:40] <= 8'h00; // wIndex[15:8]
                    setup_packet[55:48] <= 8'h12; // wLength[7:0]: 18 bytes for Device Descriptor
                    setup_packet[63:56] <= 8'h00; // wLength[15:8]
                    
                    send_setup <= 1'b1;
                    state <= SEND_GET_DESC;
                end
                
                SEND_GET_DESC: begin
                    if (setup_done) begin
                        send_setup <= 1'b0;
                        state <= WAIT_GET_DESC;
                        timeout_counter <= 8'd0;
                    end else begin
                        timeout_counter <= timeout_counter + 1;
                        if (timeout_counter == 8'hFF) begin
                            state <= IDLE; // Retry on timeout
                        end
                    end
                end
                
                WAIT_GET_DESC: begin
                    timeout_counter <= timeout_counter + 1;
                    if (timeout_counter > 8'd100) begin // Wait for descriptor response
                        // Build SET_ADDRESS SETUP packet
                        setup_packet[7:0]   <= 8'h00; // bmRequestType: Host-to-Device, Standard, Device
                        setup_packet[15:8]  <= 8'h05; // bRequest: SET_ADDRESS
                        setup_packet[23:16] <= 8'h01; // wValue[7:0]: New address (e.g., 1)
                        setup_packet[31:24] <= 8'h00; // wValue[15:8]
                        setup_packet[39:32] <= 8'h00; // wIndex[7:0]
                        setup_packet[47:40] <= 8'h00; // wIndex[15:8]
                        setup_packet[55:48] <= 8'h00; // wLength[7:0]: No data phase
                        setup_packet[63:56] <= 8'h00; // wLength[15:8]
                        
                        send_setup <= 1'b1;
                        enum_state <= 2'd1;
                        state <= SEND_SET_ADDR;
                    end else if (timeout_counter == 8'hFF) begin
                        state <= IDLE; // Retry on timeout
                    end
                end
                
                SEND_SET_ADDR: begin
                    if (setup_done) begin
                        send_setup <= 1'b0;
                        state <= WAIT_SET_ADDR;
                        timeout_counter <= 8'd0;
                    end else begin
                        timeout_counter <= timeout_counter + 1;
                        if (timeout_counter == 8'hFF) begin
                            state <= IDLE; // Retry on timeout
                        end
                    end
                end
                
                WAIT_SET_ADDR: begin
                    timeout_counter <= timeout_counter + 1;
                    if (timeout_counter > 8'd100) begin // Wait for address assignment
                        // Build SET_CONFIGURATION SETUP packet
                        setup_packet[7:0]   <= 8'h00; // bmRequestType: Host-to-Device, Standard, Device
                        setup_packet[15:8]  <= 8'h09; // bRequest: SET_CONFIGURATION
                        setup_packet[23:16] <= 8'h01; // wValue[7:0]: Configuration value (e.g., 1)
                        setup_packet[31:24] <= 8'h00; // wValue[15:8]
                        setup_packet[39:32] <= 8'h00; // wIndex[7:0]
                        setup_packet[47:40] <= 8'h00; // wIndex[15:8]
                        setup_packet[55:48] <= 8'h00; // wLength[7:0]: No data phase
                        setup_packet[63:56] <= 8'h00; // wLength[15:8]
                        
                        send_setup <= 1'b1;
                        enum_state <= 2'd2;
                        state <= SEND_SET_CONFIG;
                    end else if (timeout_counter == 8'hFF) begin
                        state <= IDLE; // Retry on timeout
                    end
                end
                
                SEND_SET_CONFIG: begin
                    if (setup_done) begin
                        send_setup <= 1'b0;
                        state <= WAIT_SET_CONFIG;
                        timeout_counter <= 8'd0;
                    end else begin
                        timeout_counter <= timeout_counter + 1;
                        if (timeout_counter == 8'hFF) begin
                            state <= IDLE; // Retry on timeout
                        end
                    end
                end
                
                WAIT_SET_CONFIG: begin
                    timeout_counter <= timeout_counter + 1;
                    if (timeout_counter > 8'd100) begin // Wait for configuration
                        enum_state <= 2'd3; // Enumeration complete
                        state <= ENUM_DONE;
                    end else if (timeout_counter == 8'hFF) begin
                        state <= IDLE; // Retry on timeout
                    end
                end
                
                ENUM_DONE: begin
                    // Stay in ENUM_DONE until reset
                    enum_state <= 2'd3;
                    send_setup <= 1'b0;
                    timeout_counter <= 8'd0;
                end
                
                default: begin
                    state <= IDLE;
                    enum_state <= 2'd0;
                    send_setup <= 1'b0;
                end
            endcase
        end
    end

endmodule