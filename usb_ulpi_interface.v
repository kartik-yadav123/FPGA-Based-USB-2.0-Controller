
module usb_ulpi_interface (
    input          clk_60MHz, // 60 MHz system clock
    input          reset,     // Changed from 'rst' to 'reset'
    inout  [7:0]   ulpi_data, // ULPI 8-bit data bus
    input          ulpi_dir,  // ULPI direction (PHY -> LINK)
    input          ulpi_nxt,  // ULPI next indicator
    output         ulpi_stp,  // ULPI stop signal
    input  [7:0]   tx_data,   // Data to transmit
    input          tx_valid,  // Transmit request
    output         tx_ready,  // Transmit ready
    output [7:0]   rx_data,   // Received data
    output         rx_valid   // Receive valid
);

    // =========================================================
    // FSM State Encoding
    // =========================================================
    localparam ST_IDLE = 2'b00;
    localparam ST_TX   = 2'b01;
    localparam ST_RX   = 2'b10;

    // Internal state and output registers
    reg [1:0] state_reg, next_state_reg;
    reg        ulpi_stp_reg;
    reg        tx_ready_reg;
    reg        rx_valid_reg;
    reg [7:0]  rx_data_reg;
    reg [7:0]  ulpi_dout_reg;
    reg        ulpi_oe_reg;

    // Assign outputs from internal registers
    assign ulpi_stp = ulpi_stp_reg;
    assign tx_ready = tx_ready_reg;
    assign rx_valid = rx_valid_reg;
    assign rx_data = rx_data_reg;

    // Tristate buffer for the ULPI data bus
    assign ulpi_data = (ulpi_oe_reg) ? ulpi_dout_reg : 8'bz;

    // =========================================================
    // FSM Sequential Logic
    // =========================================================
    always @(posedge clk_60MHz or posedge reset) begin
        if (reset) begin // Changed from 'rst' to 'reset'
            state_reg      <= ST_IDLE;
            ulpi_stp_reg   <= 1'b0;
            tx_ready_reg   <= 1'b0;
            rx_valid_reg   <= 1'b0;
            ulpi_oe_reg    <= 1'b0;
            ulpi_dout_reg  <= 8'b0;
            rx_data_reg    <= 8'b0;
        end else begin
            // Default assignments to prevent latches
            ulpi_stp_reg   <= 1'b0;
            tx_ready_reg   <= 1'b0;
            rx_valid_reg   <= 1'b0;
            ulpi_oe_reg    <= 1'b0;

            case (state_reg)
                ST_IDLE: begin
                    if (ulpi_dir) begin
                        next_state_reg <= ST_RX;
                    end else if (tx_valid) begin
                        next_state_reg <= ST_TX;
                    end else begin
                        next_state_reg <= ST_IDLE;
                    end
                end

                ST_TX: begin
                    ulpi_oe_reg    <= 1'b1;
                    ulpi_dout_reg  <= tx_data;
                    ulpi_stp_reg   <= 1'b1;
                    tx_ready_reg   <= 1'b1;
                    if (ulpi_nxt) begin
                        next_state_reg <= ST_IDLE;
                    end else begin
                        next_state_reg <= ST_TX;
                    end
                end

                ST_RX: begin
                    ulpi_stp_reg   <= 1'b1;
                    rx_data_reg    <= ulpi_data;
                    rx_valid_reg   <= 1'b1;
                    if (!ulpi_dir) begin
                        next_state_reg <= ST_IDLE;
                    end else begin
                        next_state_reg <= ST_RX;
                    end
                end

                default: begin
                    next_state_reg <= ST_IDLE;
                end
            endcase
            state_reg <= next_state_reg;
        end
    end
endmodule