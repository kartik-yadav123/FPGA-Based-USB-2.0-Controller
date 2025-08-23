module usb_packet_builder (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [3:0] pid,
    input wire [7:0] data_in,
    input wire data_valid,
    input wire data_last,
    output reg [7:0] packet_out,
    output reg packet_valid,
    output reg packet_done
);
    
    reg [2:0] state;
    reg [7:0] data_buffer [0:63];  // Max 64 bytes data
    reg [5:0] data_count;
    reg [15:0] crc16;
    reg [4:0] crc5;
    
    localparam [2:0] IDLE = 3'd0,
                    COLLECT_DATA = 3'd1,
                    SEND_PID = 3'd2,
                    SEND_DATA = 3'd3,
                    SEND_CRC = 3'd4,
                    DONE = 3'd5;
    
    integer i;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            packet_valid <= 1'b0;
            packet_done <= 1'b0;
            data_count <= 6'd0;
            packet_out <= 8'h00;
            crc16 <= 16'hFFFF;
            crc5 <= 5'h1F;
            
            for (i = 0; i < 64; i = i + 1) begin
                data_buffer[i] <= 8'h00;
            end
        end else begin
            case (state)
                IDLE: begin
                    packet_done <= 1'b0;
                    packet_valid <= 1'b0;
                    data_count <= 6'd0;
                    if (start) begin
                        state <= COLLECT_DATA;
                    end
                end
                
                COLLECT_DATA: begin
                    if (data_valid && data_count < 64) begin
                        data_buffer[data_count] <= data_in;
                        data_count <= data_count + 1;
                        
                        if (data_last) begin
                            state <= SEND_PID;
                        end
                    end
                end
                
                SEND_PID: begin
                    packet_out <= {~pid, pid};  // PID with complement
                    packet_valid <= 1'b1;
                    state <= SEND_DATA;
                    data_count <= 6'd0;
                end
                
                SEND_DATA: begin
                    if (data_count < data_count) begin  // Send collected data
                        packet_out <= data_buffer[data_count];
                        packet_valid <= 1'b1;
                        data_count <= data_count + 1;
                    end else begin
                        state <= SEND_CRC;
                    end
                end
                
                SEND_CRC: begin
                    // Send CRC16 for data packets (simplified)
                    packet_out <= crc16[7:0];
                    packet_valid <= 1'b1;
                    state <= DONE;
                end
                
                DONE: begin
                    packet_valid <= 1'b0;
                    packet_done <= 1'b1;
                    if (!start) begin
                        state <= IDLE;
                        packet_done <= 1'b0;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule
