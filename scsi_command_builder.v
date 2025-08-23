module scsi_command_builder (
    input wire clk,
    input wire reset,
    input wire start_read,
    input wire start_write,
    input wire [31:0] lba,
    input wire [15:0] num_blocks,
    output reg [79:0] cdb,
    output reg valid
);
    
    reg [2:0] state;
    localparam [2:0] IDLE = 3'd0,
                     BUILD_READ10 = 3'd1,
                     BUILD_WRITE10 = 3'd2,
                     DONE = 3'd3;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            cdb <= 80'h0;
            valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    valid <= 1'b0;
                    if (start_read) begin
                        state <= BUILD_READ10;
                    end else if (start_write) begin
                        state <= BUILD_WRITE10;
                    end
                end
                
                BUILD_READ10: begin
                    cdb[79:72] <= 8'h28;
                    cdb[71:64] <= 8'h00;
                    cdb[63:32] <= lba;
                    cdb[31:24] <= 8'h00;
                    cdb[23:8]  <= num_blocks;
                    cdb[7:0]   <= 8'h00;
                    
                    state <= DONE;
                    valid <= 1'b1;
                end
                
                BUILD_WRITE10: begin
                    cdb[79:72] <= 8'h2A;
                    cdb[71:64] <= 8'h00;
                    cdb[63:32] <= lba;
                    cdb[31:24] <= 8'h00;
                    cdb[23:8]  <= num_blocks;
                    cdb[7:0]   <= 8'h00;
                    
                    state <= DONE;
                    valid <= 1'b1;
                end
                
                DONE: begin
                    if (!start_read && !start_write) begin
                        state <= IDLE;
                        valid <= 1'b0;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule