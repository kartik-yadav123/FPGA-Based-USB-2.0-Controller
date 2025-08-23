module usb_pid_decoder (
    input wire [7:0] pid_byte,
    output reg [3:0] pid,
    output reg valid
);
    always @(*) begin
        if ((pid_byte[7:4] ^ pid_byte[3:0]) == 4'hF) begin
            pid = pid_byte[3:0];
            valid = 1;
        end else begin
            pid = 4'h0;
            valid = 0;
        end
    end
endmodule

// usb_pid_encoder module (no changes needed - already correct)
module usb_pid_encoder (
    input wire [3:0] pid,
    output reg [7:0] pid_byte
);
    always @(*) begin
        pid_byte[3:0] = pid;
        pid_byte[7:4] = ~pid;
    end
endmodule