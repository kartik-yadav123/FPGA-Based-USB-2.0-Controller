module usb_bulk_transport_wrapper (
    input wire clk,
    input wire reset,
    input wire start_transfer,
    input wire direction,  // 1 for read, 0 for write
    input wire [7:0] data_in,
    output reg [7:0] data_out,
    output reg data_valid,
    output reg done,
    input wire [255:0] cbw  // Command Block Wrapper (31 bytes + padding)
);
    
    reg [3:0] state;
    reg [7:0] byte_count;
    reg [7:0] transfer_count;
    reg [7:0] cbw_bytes [0:30];  // 31 bytes for CBW
    reg [7:0] csw_bytes [0:12];  // 13 bytes for CSW
    
    localparam [3:0] IDLE = 4'd0,
                    SEND_CBW = 4'd1,
                    DATA_PHASE_READ = 4'd2,
                    DATA_PHASE_WRITE = 4'd3,
                    RECEIVE_CSW = 4'd4,
                    DONE_STATE = 4'd5;
    
    integer i;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            data_valid <= 1'b0;
            done <= 1'b0;
            byte_count <= 8'd0;
            transfer_count <= 8'd0;
            data_out <= 8'h00;
            
            // Initialize CBW array
            for (i = 0; i < 31; i = i + 1) begin
                cbw_bytes[i] <= 8'h00;
            end
            
            // Initialize CSW array
            for (i = 0; i < 13; i = i + 1) begin
                csw_bytes[i] <= 8'h00;
            end
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    data_valid <= 1'b0;
                    if (start_transfer) begin
                        // Extract CBW bytes from packed input
                        for (i = 0; i < 31; i = i + 1) begin
                            cbw_bytes[i] <= cbw[(i*8) +: 8];
                        end
                        byte_count <= 8'd0;
                        transfer_count <= 8'd0;
                        state <= SEND_CBW;
                    end
                end
                
                SEND_CBW: begin
                    if (byte_count < 31) begin
                        data_out <= cbw_bytes[byte_count];
                        data_valid <= 1'b1;
                        byte_count <= byte_count + 1;
                    end else begin
                        data_valid <= 1'b0;
                        byte_count <= 8'd0;
                        if (direction) begin
                            state <= DATA_PHASE_READ;
                        end else begin
                            state <= DATA_PHASE_WRITE;
                        end
                    end
                end
                
                DATA_PHASE_READ: begin
                    // Read operation - forward received data
                    data_out <= data_in;
                    data_valid <= 1'b1;
                    
                    transfer_count <= transfer_count + 1;
                    if (transfer_count >= 8'd255) begin  // Example transfer size
                        state <= RECEIVE_CSW;
                        data_valid <= 1'b0;
                    end
                end
                
                DATA_PHASE_WRITE: begin
                    // Write operation - send data (placeholder data for now)
                    data_out <= 8'hAA;  // Test pattern
                    data_valid <= 1'b1;
                    
                    transfer_count <= transfer_count + 1;
                    if (transfer_count >= 8'd255) begin  // Example transfer size
                        state <= RECEIVE_CSW;
                        data_valid <= 1'b0;
                    end
                end
                
                RECEIVE_CSW: begin
                    // Receive Command Status Wrapper
                    if (byte_count < 13) begin
                        csw_bytes[byte_count] <= data_in;
                        byte_count <= byte_count + 1;
                    end else begin
                        state <= DONE_STATE;
                    end
                end
                
                DONE_STATE: begin
                    done <= 1'b1;
                    if (!start_transfer) begin
                        state <= IDLE;
                        done <= 1'b0;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule