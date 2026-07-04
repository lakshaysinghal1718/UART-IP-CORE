`timescale 1ns/1ps
module tb_uart_top_phase3;
    parameter DATA_BITS   = 8;
    parameter PARITY_TYPE = 0;
    parameter STOP_BITS   = 1;
    parameter ADDR_WIDTH  = 4; 
    parameter FIFO_DEPTH  = 1 << ADDR_WIDTH;
    parameter IBRD = 27;
    parameter FBRD = 8;
    
    reg clk;
    reg rst_n;
    
    integer error_count = 0;
    integer pass_count = 0;
    reg [DATA_BITS-1:0]read_val;
    reg [DATA_BITS-1:0] tx_stall_data [0:FIFO_DEPTH-1];
    reg [DATA_BITS-1:0] rx_stall_data [0:FIFO_DEPTH-1];
    
    wire serial_A_to_B;
    wire serial_B_to_A;
    wire rts_A_to_cts_B;
    wire rts_B_to_cts_A;
    
    reg tx_wr_en_A;
    reg [DATA_BITS-1:0]tx_data_in_A;
    wire tx_fifo_full_A;
    wire tx_fifo_empty_A;
    
    reg rx_rd_en_A;
    wire [DATA_BITS-1:0]rx_data_out_A;
    wire rx_fifo_full_A;
    wire rx_fifo_empty_A;
    wire overrun_err_A; 
    
    
    
    reg tx_wr_en_B;
    reg [DATA_BITS-1:0]tx_data_in_B;
    wire tx_fifo_full_B;
    wire tx_fifo_empty_B;
    
    reg rx_rd_en_B;
    wire [DATA_BITS-1:0]rx_data_out_B;
    wire rx_fifo_full_B;
    wire rx_fifo_empty_B;
    wire overrun_err_B;
    
    // UART A
    uart_top #(
        .DATA_BITS(DATA_BITS),
        .STOP_BITS(STOP_BITS),
        .PARITY_TYPE(PARITY_TYPE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .IBRD(IBRD),
        .FBRD(FBRD)
    ) UART_A (
        .clk(clk),
        .rst_n(rst_n),
        
        .tx_wr_en(tx_wr_en_A),
        .tx_data_in(tx_data_in_A),
        .tx_fifo_full(tx_fifo_full_A),
        .tx_fifo_empty(tx_fifo_empty_A),
        
        .rx_rd_en(rx_rd_en_A),
        .rx_data_out(rx_data_out_A),
        .rx_fifo_full(rx_fifo_full_A),
        .rx_fifo_empty(rx_fifo_empty_A),
        .overrun_err(overrun_err_A),
        
        .tx_out(serial_A_to_B),
        .rx_in(serial_B_to_A),
        .cts_n(rts_B_to_cts_A),
        .rts_n(rts_A_to_cts_B)
    );
    
    // UART B
    uart_top #(
        .DATA_BITS(DATA_BITS),
        .STOP_BITS(STOP_BITS),
        .PARITY_TYPE(PARITY_TYPE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .IBRD(IBRD),
        .FBRD(FBRD)
    ) UART_B (
        .clk(clk),
        .rst_n(rst_n),
        
        .tx_wr_en(tx_wr_en_B),
        .tx_data_in(tx_data_in_B),
        .tx_fifo_full(tx_fifo_full_B),
        .tx_fifo_empty(tx_fifo_empty_B),
        
        .rx_rd_en(rx_rd_en_B),
        .rx_data_out(rx_data_out_B),
        .rx_fifo_full(rx_fifo_full_B),
        .rx_fifo_empty(rx_fifo_empty_B),
        .overrun_err(overrun_err_B),
        
        .tx_out(serial_B_to_A),
        .rx_in(serial_A_to_B),
        .cts_n(rts_A_to_cts_B),
        .rts_n(rts_B_to_cts_A)
    );
    
    initial clk = 0;
    always #10 clk = ~clk;
    
    reg [DATA_BITS-1:0]ideal_data[0:19];
    
    real start_time;
    real end_time;
    real avg_period;
    real expected_period = 1000000000.0/115200.0; //1sec/115200 in ns= 8680.55 ns
    integer i;
    
    initial begin
        clk = 0;
        rst_n = 0;
        tx_wr_en_A = 0; tx_data_in_A = 0; rx_rd_en_A = 0;
        tx_wr_en_B = 0; tx_data_in_B = 0; rx_rd_en_B = 0;
        pass_count = 0; error_count = 0;
        
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(10) @(posedge clk);
        
        $display("===== PHASE 3 TEST =====");
        
        $display("=== FRACTIONAL BAUD RATE TEST ===");
        fork
            begin : measure_baud
                @(posedge UART_A.baud_tick);
                start_time = $realtime;
                repeat(128) @(posedge UART_A.baud_tick);
                end_time = $realtime;
            end
            begin : timeout_baud
                repeat(100000) @(posedge clk);
                $display(" [FATAL] Timeout waiting for baud_ticks!");
                error_count = error_count + 1;
            end
        join_any
        disable fork;
        
        avg_period = (end_time-start_time)/128.0;
        
        $display("Target Period: %.2f ns", expected_period);
        $display("Measured Period: %.2f ns", avg_period);
        
        //Tolerance of +-2%
        if (avg_period > expected_period*0.98 && avg_period < expected_period * 1.02) begin
            $display(" [PASS] Baud rate is within +/- 2%% tolerance.");
        end else begin
            $display(" [FAIL] Baud rate out of tolerance limits.");
            error_count = error_count + 1;
        end
        
        $display("=== RTS/CTS FLOW CONTROL TEST ===");
        
        for(i=0; i < 20; i = i+1) begin
            ideal_data[i] = $random & 8'hFF; //Masking as $random creates a 32 bit signed integer and we want only 8 bits.
        end
        
        $display("Loading 20 bytes into UART A...");
        for(i=0; i < 20; i = i+1) begin
            cpu_write_tx_A(ideal_data[i]);
        end
        
        fork
            begin : wait_rts
                wait(rts_B_to_cts_A == 1'b1);
                $display("RTS of UART_B is asserted. Waiting to ensure TX pauses...");
            end
            begin : timeout_rts
                repeat(200000) @(posedge clk);
                $display(" [FATAL] Timeout waiting for RTS assertion!...");
                error_count = error_count + 1;
            end
        join_any
        disable fork; // Used to disable the remaining branch
        
        
        begin : overrun_check_block
            reg overrun_caught;
            overrun_caught = 1'b0;
            
            fork
                begin : wait_window
                    repeat(25000) @(posedge clk);
                end
                begin : catch_pulse
                    @(posedge overrun_err_B);
                    overrun_caught = 1'b1;
                end
            join_any
            disable fork;
            
            if (overrun_caught) begin
                $display(" [FAIL] UART B threw an Overrun Error! CTS failed to stop UART A");
                error_count = error_count + 1;
            end else begin
                $display(" [PASS] UART A is successfully paused. No Overrun detected.");
                pass_count = pass_count + 1;
            end
        end
        
        $display("Draining UART B and comparing data...");
        for (i = 0; i<20; i = i+1) begin
            fork
                begin : wait_rx_data
                    wait(!rx_fifo_empty_B);
                end
                begin : timeout_rx_data
                    repeat(100000) @(posedge clk);
                    $display(" [FATAL] Timeout waiting for byte %0d to arrive!", i);
                end
            join_any
            disable fork;
            
            cpu_read_rx_B(read_val); 
            
            if (read_val === ideal_data[i]) begin 
                pass_count = pass_count + 1;
            end else begin
                $display(" [FAIL] Data Mismatch at byte %0d. Expected: %h, Got: %h", i, ideal_data[i], read_val);
                error_count = error_count + 1;
            end
        end
        
        //=======================================
        //REGRESSION TESTS (PHASE 2 TESTS)
        //=======================================
        
        $display("\n=== STARTING PHASE 2 BURST TEST ===");
        
        $display("-> CPU Burst Writing to TX FIFO(UART A)...");
        tx_stall_data[0] = 8'h48; // 'H'
        tx_stall_data[1] = 8'h45; // 'E'
        tx_stall_data[2] = 8'h4C; // 'L'
        tx_stall_data[3] = 8'h4C; // 'L'
        tx_stall_data[4] = 8'h4F; // 'O'
        
        for (i = 0; i < 5; i = i + 1) begin
            cpu_write_tx_A(tx_stall_data[i]);
        end
        
        fork
            begin : test1_wait
                wait(UART_B.u_rx_fifo.data_count == 5);
            end
            begin : test1_timeout
                repeat(60000) @(posedge clk); 
                $display("[FATAL] Test 1 timed out waiting for RX count!");
                $finish;
            end
        join_any
        disable fork;
        
        i=0;
        while (!rx_fifo_empty_B) begin
            cpu_read_rx_B(read_val);
            if (read_val === tx_stall_data[i]) begin
                $display("Popped from UART B RX FIFO: %c (Hex: %h)", read_val, read_val);
            end else begin
                $display("[MISMATCH] Expected: %h, Got: %h", tx_stall_data[i], read_val);
                error_count = error_count + 1;
            end
            i = i + 1;
        end
        
        
        //OVERRUN TEST
        $display("--- TEST 2: RX OVERRUN ---");
        
        force rts_B_to_cts_A = 1'b0;
        
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            rx_stall_data[i] = $random & 8'hFF; //Masking as $random creates a 32 bit signed integer and we want only 8 bits.
        end

        for(i = 0; i < FIFO_DEPTH; i = i + 1) begin
            cpu_write_tx_A(rx_stall_data[i]);
        end
        
        fork
            begin : test2_fill_wait
                wait(UART_B.u_rx_fifo.full == 1'b1);
            end
            begin : test2_fill_timeout
                repeat(200000) @(posedge clk);
                $display("[FATAL] Test 2 timed out waiting for RX FIFO saturation!");
                $finish;
            end
        join_any
        disable fork;
        
        $display("Firing 17th byte...");    
        cpu_write_tx_A(8'hFF);
        
        fork
            begin : pulse_catch
                @(posedge overrun_err_B);
                $display(" [SUCCESS] Hardware pulsed overrun alert wire!");
            end
            begin : pulse_timeout
                repeat(50000) @(posedge clk);
                $display("[FAIL] Overrun pulse never arrived! Hardware failed to catch collision.");
                error_count = error_count + 1;
            end
        join_any
        disable fork;

        i = 0;
        while (!rx_fifo_empty_B) begin
            cpu_read_rx_B(read_val);
            if (read_val !== rx_stall_data[i]) begin
                $display("   [CRITICAL] Data corruption at bit %0d! Expected %h, Got %h at time %0t", i, rx_stall_data[i], read_val, $time);
                error_count = error_count + 1;
            end
            i = i + 1;
        end
        
        release rts_B_to_cts_A;
        
        //ALL TESTS FINISHED
        if (error_count == 0) begin
            $display("=== PHASE 3 VERIFICATION PASSED! ===");
        end else begin
            $display("=== VERIFICATION FAILED! ===");
        end
        $display(" Passes: %0d", pass_count);
        $display(" Errors: %0d", error_count);
        
        $finish;      
    end
    
    task cpu_write_tx_A(input [DATA_BITS-1:0] data);
        begin
            while (tx_fifo_full_A) begin
                @(posedge clk);
            end
            @(posedge clk);
            tx_wr_en_A <= 1'b1;
            tx_data_in_A <= data;
            
            @(posedge clk);
            tx_wr_en_A <= 1'b0;
            tx_data_in_A <= 8'h00;
            #1; // PROVIDING SIGNALS SOME TIME TO SETTLE
        end
    endtask
    
    task cpu_read_rx_A(output [DATA_BITS-1:0] data);
        begin
            @(posedge clk);
            if(!rx_fifo_empty_A) begin
                rx_rd_en_A <= 1'b1;
                data = rx_data_out_A;
            end else begin
                $display("ERROR: RX FIFO IS EMPTY! Cannot read. Time: %0t", $time);
                data = {DATA_BITS{1'bx}};
                error_count = error_count + 1;
            end
            @(posedge clk);
            rx_rd_en_A <= 1'b0;
            #1;
        end
    endtask
       
    task cpu_write_tx_B(input [DATA_BITS-1:0] data);
        begin
            while (tx_fifo_full_B) begin
                @(posedge clk);
            end
            @(posedge clk);
            tx_wr_en_B <= 1'b1;
            tx_data_in_B <= data;
            
            @(posedge clk);
            tx_wr_en_B <= 1'b0;
            tx_data_in_B <= 8'h00;
            #1; // PROVIDING SIGNALS SOME TIME TO SETTLE
        end
    endtask
    
    task cpu_read_rx_B(output [DATA_BITS-1:0] data);
        begin
            @(posedge clk);
            if(!rx_fifo_empty_B) begin
                rx_rd_en_B <= 1'b1;
                data = rx_data_out_B;
            end else begin
                $display("ERROR: RX FIFO IS EMPTY! Cannot read. Time: %0t", $time);
                data = {DATA_BITS{1'bx}};
                error_count = error_count + 1;
            end
            @(posedge clk);
            rx_rd_en_B <= 1'b0;
            #1;
        end
    endtask
       
endmodule