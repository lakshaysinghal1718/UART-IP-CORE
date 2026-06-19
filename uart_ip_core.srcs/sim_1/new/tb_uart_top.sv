`timescale 1ns/1ps
module tb_uart_top;
    parameter DATA_BITS   = 8;
    parameter PARITY_TYPE = 0;
    parameter STOP_BITS   = 1;
    parameter ADDR_WIDTH  = 4; 
    parameter FIFO_DEPTH  = 1 << ADDR_WIDTH;
    
    integer error_count = 0;
    reg [DATA_BITS-1:0]read_val;
    reg [DATA_BITS-1:0] tx_stall_data [0:FIFO_DEPTH-1];
    reg [DATA_BITS-1:0] rx_stall_data [0:FIFO_DEPTH-1];
    
    
    reg clk;
    reg rst_n;
    
    reg tx_wr_en;
    reg [DATA_BITS-1:0]tx_data_in;
    wire tx_fifo_full;
    wire tx_fifo_empty;
    
    reg rx_rd_en;
    wire [DATA_BITS-1:0]rx_data_out;
    wire rx_fifo_full;
    wire rx_fifo_empty;
    
    wire serial_loop;
    wire overrun_err;
    
    uart_top #(
        .DATA_BITS(DATA_BITS),
        .STOP_BITS(STOP_BITS),
        .PARITY_TYPE(PARITY_TYPE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .tx_wr_en(tx_wr_en),
        .tx_data_in(tx_data_in),
        .tx_fifo_full(tx_fifo_full),
        .tx_fifo_empty(tx_fifo_empty),
        
        .rx_rd_en(rx_rd_en),
        .rx_data_out(rx_data_out),
        .rx_fifo_full(rx_fifo_full),
        .rx_fifo_empty(rx_fifo_empty),
        
        .tx_out(serial_loop),
        .rx_in(serial_loop),
        .overrun_err(overrun_err)
    );
    
    initial clk = 0;
    always #10 clk = ~clk;
    
    task cpu_write_tx(input [DATA_BITS-1:0] data);
        begin
            while (tx_fifo_full) begin
                @(posedge clk);
            end
            @(posedge clk);
            tx_wr_en <= 1'b1;
            tx_data_in <= data;
            
            @(posedge clk);
            tx_wr_en <= 1'b0;
            tx_data_in <= 8'h00;
            #1;
        end
    endtask
    
    task cpu_read_rx(output [DATA_BITS-1:0] data);
        begin
            @(posedge clk);
            if(!rx_fifo_empty) begin
                rx_rd_en <= 1'b1;
                data = rx_data_out;
            end else begin
                $display("ERROR: RX FIFO IS EMPTY! Cannot read. Time: %0t", $time);
                error_count = error_count + 1;
            end
            @(posedge clk);
            rx_rd_en <= 1'b0;
            #1;
        end
    endtask
    
    integer i;
    
    initial begin
        rst_n = 0;
        tx_wr_en = 0;
        rx_rd_en = 0;
        tx_data_in = 0;
        
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        repeat(5) @(posedge clk);
        
        $display("\n=== STARTING PHASE 2 BURST TEST ===");
        
        $display("-> CPU Burst Writing to TX FIFO...");
        tx_stall_data[0] = 8'h48; // 'H'
        tx_stall_data[1] = 8'h45; // 'E'
        tx_stall_data[2] = 8'h4C; // 'L'
        tx_stall_data[3] = 8'h4C; // 'L'
        tx_stall_data[4] = 8'h4F; // 'O'
        
        for (i = 0; i < 5; i = i + 1) begin
            cpu_write_tx(tx_stall_data[i]);
        end
        
        fork
            begin : test1_wait
                wait(u_dut.u_rx_fifo.data_count == 5);
            end
            begin : test1_timeout
                repeat(60000) @(posedge clk); 
                $display("[FATAL] Test 1 timed out waiting for RX count!");
                $finish;
            end
        join_any
        disable fork;
        
        i=0;
        while (!rx_fifo_empty) begin
            cpu_read_rx(read_val);
            if (read_val === tx_stall_data[i]) begin
                $display("Popped from RX FIFO: %c (Hex: %h)", read_val, read_val);
            end else begin
                $display("[MISMATCH] Expected: %h, Got: %h", tx_stall_data[i], read_val);
                error_count = error_count + 1;
            end
            i = i + 1;
        end
        
        $display("--- TEST 2: RX OVERRUN ---");
        
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            rx_stall_data[i] = $random & 8'hFF; //Masking as $random creates a 32 bit signed integer and we want only 8 bits.
        end

        for(i = 0; i < FIFO_DEPTH; i = i + 1) begin
            cpu_write_tx(rx_stall_data[i]);
        end
        
        fork
            begin : test2_fill_wait
                wait(u_dut.u_rx_fifo.full == 1'b1);
            end
            begin : test2_fill_timeout
                repeat(200000) @(posedge clk);
                $display("[FATAL] Test 2 timed out waiting for RX FIFO saturation!");
                $finish;
            end
        join_any
        disable fork;
        
        $display("Firing 17th byte...");    
        cpu_write_tx(8'hFF);
        
        fork
            begin : pulse_catch
                @(posedge overrun_err);
                $display("   [SUCCESS] Hardware pulsed overrun alert wire!");
            end
            begin : pulse_timeout
                repeat(50000) @(posedge clk);
                $display("[FAIL] Overrun pulse never arrived! Hardware failed to catch collision.");
                error_count = error_count + 1;
            end
        join_any
        disable fork;

        i = 0;
        while (!rx_fifo_empty) begin
            cpu_read_rx(read_val);
            if (read_val !== rx_stall_data[i]) begin
                $display("   [CRITICAL] Data corruption at bit %0d! Expected %h, Got %h at time %0t", i, rx_stall_data[i], read_val, $time);
                error_count = error_count + 1;
            end
            i = i + 1;
        end
        
        if (error_count == 0) begin
            $display("===ALL VERIFICATION TESTS PASSED!===");
        end else begin
            $display("===TESTBENCH FAILED! ERROR: %0d", error_count);
        end
        $finish;
    end

endmodule