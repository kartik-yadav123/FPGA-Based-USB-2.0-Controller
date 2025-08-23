module uart_core #(
    parameter CLK_FREQ = 50000000,   // system clock frequency
    parameter BAUD     = 115200      // baud rate
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    output wire       tx,

    // RX Interface
    output reg        rx_ready,
    output reg [7:0]  rx_data,

    // TX Interface
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_busy
);

    localparam BAUD_TICK = CLK_FREQ / BAUD;

    // ==========================
    // TX (Transmitter)
    // ==========================
    reg [15:0] tx_clk_cnt = 0;
    reg [3:0]  tx_bit_cnt = 0;
    reg [9:0]  tx_shift   = 10'b1111111111; // idle = 1
    reg        tx_reg     = 1'b1;
    assign tx = tx_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_clk_cnt <= 0;
            tx_bit_cnt <= 0;
            tx_shift   <= 10'b1111111111;
            tx_reg     <= 1'b1;
            tx_busy    <= 1'b0;
        end else begin
            if (tx_start && !tx_busy) begin
                // Frame: start(0) + 8 data bits + stop(1)
                tx_shift <= {1'b1, tx_data, 1'b0};
                tx_bit_cnt <= 0;
                tx_clk_cnt <= 0;
                tx_busy <= 1'b1;
            end else if (tx_busy) begin
                if (tx_clk_cnt < BAUD_TICK - 1) begin
                    tx_clk_cnt <= tx_clk_cnt + 1;
                end else begin
                    tx_clk_cnt <= 0;
                    tx_reg <= tx_shift[0];
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    tx_bit_cnt <= tx_bit_cnt + 1;

                    if (tx_bit_cnt == 9) begin
                        tx_busy <= 1'b0;
                    end
                end
            end
        end
    end

    // ==========================
    // RX (Receiver)
    // ==========================
    reg [15:0] rx_clk_cnt = 0;
    reg [3:0]  rx_bit_cnt = 0;
    reg [7:0]  rx_shift   = 0;
    reg        rx_busy    = 0;
    reg        rx_sync1, rx_sync2;

    // Synchronize RX input
    always @(posedge clk) begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_ready   <= 0;
            rx_data    <= 0;
            rx_clk_cnt <= 0;
            rx_bit_cnt <= 0;
            rx_busy    <= 0;
        end else begin
            rx_ready <= 0;

            if (!rx_busy) begin
                if (!rx_sync2) begin // detect start bit
                    rx_busy <= 1;
                    rx_clk_cnt <= BAUD_TICK/2; // sample in middle
                    rx_bit_cnt <= 0;
                end
            end else begin
                if (rx_clk_cnt < BAUD_TICK - 1) begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end else begin
                    rx_clk_cnt <= 0;
                    rx_bit_cnt <= rx_bit_cnt + 1;

                    if (rx_bit_cnt >= 1 && rx_bit_cnt <= 8) begin
                        rx_shift <= {rx_sync2, rx_shift[7:1]};
                    end else if (rx_bit_cnt == 9) begin
                        rx_busy <= 0;
                        rx_data <= rx_shift;
                        rx_ready <= 1;
                    end
                end
            end
        end
    end
endmodule
