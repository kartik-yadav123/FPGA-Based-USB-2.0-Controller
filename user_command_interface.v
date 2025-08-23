module user_command_interface (
    input  wire        clk,
    input  wire        reset,
    input  wire        read_button,      // Active-high signal to trigger a read
    input  wire [31:0] lba_manual_in,    // Manual LBA input from switches
    input  wire [15:0] num_blocks_manual_in, // Manual block count input
    output reg         start_scsi_read_out,
    output wire [31:0] lba_out,
    output wire [15:0] num_blocks_out
);

    reg read_button_d1;
    reg read_button_d2;

    // Synchronize and debounce the input button
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            read_button_d1 <= 1'b0;
            read_button_d2 <= 1'b0;
            start_scsi_read_out <= 1'b0;
        end else begin
            read_button_d1 <= read_button;
            read_button_d2 <= read_button_d1;
            // Detect a rising edge on the button
            if (read_button_d1 && !read_button_d2) begin
                start_scsi_read_out <= 1'b1;
            end else begin
                start_scsi_read_out <= 1'b0;
            end
        end
    end

    assign lba_out = lba_manual_in;
    assign num_blocks_out = num_blocks_manual_in;

endmodule