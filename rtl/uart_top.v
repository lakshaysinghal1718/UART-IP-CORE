module uart_top #(
    parameter DATA_BITS   = 8,
    parameter STOP_BITS   = 1,
    parameter PARITY_TYPE = 0,
    parameter ADDR_WIDTH  = 4,
    parameter IBRD = 27,
    parameter FBRD = 8
)(
    input  wire clk,
    input  wire rst_n,
    
    input  wire tx_wr_en,
    input  wire [DATA_BITS-1:0] tx_data_in,
    output wire tx_fifo_full,
    output wire tx_fifo_empty,
    
    input  wire rx_rd_en,
    output wire [DATA_BITS-1:0] rx_data_out,
    output wire rx_fifo_full,
    output wire rx_fifo_empty,

    output wire tx_out,
    output wire overrun_err,
    input  wire rx_in,
    
    input wire cts_n,
    output reg rts_n
);

    wire baud_tick;
    wire sample_tick;

    wire [DATA_BITS-1:0] tx_fifo_dout;
    wire tx_busy;
    wire tx_done;

    wire [DATA_BITS-1:0] rx_uart_data;
    wire rx_valid;
    wire frame_err;
    wire parity_err;
    
    wire rx_almost_full;
    
    reg cts_sync1;
    reg cts_sync2;
    
    wire cts_active;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            cts_sync1 <= 1'b0;
            cts_sync2 <= 1'b0;
        end else begin 
            cts_sync1 <= ~cts_n;
            cts_sync2 <= cts_sync1;
        end
    end
    
    assign cts_active = cts_sync2; //just for readability
    
    always @(posedge clk) begin
        if (!rst_n) begin
            rts_n <= 1'b1; // NOT requesting for receiving
        end else begin
            rts_n <= rx_almost_full;
        end
    end            

    wire tx_start_internal = (!tx_fifo_empty) && (!tx_busy) && cts_active;
    wire tx_fifo_rd_en     = tx_start_internal;

    wire rx_fifo_wr_en = rx_valid;
    
    assign overrun_err = rx_valid && rx_fifo_full;

    // BAUD GENERATOR    
    baud_gen #(
        .IBRD(IBRD),
        .FBRD(FBRD)
    ) u_baud_gen (
        .clk         (clk),
        .rst_n       (rst_n),
        .baud_tick   (baud_tick),
        .sample_tick (sample_tick)
    );

    // TX FIFO
    fifo #(
        .DATA_WIDTH(DATA_BITS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_tx_fifo (
        .clk             (clk),
        .rst_n           (rst_n),
        .wr_en           (tx_wr_en),
        .rd_en           (tx_fifo_rd_en),
        .din             (tx_data_in),
        .full_threshold  ({ADDR_WIDTH+1{1'b1}}), // ignored for now, will be covered in phase 4
        .empty_threshold (0),                    // ignored for now, will be covered in phase 4
        .almost_full     (),
        .almost_empty    (),
        .dout            (tx_fifo_dout),
        .full            (tx_fifo_full),
        .empty           (tx_fifo_empty),
        .data_count      ()
    );

    // TX
    uart_tx #(
        .DATA_BITS(DATA_BITS),
        .STOP_BITS(STOP_BITS),
        .PARITY_TYPE(PARITY_TYPE)
    ) u_uart_tx (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_start   (tx_start_internal),
        .tx_data_in (tx_fifo_dout),
        .baud_tick  (baud_tick),
        .tx_out     (tx_out),
        .tx_busy    (tx_busy),
        .tx_done    (tx_done)
    );

    // RX
    uart_rx #(
        .DATA_BITS(DATA_BITS),
        .STOP_BITS(STOP_BITS),
        .PARITY_TYPE(PARITY_TYPE)
    ) u_uart_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .rx_in       (rx_in),
        .sample_tick (sample_tick),
        .rx_data     (rx_uart_data),
        .rx_valid    (rx_valid),
        .frame_err   (frame_err),
        .parity_err  (parity_err)
    );

    // RX FIFO
    fifo #(
        .DATA_WIDTH(DATA_BITS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_rx_fifo (
        .clk             (clk),
        .rst_n           (rst_n),
        .wr_en           (rx_fifo_wr_en),
        .rd_en           (rx_rd_en),
        .din             (rx_uart_data),
        .full_threshold  ((1<<ADDR_WIDTH)-2), 
        .empty_threshold (0),
        .almost_full     (rx_almost_full),
        .almost_empty    (),
        .dout            (rx_data_out),
        .full            (rx_fifo_full),
        .empty           (rx_fifo_empty),
        .data_count      ()
    );

endmodule