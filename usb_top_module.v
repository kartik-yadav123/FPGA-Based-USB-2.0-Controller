module usb_top_module(
    input  wire        clk_50MHz,    
    input  wire        reset_n,      
    
    // ULPI interface (essential for USB)
    inout  wire [7:0]  ulpi_data,    
    input  wire        ulpi_dir,     
    input  wire        ulpi_nxt,     
    output wire        ulpi_stp,     
    output reg         ulpi_reset,   
    output wire        ulpi_clk_out, 
    
    // Simple control inputs
    input  wire        start_read,   
    input  wire        start_write,  
    
    // UART interface for file operations
    input  wire        uart_rx,      
    output wire        uart_tx,      
    
    // Simple status outputs
    output reg         operation_busy,
    output reg         operation_done,
    output reg         error          
);
    // Clock and reset signals
    wire               clk_ulpi;     // 60 MHz ULPI clock
    wire               rst;          // Active-high reset
    
    // USB interface signals
    wire [7:0]         ulpi_rx_data; 
    wire               ulpi_rx_valid;
    
    // PID decoder
    wire [3:0]         pid_type;     
    wire               pid_valid;    
    
    // Enumeration FSM
    wire [7:0]         enum_tx_data; 
    wire               enum_tx_valid;
    wire               enum_tx_ready;
    wire [1:0]         enum_state;   
    wire               enum_done;    
    
    // Token Generator
    reg [3:0]          token_type_reg;
    reg                token_start;  
    wire [7:0]         token_out;    
    wire               token_valid;  
    wire               token_done;   
    
    // Descriptor Parser
    wire               desc_parse_done;
    wire [3:0]         endpoint_address;
    wire [10:0]        max_packet_size;
    wire               interface_mass_storage_found;
    
    // SCSI Command Builder
    wire [31:0]        lba_in;       
    wire [15:0]        num_blocks_in;
    wire [79:0]        cdb_out;      
    wire               start_scsi_read_wire;
    wire               start_scsi_write_wire;
    wire               scsi_valid;   
    
    // Mass Storage Transport
    wire               bulk_transport_done;
    wire [7:0]         bulk_tx_data; 
    wire               bulk_tx_valid;
    wire               bulk_tx_ready;
    wire [7:0]         mem_data_out; 
    wire               mem_we;       
    wire [7:0]         mem_data_in;  
    wire [9:0]         mem_addr;     // Added missing memory address signal
    
    // File operation control
    reg                file_operation_mode;
    reg                start_file_transfer;
    reg [31:0]         file_size_bytes;
    reg [31:0]         file_bytes_remaining;
    
    // UART interface signals
    wire               uart_tx_busy;
    wire               uart_rx_ready;
    wire [7:0]         uart_rx_data;
    reg                uart_tx_start;
    reg [7:0]          uart_tx_data;
    
    // Memory buffers - dual buffer system
    reg [7:0]          file_buffer_a [0:511];
    reg [7:0]          file_buffer_b [0:511];
    reg                active_buffer;
    reg [9:0]          buffer_write_addr;
    reg [9:0]          buffer_read_addr;
    reg                buffer_ready;
    reg                buffer_data_valid;
    
    // Internal counters
    reg [15:0]         bytes_transferred;
    reg [15:0]         blocks_completed;
    
    // Memory address management - Fixed for mass storage FSM
    reg [9:0]          mem_addr_reg;      // For USB write operations (pendrive to FPGA)
    reg [9:0]          mem_read_addr;     // For USB read operations (FPGA to pendrive)
    
    // Fixed parameters
    localparam [15:0]  DEFAULT_NUM_BLOCKS = 16'd1;
    localparam [31:0]  DEFAULT_LBA = 32'h00000000;
    
    // File operation states
    localparam [3:0]
        FILE_IDLE           = 4'd0,
        FILE_WAIT_SIZE      = 4'd1,
        FILE_RECEIVE_DATA   = 4'd2,
        FILE_PREPARE_WRITE  = 4'd3,
        FILE_SEND_DATA      = 4'd4,
        FILE_COMPLETE       = 4'd5;
    
    reg [3:0] file_state;
    
    // Main USB operation states
    localparam [4:0]
        S_IDLE                     = 5'd0,
        S_ENUM_INIT                = 5'd1,
        S_ENUM_DONE                = 5'd2,
        S_DESC_PARSE               = 5'd3,
        S_MSC_INIT                 = 5'd4,
        S_WAIT_FILE_DATA           = 5'd5,
        S_READ_CMD_BUILD           = 5'd6,
        S_GENERATE_CBW_TOKEN       = 5'd7,
        S_SEND_CBW                 = 5'd8,
        S_GENERATE_DATA_TOKEN      = 5'd9,
        S_TRANSFER_DATA            = 5'd10,
        S_GENERATE_CSW_TOKEN       = 5'd11,
        S_RECEIVE_CSW              = 5'd12,
        S_WRITE_CMD_BUILD          = 5'd13,
        S_PREPARE_WRITE_DATA       = 5'd14,
        S_GENERATE_WRITE_CBW_TOKEN = 5'd15,
        S_SEND_WRITE_CBW           = 5'd16,
        S_GENERATE_WRITE_DATA_TOKEN= 5'd17,
        S_SEND_WRITE_DATA          = 5'd18,
        S_GENERATE_WRITE_CSW_TOKEN = 5'd19,
        S_RECEIVE_WRITE_CSW        = 5'd20,
        S_SEND_FILE_DATA           = 5'd21,
        S_OPERATION_COMPLETE       = 5'd22;
    
    reg [4:0] main_state;
    reg       start_enum;
    reg       start_descriptor_parser;
    reg       start_scsi_read_reg;
    reg       start_scsi_write_reg;
    
    // Derived signals
    wire [7:0]         device_class;
    wire [3:0]         bulk_in_ep_addr;
    wire [3:0]         bulk_out_ep_addr;
    wire [10:0]        bulk_in_max_packet;
    wire [10:0]        bulk_out_max_packet;
    
    assign device_class = interface_mass_storage_found ? 8'h08 : 8'h00;
    assign bulk_in_ep_addr = endpoint_address;
    assign bulk_out_ep_addr = endpoint_address + 4'd1;
    assign bulk_in_max_packet = max_packet_size;
    assign bulk_out_max_packet = max_packet_size;
    
    // Clock and reset logic
    assign rst = ~reset_n;
    
    // PLL to generate 60 MHz ULPI clock from 50 MHz input
    pll_50_to_60 pll (
        .inclk0(clk_50MHz),
        .c0(clk_ulpi)
    );
    
    assign ulpi_clk_out = clk_ulpi;
    
    // ULPI reset: active high for 10 us after power-on
    reg [9:0] reset_counter;
    always @(posedge clk_ulpi or posedge rst) begin
        if (rst) begin
            reset_counter <= 10'd0;
            ulpi_reset <= 1'b1;
        end else if (reset_counter < 10'd600) begin // 10 us at 60 MHz
            reset_counter <= reset_counter + 1;
            ulpi_reset <= 1'b1;
        end else begin
            ulpi_reset <= 1'b0;
        end
    end
    
    // Button edge detection
    reg start_read_prev, start_write_prev;
    wire start_read_edge, start_write_edge;
    
    always @(posedge clk_ulpi) begin
        start_read_prev <= start_read;
        start_write_prev <= start_write;
    end
    
    assign start_read_edge = start_read && !start_read_prev;
    assign start_write_edge = start_write && !start_write_prev;
    
    // UART Interface
    // Instantiating the provided uart_core module
    uart_core #(.CLK_FREQ(60000000), .BAUD(115200)) uart_inst (
        .clk(clk_ulpi),
        .reset(rst),
        .rx(uart_rx),
        .tx(uart_tx),
        .tx_data(uart_tx_data),
        .tx_start(uart_tx_start),
        .tx_busy(uart_tx_busy),
        .rx_data(uart_rx_data),
        .rx_ready(uart_rx_ready)
    );
    
    // File Operation State Machine
    always @(posedge clk_ulpi or posedge rst) begin
        if (rst) begin
            file_state <= FILE_IDLE;
            file_size_bytes <= 32'd0;
            file_bytes_remaining <= 32'd0;
            buffer_write_addr <= 10'd0;
            buffer_read_addr <= 10'd0;
            buffer_ready <= 1'b0;
            buffer_data_valid <= 1'b0;
            active_buffer <= 1'b0;
            uart_tx_start <= 1'b0;
            uart_tx_data <= 8'd0;
        end else begin
            uart_tx_start <= 1'b0; // Default
            
            case (file_state)
                FILE_IDLE: begin
                    buffer_ready <= 1'b0;
                    buffer_data_valid <= 1'b0;
                    
                    if (start_file_transfer) begin
                        if (file_operation_mode == 1'b1) begin
                            // Write mode: wait for file size from PC
                            file_state <= FILE_WAIT_SIZE;
                        end else begin
                            // Read mode: prepare to send data to PC
                            file_bytes_remaining <= DEFAULT_NUM_BLOCKS * 32'd512;
                            buffer_read_addr <= 10'd0;
                            // buffer_data_valid will be set by the USB transfer logic
                            file_state <= FILE_SEND_DATA;
                        end
                    end
                end
                
                FILE_WAIT_SIZE: begin
                    if (uart_rx_ready) begin
                        // Receive number of blocks (simplified protocol)
                        file_size_bytes <= {24'd0, uart_rx_data} * 32'd512;
                        file_bytes_remaining <= {24'd0, uart_rx_data} * 32'd512;
                        buffer_write_addr <= 10'd0;
                        file_state <= FILE_RECEIVE_DATA;
                    end
                end
                
                FILE_RECEIVE_DATA: begin
                    if (uart_rx_ready && file_bytes_remaining > 0) begin
                        // Store received byte in active buffer
                        if (active_buffer == 1'b0) begin
                            file_buffer_a[buffer_write_addr] <= uart_rx_data;
                        end else begin
                            file_buffer_b[buffer_write_addr] <= uart_rx_data;
                        end
                        
                        buffer_write_addr <= buffer_write_addr + 1;
                        file_bytes_remaining <= file_bytes_remaining - 1;
                        
                        // Check if buffer is full (512 bytes) or file complete
                        if (buffer_write_addr == 10'd511 || file_bytes_remaining == 1) begin
                            buffer_ready <= 1'b1;
                            // Set buffer_data_valid for the USB write to pick up
                            buffer_data_valid <= 1'b1;
                            file_state <= FILE_PREPARE_WRITE;
                        end
                    end
                end
                
                FILE_PREPARE_WRITE: begin
                    // This state waits for the main USB FSM to handle the write
                    // The main FSM will transition back to S_WAIT_FILE_DATA, which
                    // will cause this FSM to transition back to FILE_RECEIVE_DATA
                    // if more data is expected.
                    if (file_bytes_remaining > 0) begin
                        // Data from USB transfer is consumed, prepare to receive next buffer
                        if (main_state == S_WAIT_FILE_DATA) begin
                            active_buffer <= ~active_buffer;
                            buffer_write_addr <= 10'd0;
                            buffer_ready <= 1'b0;
                            buffer_data_valid <= 1'b0;
                            file_state <= FILE_RECEIVE_DATA;
                        end
                    end else begin
                        file_state <= FILE_COMPLETE;
                    end
                end
                
                FILE_SEND_DATA: begin
                    if (!uart_tx_busy && buffer_data_valid && buffer_read_addr < 10'd512 && file_bytes_remaining > 0) begin
                        // Send byte from active buffer to PC
                        if (active_buffer == 1'b0) begin
                            uart_tx_data <= file_buffer_a[buffer_read_addr];
                        end else begin
                            uart_tx_data <= file_buffer_b[buffer_read_addr];
                        end
                        
                        uart_tx_start <= 1'b1;
                        buffer_read_addr <= buffer_read_addr + 1;
                        file_bytes_remaining <= file_bytes_remaining - 1;
                        
                        // Check if buffer is empty or file complete
                        if (buffer_read_addr == 10'd511 || file_bytes_remaining == 1) begin
                            if (file_bytes_remaining > 1) begin
                                // Wait for USB to fill next buffer
                                buffer_data_valid <= 1'b0;
                                active_buffer <= ~active_buffer;
                                buffer_read_addr <= 10'd0;
                            end else begin
                                file_state <= FILE_COMPLETE;
                            end
                        end
                    end
                end
                
                FILE_COMPLETE: begin
                    buffer_ready <= 1'b0;
                    buffer_data_valid <= 1'b0;
                    file_state <= FILE_IDLE;
                end
                
                default: file_state <= FILE_IDLE;
            endcase
        end
    end
    
    // Main USB Operation State Machine
    always @(posedge clk_ulpi or posedge rst) begin
        if (rst) begin
            main_state <= S_IDLE;
            start_enum <= 1'b0;
            start_descriptor_parser <= 1'b0;
            start_scsi_read_reg <= 1'b0;
            start_scsi_write_reg <= 1'b0;
            file_operation_mode <= 1'b0;
            start_file_transfer <= 1'b0;
            operation_busy <= 1'b0;
            operation_done <= 1'b0;
            error <= 1'b0;
            bytes_transferred <= 16'd0;
            blocks_completed <= 16'd0;
            token_start <= 1'b0;
            token_type_reg <= 4'h0;
            // Note: mem_addr_reg and mem_read_addr managed by separate always blocks
        end else begin
            // Default assignments
            start_enum <= 1'b0;
            start_descriptor_parser <= 1'b0;
            start_file_transfer <= 1'b0;
            token_start <= 1'b0;
            
            case (main_state)
                S_IDLE: begin
                    operation_done <= 1'b0;
                    operation_busy <= 1'b0;
                    error <= 1'b0;
                    bytes_transferred <= 16'd0;
                    blocks_completed <= 16'd0;
                    if (start_read_edge) begin
                        // Read from pendrive, save to file
                        file_operation_mode <= 1'b0;
                        operation_busy <= 1'b1;
                        start_enum <= 1'b1;
                        main_state <= S_ENUM_INIT;
                    end else if (start_write_edge) begin
                        // Read from file, write to pendrive
                        file_operation_mode <= 1'b1;
                        operation_busy <= 1'b1;
                        start_enum <= 1'b1;
                        main_state <= S_ENUM_INIT;
                    end
                end
                
                S_ENUM_INIT: begin
                    if (enum_done) begin
                        start_enum <= 1'b0;
                        start_descriptor_parser <= 1'b1;
                        main_state <= S_DESC_PARSE;
                    end
                end
                
                S_DESC_PARSE: begin
                    if (desc_parse_done) begin
                        start_descriptor_parser <= 1'b0;
                        main_state <= S_MSC_INIT;
                    end
                end
                
                S_MSC_INIT: begin
                    if (device_class == 8'h08 && interface_mass_storage_found) begin
                        start_file_transfer <= 1'b1;
                        if (file_operation_mode == 1'b1) begin
                            // Write operation: wait for file data
                            main_state <= S_WAIT_FILE_DATA;
                        end else begin
                            // Read operation: start reading from pendrive
                            start_scsi_read_reg <= 1'b1;
                            main_state <= S_READ_CMD_BUILD;
                        end
                    end else begin
                        error <= 1'b1;
                        main_state <= S_OPERATION_COMPLETE;
                    end
                end
                
                S_WAIT_FILE_DATA: begin
                    if (file_operation_mode == 1'b1 && buffer_ready) begin
                        start_scsi_write_reg <= 1'b1;
                        main_state <= S_WRITE_CMD_BUILD;
                    end else if (file_operation_mode == 1'b0 && buffer_data_valid) begin
                        main_state <= S_SEND_FILE_DATA;
                    end
                end
                
                // Read operation states
                S_READ_CMD_BUILD: begin
                    if (scsi_valid) begin
                        start_scsi_read_reg <= 1'b0;
                        main_state <= S_GENERATE_CBW_TOKEN;
                    end
                end
                
                S_GENERATE_CBW_TOKEN: begin
                    token_start <= 1'b1;
                    token_type_reg <= 4'h1; // OUT PID
                    if (token_done) begin
                        main_state <= S_SEND_CBW;
                    end
                end
                
                S_SEND_CBW: begin
                    if (bulk_transport_done) begin
                        main_state <= S_GENERATE_DATA_TOKEN;
                    end
                end
                
                S_GENERATE_DATA_TOKEN: begin
                    token_start <= 1'b1;
                    token_type_reg <= 4'h9; // IN PID
                    if (token_done) begin
                        main_state <= S_TRANSFER_DATA;
                    end
                end
                
                S_TRANSFER_DATA: begin
                    if (bulk_transport_done) begin
                        bytes_transferred <= bytes_transferred + 16'd512;
                        blocks_completed <= 16'd1; // Assuming single block transfer
                        main_state <= S_GENERATE_CSW_TOKEN;
                    end
                end
                
                S_GENERATE_CSW_TOKEN: begin
                    token_start <= 1'b1;
                    token_type_reg <= 4'h9; // IN PID
                    if (token_done) begin
                        main_state <= S_RECEIVE_CSW;
                    end
                end
                
                S_RECEIVE_CSW: begin
                    if (bulk_transport_done) begin
                        if (file_bytes_remaining > 0) begin
                            main_state <= S_WAIT_FILE_DATA;
                        end else begin
                            main_state <= S_OPERATION_COMPLETE;
                        end
                    end
                end
                
                S_SEND_FILE_DATA: begin
                    if (file_state == FILE_COMPLETE) begin
                        main_state <= S_OPERATION_COMPLETE;
                    end
                end
                
                // Write operation states
                S_WRITE_CMD_BUILD: begin
                    if (scsi_valid) begin
                        start_scsi_write_reg <= 1'b0;
                        main_state <= S_PREPARE_WRITE_DATA;
                    end
                end
                
                S_PREPARE_WRITE_DATA: begin
                    if (buffer_ready) begin
                        main_state <= S_GENERATE_WRITE_CBW_TOKEN;
                    end
                end
                
                S_GENERATE_WRITE_CBW_TOKEN: begin
                    token_start <= 1'b1;
                    token_type_reg <= 4'h1; // OUT PID
                    if (token_done) begin
                        main_state <= S_SEND_WRITE_CBW;
                    end
                end
                
                S_SEND_WRITE_CBW: begin
                    if (bulk_transport_done) begin
                        main_state <= S_GENERATE_WRITE_DATA_TOKEN;
                    end
                end
                
                S_GENERATE_WRITE_DATA_TOKEN: begin
                    token_start <= 1'b1;
                    token_type_reg <= 4'h1; // OUT PID
                    if (token_done) begin
                        main_state <= S_SEND_WRITE_DATA;
                    end
                end
                
                S_SEND_WRITE_DATA: begin
                    if (bulk_transport_done) begin
                        bytes_transferred <= bytes_transferred + 16'd512;
                        blocks_completed <= blocks_completed + 1;
                        main_state <= S_GENERATE_WRITE_CSW_TOKEN;
                    end
                end
                
                S_GENERATE_WRITE_CSW_TOKEN: begin
                    token_start <= 1'b1;
                    token_type_reg <= 4'h9; // IN PID
                    if (token_done) begin
                        main_state <= S_RECEIVE_WRITE_CSW;
                    end
                end
                
                S_RECEIVE_WRITE_CSW: begin
                    if (bulk_transport_done) begin
                        // Check if more data to write
                        if (file_bytes_remaining > 0) begin
                            main_state <= S_WAIT_FILE_DATA;
                        end else begin
                            main_state <= S_OPERATION_COMPLETE;
                        end
                    end
                end
                
                S_OPERATION_COMPLETE: begin
                    operation_done <= 1'b1;
                    operation_busy <= 1'b0;
                    main_state <= S_IDLE;
                end
                
                default: main_state <= S_IDLE;
            endcase
        end
    end
    
    // Output multiplexer for TX data
    reg [7:0]  tx_data_mux;
    reg        tx_valid_mux;
    wire       tx_ready_mux;
    always @(*) begin
        case (main_state)
            S_ENUM_INIT: begin
                tx_data_mux = token_valid ? token_out : enum_tx_data;
                tx_valid_mux = token_valid || enum_tx_valid;
            end
            S_SEND_CBW, S_TRANSFER_DATA, S_RECEIVE_CSW,
            S_SEND_WRITE_CBW, S_SEND_WRITE_DATA, S_RECEIVE_WRITE_CSW: begin
                tx_data_mux = token_valid ? token_out : bulk_tx_data;
                tx_valid_mux = token_valid || bulk_tx_valid;
            end
            default: begin
                tx_data_mux = 8'h00;
                tx_valid_mux = 1'b0;
            end
        endcase
    end
    
    assign enum_tx_ready = tx_ready_mux;
    assign bulk_tx_ready = tx_ready_mux;
    
    // Memory interface for USB bulk transport - Fixed to avoid multiple drivers
    always @(posedge clk_ulpi or posedge rst) begin
        if (rst) begin
            mem_addr_reg <= 10'd0;
        end else if (mem_we && mem_addr_reg < 10'd512) begin
            // Write received data to active buffer
            if (active_buffer == 1'b0) begin
                file_buffer_a[mem_addr_reg] <= mem_data_out;
            end else begin
                file_buffer_b[mem_addr_reg] <= mem_data_out;
            end
            mem_addr_reg <= mem_addr_reg + 1;
        end else if (main_state == S_READ_CMD_BUILD || main_state == S_WRITE_CMD_BUILD) begin
            mem_addr_reg <= 10'd0; // Reset address at start of new operation
        end
    end
    
    // Memory data output (for writing to pendrive) - separate read address management
    always @(posedge clk_ulpi or posedge rst) begin
        if (rst) begin
            mem_read_addr <= 10'd0;
        end else if (main_state == S_READ_CMD_BUILD || main_state == S_WRITE_CMD_BUILD) begin
            mem_read_addr <= 10'd0;
        end else if ((main_state == S_SEND_WRITE_DATA) && bulk_tx_valid && bulk_tx_ready && mem_read_addr < 10'd512) begin
            mem_read_addr <= mem_read_addr + 1;
        end
    end
    
    assign mem_data_in = (active_buffer == 1'b0) ? file_buffer_a[mem_read_addr] : file_buffer_b[mem_read_addr];
    
    // Fixed LBA and block count assignments
    assign lba_in = DEFAULT_LBA;
    assign num_blocks_in = DEFAULT_NUM_BLOCKS;
    assign start_scsi_read_wire = start_scsi_read_reg;
    assign start_scsi_write_wire = start_scsi_write_reg;
    
    // Module instantiations
    
    // ULPI Interface
    usb_ulpi_interface ulpi_if (
        .clk_60MHz(clk_ulpi),
        .reset(rst),
        .ulpi_data(ulpi_data),
        .ulpi_dir(ulpi_dir),
        .ulpi_nxt(ulpi_nxt),
        .ulpi_stp(ulpi_stp),
        .rx_data(ulpi_rx_data),
        .rx_valid(ulpi_rx_valid),
        .tx_data(tx_data_mux),
        .tx_valid(tx_valid_mux),
        .tx_ready(tx_ready_mux)
    );
    
    usb_pid_decoder pid_decoder (
        .pid_byte(ulpi_rx_data),
        .pid(pid_type),
        .valid(pid_valid)
    );
    
    // USB Enumeration FSM
    usb_enumeration_fsm enum_fsm (
        .clk(clk_ulpi),
        .reset(rst),
        .start_enum(start_enum),
        .rx_data(ulpi_rx_data),
        .rx_valid(ulpi_rx_valid),
        .tx_data(enum_tx_data),
        .tx_valid(enum_tx_valid),
        .tx_ready(enum_tx_ready),
        .enum_state(enum_state),
        .enum_done(enum_done)
    );
    
    // USB Token Generator
    usb_token_generator token_gen (
        .clk(clk_ulpi),
        .reset(rst),
        .start(token_start),
        .token_pid(token_type_reg),
        .device_addr(7'd1),
        .endpoint_addr((token_type_reg == 4'h1) ? bulk_out_ep_addr : bulk_in_ep_addr),
        .token_out(token_out),
        .token_valid(token_valid),
        .token_done(token_done)
    );
    
    // Descriptor Parser
    usb_descriptor_parser desc_parser (
        .clk(clk_ulpi),
        .rst(rst),
        .start(start_descriptor_parser),
        .data_in(ulpi_rx_data),
        .data_valid(ulpi_rx_valid),
        .done(desc_parse_done),
        .endpoint_address(endpoint_address),
        .max_packet_size(max_packet_size),
        .interface_mass_storage_found(interface_mass_storage_found)
    );
    
    // SCSI Command Builder
    scsi_command_builder scsi_builder (
        .clk(clk_ulpi),
        .reset(rst),
        .start_read(start_scsi_read_reg),
        .start_write(start_scsi_write_reg),
        .lba(lba_in),
        .num_blocks(num_blocks_in),
        .cdb(cdb_out),
        .valid(scsi_valid)
    );
    
    // Mass Storage Bulk Transport FSM
    usb_mass_storage_fsm bulk_transport (
        .clk(clk_ulpi),
        .reset(rst),
        .rx_data(ulpi_rx_data),
        .rx_valid(ulpi_rx_valid),
        .tx_data(bulk_tx_data),
        .tx_valid(bulk_tx_valid),
        .tx_ready(bulk_tx_ready),
        .start_read(start_scsi_read_wire),
        .start_write(start_scsi_write_wire),
        .cdb_0(cdb_out[7:0]),
        .cdb_1(cdb_out[15:8]),
        .cdb_2(cdb_out[23:16]),
        .cdb_3(cdb_out[31:24]),
        .cdb_4(cdb_out[39:32]),
        .cdb_5(cdb_out[47:40]),
        .cdb_6(cdb_out[55:48]),
        .cdb_7(cdb_out[63:56]),
        .cdb_8(cdb_out[71:64]),
        .cdb_9(cdb_out[79:72]),
        .scsi_valid(scsi_valid),
        .mem_data_out(mem_data_out),
        .mem_we(mem_we),
        .mem_data_in(mem_data_in),
        .done(bulk_transport_done)
    );
    
endmodule

// Placeholder PLL module for simulation (replace with Intel FPGA PLL IP for synthesis)
module pll_50_to_60 (
    input wire inclk0,    // 50 MHz input clock
    output reg c0         // 60 MHz output clock
);
    // WARNING: This is a simulation-only placeholder. Use Intel FPGA PLL IP for synthesis.
    reg [31:0] counter;
    initial begin
        counter = 0;
        c0 = 0;
    end
    
    always @(posedge inclk0) begin
        counter <= counter + 1;
        // Approximate 60 MHz from 50 MHz (5/6 ratio)
        if (counter >= 5) begin
            c0 <= ~c0;
            counter <= counter - 5;
        end
    end
endmodule
