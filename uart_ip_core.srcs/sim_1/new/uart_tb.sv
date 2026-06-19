`timescale 1ns / 1ps
module uart_tb;
    parameter DATA_BITS   = 8;
    parameter PARITY_TYPE = 0;
    parameter STOP_BITS   = 1;
    
    integer pass_cnt;
    integer fail_cnt;
    
    reg clk;
    reg rst_n;
    reg tx_start;
    reg [DATA_BITS-1:0]tx_data_in;
    
    wire [DATA_BITS-1:0]rx_data;
    wire rx_valid;
    wire tx_busy;
    wire tx_done;
    wire frame_err;
    wire parity_err;
    wire tx_out;
    wire rx_in;
    
    assign rx_in = tx_out;
    
    uart_top #(
        .DATA_BITS(DATA_BITS),
        .PARITY_TYPE(PARITY_TYPE),
        .STOP_BITS(STOP_BITS)
    ) dut (.*);
    
    initial clk = 0;
    always #10 clk = ~clk; //50MHz clock
    
    task send_byte(input [DATA_BITS-1:0]data);
        begin
            @(posedge clk);
            tx_data_in = data;
            tx_start = 1;
            @(posedge clk);
            tx_start = 0;
            
            fork
                begin : timeout_block
                    repeat(20000) @(posedge clk);
                    $fatal(1, "TIMEOUT waiting for tx_done");
                end
                begin
                    @(posedge tx_done);
                    disable timeout_block;
                end
                
                
                begin : timeout_block2
                    repeat(20000) @(posedge clk);
                    $fatal(1, "TIMEOUT waiting for rx_valid");
                end
                begin
                    @(posedge rx_valid);
                    disable timeout_block2;
                end
            join
            
            
            
            if(rx_data == data && !frame_err && !parity_err) begin
                $display("PASS:- Sent: %h, Got: %h", data, rx_data);
                pass_cnt = pass_cnt+1;
            end
            else begin
                $error("FAIL:- Sent: %h, Got: %h, frame_err: %b, parity_err: %b", data, rx_data, frame_err, parity_err);
                fail_cnt = fail_cnt+1;
            end
        end
    endtask
                 
    // Hardware Probe: Trace the RX State Machine
    always @(dut.u_uart_rx.state) begin
        $display("[TIME: %0t ns] RX State changed to: %0d", $time, dut.u_uart_rx.state);
    end
    initial begin
        rst_n      = 0;
        tx_start   = 0;
        tx_data_in = 0;
        pass_cnt   = 0;
        fail_cnt   = 0;
          
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        $display("===DIRECTED TESTS===");
        send_byte(8'h00); //all zeros
        send_byte(8'hFF); //all ones
        send_byte(8'h55); //alternate starting from 0
        send_byte(8'hAA); //alternate starting from 1
        
        $display("===RANDOMIZED TESTS===");
        repeat(1000) begin
            send_byte($urandom_range(0,255));
        end
        


$display("=== ERROR INJECTION TEST ===");
        begin
            @(posedge clk);
            tx_data_in = 8'hA5;
            tx_start   = 1'b1;
            @(posedge clk);
            tx_start   = 1'b0;
            

            repeat(9) @(posedge dut.baud_tick);
            
            force dut.u_uart_rx.rx_in = 1'b0;
            
            fork
                begin : timeout_err
                    repeat(20000) @(posedge clk);
                    $error("FAIL:- Frame error not detected (TIMEOUT)");
                    fail_cnt = fail_cnt + 1;
                end
                begin : get_err
                    @(posedge frame_err);
                    $display("PASS:- Frame error correctly detected");
                    pass_cnt = pass_cnt + 1;
                    disable timeout_err;
                end
            join
            
            release dut.u_uart_rx.rx_in;
            
            @(posedge tx_done);
        end
        
        
        $display("=== Testbench Complete. Pass: %0d  Fail: %0d ===", pass_cnt, fail_cnt);
        $finish;
    end
        
    
    
endmodule