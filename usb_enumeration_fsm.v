// Corrected USB Enumeration FSM
// This module implements the USB enumeration sequence using a robust state machine
// designed for hardware. It works correctly with the updated usb_ulpi_interface.
module usb_enumeration_fsm (
    input wire clk,
    input wire reset,
    input wire start_enum,
    input wire [7:0] rx_data,
    input wire rx_valid,
    output reg [7:0] tx_data,
    output reg tx_valid,
    input wire tx_ready,
    output reg [1:0] enum_state,
    output reg enum_done
);
    
    // Internal state variables
    reg [3:0] state, next_state;
    reg [7:0] setup_packet [0:7];
    reg [2:0] packet_count;
    reg [6:0] device_address;
    reg [7:0] rx_buffer [0:255];
    reg [7:0] rx_count;
    reg [31:0] timeout_counter;
    
    // State machine parameters
    localparam [3:0] 
        IDLE = 4'd0,
        SEND_GET_DESCRIPTOR_SETUP = 4'd1,
        WAIT_GET_DESC_ACK = 4'd2,
        RECEIVE_GET_DESCRIPTOR_DATA = 4'd3,
        SEND_SET_ADDRESS_SETUP = 4'd4,
        WAIT_SET_ADDR_ACK = 4'd5,
        SEND_GET_CONFIG_SETUP = 4'd6,
        WAIT_GET_CONFIG_DATA = 4'd7,
        SEND_SET_CONFIG_SETUP = 4'd8,
        WAIT_SET_CONFIG_ACK = 4'd9,
        ENUM_COMPLETE = 4'd10,
        ENUM_ERROR = 4'd11;

    // A single always block for all sequential logic
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            packet_count <= 3'd0;
            rx_count <= 8'd0;
            device_address <= 7'd1;
            tx_valid <= 1'b0;
            enum_done <= 1'b0;
            enum_state <= 2'd0;
            timeout_counter <= 32'd0;
        end else begin
            state <= next_state;
            
            // Default assignments to prevent latches and simplify logic
            tx_valid <= 1'b0;
            enum_done <= 1'b0;
            
            case (state)
                IDLE: begin
                    enum_state <= 2'd0;
                    if (start_enum) begin
                        // Prepare GET_DESCRIPTOR setup packet
                        setup_packet[0] <= 8'h80; // bmRequestType (Device to Host)
                        setup_packet[1] <= 8'h06; // bRequest: GET_DESCRIPTOR
                        setup_packet[2] <= 8'h00; // wValue[7:0]
                        setup_packet[3] <= 8'h01; // wValue[15:8]: Device descriptor
                        setup_packet[4] <= 8'h00; // wIndex[7:0]
                        setup_packet[5] <= 8'h00; // wIndex[15:8]
                        setup_packet[6] <= 8'h12; // wLength[7:0]: 18 bytes
                        setup_packet[7] <= 8'h00; // wLength[15:8]
                        
                        next_state <= SEND_GET_DESCRIPTOR_SETUP;
                        packet_count <= 3'd0;
                    end else begin
                        next_state <= IDLE;
                    end
                end

                // State 1: Send GET_DESCRIPTOR
                SEND_GET_DESCRIPTOR_SETUP: begin
                    tx_data <= setup_packet[packet_count];
                    tx_valid <= tx_ready; // Only assert tx_valid if the interface is ready
                    
                    if (tx_ready) begin
                        if (packet_count < 8) begin
                            packet_count <= packet_count + 1;
                            next_state <= SEND_GET_DESCRIPTOR_SETUP;
                        end else begin
                            next_state <= WAIT_GET_DESC_ACK;
                            timeout_counter <= 32'd0;
                        end
                    end else begin
                        next_state <= SEND_GET_DESCRIPTOR_SETUP;
                    end
                end

                // State 2: Wait for ACK from PHY after sending setup packet
                WAIT_GET_DESC_ACK: begin
                    timeout_counter <= timeout_counter + 1;
                    if (rx_valid) begin // Await the first packet (ACK)
                        rx_count <= 8'd0;
                        next_state <= RECEIVE_GET_DESCRIPTOR_DATA;
                    end else if (timeout_counter >= 32'd10000000) begin // Timeout (approx 166ms @ 60MHz)
                        next_state <= ENUM_ERROR;
                    end else begin
                        next_state <= WAIT_GET_DESC_ACK;
                    end
                end
                
                // State 3: Receive descriptor data
                RECEIVE_GET_DESCRIPTOR_DATA: begin
                    if (rx_valid) begin
                        rx_buffer[rx_count] <= rx_data;
                        rx_count <= rx_count + 1;
                    end
                    if (rx_count >= 17) begin // Received all 18 bytes
                        next_state <= SEND_SET_ADDRESS_SETUP;
                        packet_count <= 3'd0;
                        // Prepare SET_ADDRESS setup packet
                        setup_packet[0] <= 8'h00; // bmRequestType (Host to Device)
                        setup_packet[1] <= 8'h05; // bRequest: SET_ADDRESS
                        setup_packet[2] <= device_address; // wValue[7:0]: New address
                        setup_packet[3] <= 8'h00; // wValue[15:8]
                        setup_packet[4] <= 8'h00; // wIndex[7:0]
                        setup_packet[5] <= 8'h00; // wIndex[15:8]
                        setup_packet[6] <= 8'h00; // wLength[7:0]
                        setup_packet[7] <= 8'h00; // wLength[15:8]
                    end else begin
                        next_state <= RECEIVE_GET_DESCRIPTOR_DATA;
                    end
                end
                
                // State 4: Send SET_ADDRESS
                SEND_SET_ADDRESS_SETUP: begin
                    tx_data <= setup_packet[packet_count];
                    tx_valid <= tx_ready;
                    if (tx_ready) begin
                        if (packet_count < 8) begin
                            packet_count <= packet_count + 1;
                            next_state <= SEND_SET_ADDRESS_SETUP;
                        end else begin
                            next_state <= WAIT_SET_ADDR_ACK;
                            timeout_counter <= 32'd0;
                        end
                    end else begin
                        next_state <= SEND_SET_ADDRESS_SETUP;
                    end
                end

                // State 5: Wait for ACK after setting address
                WAIT_SET_ADDR_ACK: begin
                    timeout_counter <= timeout_counter + 1;
                    if (rx_valid) begin
                        next_state <= SEND_GET_CONFIG_SETUP;
                        packet_count <= 3'd0;
                        rx_count <= 8'd0;
                        // Prepare GET_CONFIGURATION setup packet
                        setup_packet[0] <= 8'h80; // bmRequestType
                        setup_packet[1] <= 8'h06; // bRequest: GET_DESCRIPTOR
                        setup_packet[2] <= 8'h00; // wValue[7:0]
                        setup_packet[3] <= 8'h02; // wValue[15:8]: Configuration descriptor
                        setup_packet[4] <= 8'h00; // wIndex[7:0]
                        setup_packet[5] <= 8'h00; // wIndex[15:8]
                        setup_packet[6] <= 8'h09; // wLength[7:0]: 9 bytes minimum
                        setup_packet[7] <= 8'h00; // wLength[15:8]
                    end else if (timeout_counter >= 32'd10000000) begin
                        next_state <= ENUM_ERROR;
                    end else begin
                        next_state <= WAIT_SET_ADDR_ACK;
                    end
                end
                
                // State 6: Send GET_CONFIG
                SEND_GET_CONFIG_SETUP: begin
                    tx_data <= setup_packet[packet_count];
                    tx_valid <= tx_ready;
                    if (tx_ready) begin
                        if (packet_count < 8) begin
                            packet_count <= packet_count + 1;
                            next_state <= SEND_GET_CONFIG_SETUP;
                        end else begin
                            next_state <= WAIT_GET_CONFIG_DATA;
                            timeout_counter <= 32'd0;
                        end
                    end else begin
                        next_state <= SEND_GET_CONFIG_SETUP;
                    end
                end
                
                // State 7: Wait for configuration data
                WAIT_GET_CONFIG_DATA: begin
                    timeout_counter <= timeout_counter + 1;
                    if (rx_valid) begin
                        rx_buffer[rx_count] <= rx_data;
                        rx_count <= rx_count + 1;
                    end
                    if (rx_count >= 8) begin // Received 9 bytes (index 0 to 8)
                        next_state <= SEND_SET_CONFIG_SETUP;
                        packet_count <= 3'd0;
                        // Prepare SET_CONFIGURATION setup packet
                        setup_packet[0] <= 8'h00; // bmRequestType
                        setup_packet[1] <= 8'h09; // bRequest: SET_CONFIGURATION
                        setup_packet[2] <= 8'h01; // wValue[7:0]: Configuration value
                        setup_packet[3] <= 8'h00; // wValue[15:8]
                        setup_packet[4] <= 8'h00; // wIndex[7:0]
                        setup_packet[5] <= 8'h00; // wIndex[15:8]
                        setup_packet[6] <= 8'h00; // wLength[7:0]
                        setup_packet[7] <= 8'h00; // wLength[15:8]
                    end else if (timeout_counter >= 32'd10000000) begin
                        next_state <= ENUM_ERROR;
                    end else begin
                        next_state <= WAIT_GET_CONFIG_DATA;
                    end
                end
                
                // State 8: Send SET_CONFIG
                SEND_SET_CONFIG_SETUP: begin
                    tx_data <= setup_packet[packet_count];
                    tx_valid <= tx_ready;
                    if (tx_ready) begin
                        if (packet_count < 8) begin
                            packet_count <= packet_count + 1;
                            next_state <= SEND_SET_CONFIG_SETUP;
                        end else begin
                            next_state <= WAIT_SET_CONFIG_ACK;
                            timeout_counter <= 32'd0;
                        end
                    end else begin
                        next_state <= SEND_SET_CONFIG_SETUP;
                    end
                end
                
                // State 9: Wait for ACK after setting config
                WAIT_SET_CONFIG_ACK: begin
                    timeout_counter <= timeout_counter + 1;
                    if (rx_valid) begin
                        next_state <= ENUM_COMPLETE;
                    end else if (timeout_counter >= 32'd10000000) begin
                        next_state <= ENUM_ERROR;
                    end else begin
                        next_state <= WAIT_SET_CONFIG_ACK;
                    end
                end
                
                ENUM_COMPLETE: begin
                    enum_done <= 1'b1;
                    enum_state <= 2'd3;
                    next_state <= ENUM_COMPLETE;
                end
                
                ENUM_ERROR: begin
                    enum_done <= 1'b1;
                    enum_state <= 2'd3; // Or another state for error
                    next_state <= IDLE; // Restart on error
                end
                
                default: next_state <= IDLE;
            endcase
        end
    end
endmodule