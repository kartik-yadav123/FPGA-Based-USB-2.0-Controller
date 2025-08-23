module usb_descriptor_parser (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] data_in,
    input wire data_valid,
    output reg done,
    output reg [3:0] endpoint_address,
    output reg [10:0] max_packet_size,
    output reg interface_mass_storage_found
);

    // Descriptor Types
    localparam DEVICE_DESCRIPTOR        = 8'h01;
    localparam CONFIGURATION_DESCRIPTOR = 8'h02;
    localparam INTERFACE_DESCRIPTOR     = 8'h04;
    localparam ENDPOINT_DESCRIPTOR      = 8'h05;

    // FSM States
    localparam [3:0] IDLE           = 4'd0,
                    PARSE_HEADER   = 4'd1,
                    PARSE_TYPE     = 4'd2,
                    DEVICE_DESC    = 4'd3,
                    CONFIG_DESC    = 4'd4,
                    INTERFACE_DESC = 4'd5,
                    ENDPOINT_DESC  = 4'd6,
                    DONE_STATE     = 4'd7;

    reg [3:0] state;
    reg [7:0] desc_length;
    reg [7:0] desc_type;
    reg [7:0] byte_count;
    reg [7:0] buffer[0:31];

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            byte_count <= 8'd0;
            done <= 1'b0;
            endpoint_address <= 4'd0;
            max_packet_size <= 11'd0;
            interface_mass_storage_found <= 1'b0;
            desc_length <= 8'd0;
            desc_type <= 8'd0;
            
            // Initialize buffer
            for (i = 0; i < 32; i = i + 1) begin
                buffer[i] <= 8'h00;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= PARSE_HEADER;
                        byte_count <= 8'd0;
                        done <= 1'b0;
                        interface_mass_storage_found <= 1'b0;
                    end
                end

                PARSE_HEADER: begin
                    if (data_valid) begin
                        buffer[0] <= data_in;
                        desc_length <= data_in;
                        byte_count <= 8'd1;
                        state <= PARSE_TYPE;
                    end
                end

                PARSE_TYPE: begin
                    if (data_valid) begin
                        buffer[1] <= data_in;
                        desc_type <= data_in;
                        byte_count <= 8'd2;

                        case (data_in)
                            DEVICE_DESCRIPTOR: state <= DEVICE_DESC;
                            CONFIGURATION_DESCRIPTOR: state <= CONFIG_DESC;
                            INTERFACE_DESCRIPTOR: state <= INTERFACE_DESC;
                            ENDPOINT_DESCRIPTOR: state <= ENDPOINT_DESC;
                            default: state <= PARSE_HEADER;
                        endcase
                    end
                end

                DEVICE_DESC, CONFIG_DESC, INTERFACE_DESC, ENDPOINT_DESC: begin
                    if (data_valid && byte_count < 32) begin
                        buffer[byte_count] <= data_in;
                        byte_count <= byte_count + 1;

                        if (byte_count == desc_length - 1) begin
                            case (state)
                                INTERFACE_DESC: begin
                                    // Class = 08 -> Mass Storage
                                    if (byte_count >= 5 && buffer[5] == 8'h08) begin
                                        interface_mass_storage_found <= 1'b1;
                                    end
                                    state <= PARSE_HEADER;
                                end

                                ENDPOINT_DESC: begin
                                    if (byte_count >= 5) begin
                                        endpoint_address <= buffer[2][3:0];
                                        max_packet_size <= {buffer[5], buffer[4]};
                                    end
                                    state <= DONE_STATE;
                                    done <= 1'b1;
                                end

                                default: begin
                                    state <= PARSE_HEADER;
                                end
                            endcase
                        end
                    end
                end

                DONE_STATE: begin
                    if (!start) begin
                        state <= IDLE;
                        done <= 1'b0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule