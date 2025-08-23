module usb_token_generator (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [3:0] token_pid,
    input wire [6:0] device_addr,
    input wire [3:0] endpoint_addr,
    output reg [7:0] token_out,
    output reg token_valid,
    output reg token_done
);
    
    reg [2:0] state;
    reg [1:0] byte_count;
    reg [10:0] addr_endp;
    reg [4:0] crc5;
    
    localparam [2:0] IDLE = 3'd0,
                    SEND_PID = 3'd1,
                    SEND_ADDR = 3'd2,
                    DONE = 3'd3;
    
    // Simple CRC5 calculation function
    function [4:0] calc_crc5;
        input [10:0] data;
        reg [4:0] crc;
        integer i;
        begin
            crc = 5'h1F;
            for (i = 0; i < 11; i = i + 1) begin
                if (crc[4] ^ data[i])
                    crc = {crc[3:0], 1'b0} ^ 5'h05;
                else
                    crc = {crc[3:0], 1'b0};
            end
            calc_crc5 = ~crc;
        end
    endfunction
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            token_valid <= 1'b0;
            token_done <= 1'b0;
            byte_count <= 2'd0;
            token_out <= 8'h00;
            addr_endp <= 11'h0;
            crc5 <= 5'h0;
        end else begin
            case (state)
                IDLE: begin
                    token_done <= 1'b0;
                    token_valid <= 1'b0;
                    if (start) begin
                        addr_endp <= {endpoint_addr, device_addr};
                        crc5 <= calc_crc5({endpoint_addr, device_addr});
                        state <= SEND_PID;
                        byte_count <= 2'd0;
                    end
                end
                
                SEND_PID: begin
                    token_out <= {~token_pid, token_pid};
                    token_valid <= 1'b1;
                    state <= SEND_ADDR;
                end
                
                SEND_ADDR: begin
                    case (byte_count)
                        2'd0: begin
                            token_out <= addr_endp[7:0];
                            token_valid <= 1'b1;
                            byte_count <= 2'd1;
                        end
                        2'd1: begin
                            token_out <= {crc5, addr_endp[10:8]};
                            token_valid <= 1'b1;
                            state <= DONE;
                        end
                        default: state <= DONE;
                    endcase
                end
                
                DONE: begin
                    token_valid <= 1'b0;
                    token_done <= 1'b1;
                    if (!start) begin
                        state <= IDLE;
                        token_done <= 1'b0;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule
