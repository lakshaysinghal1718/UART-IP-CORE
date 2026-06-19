module uart_tx #(
        parameter DATA_BITS=8,
        parameter STOP_BITS=1,
        parameter PARITY_TYPE=0
    )(
        input clk,
        input rst_n,
        input baud_tick,
        input tx_start,
        input [DATA_BITS-1:0]tx_data_in,
        
        output wire tx_busy,
        output reg tx_done,
        
        output reg tx_out
    );
    
        localparam TX_IDLE  = 3'd0,
                   TX_START = 3'd1,
                   TX_DATA  = 3'd2,
                   TX_PARITY= 3'd3,
                   TX_STOP  = 3'd4,
                   TX_STOP2 = 3'd5;
        
        reg [2:0]state;
        reg [DATA_BITS-1:0]shift_reg;
        reg [$clog2(DATA_BITS)-1:0]bit_cnt;
        reg parity_reg;
        
        assign tx_busy = (state != TX_IDLE);
        always @(posedge clk) begin
            if(!rst_n) begin
                state   <= TX_IDLE;
                shift_reg   <= 'd0; 
                bit_cnt     <= 'd0;
                parity_reg <= 1'b0;
                tx_out     <= 1'b1; // UART line idles HIGH
                tx_done    <= 1'b0;
            end else begin
                case(state)
                    TX_IDLE: begin 
                        tx_done <= 1'b0;
                        tx_out<=1;
                        if(tx_start==1) begin
                            shift_reg <= tx_data_in;
                            bit_cnt          <= 'd0;
                            parity_reg      <= 1'b0;
                            state       <= TX_START;
                        end
                        else state <= TX_IDLE; //no need as it will hold the default state only
                    end
                    
                    TX_START: begin
                        tx_out  <= 1'b0;
                        
                        if (baud_tick == 1'b1) begin
                            state <= TX_DATA;
                        end
                    end
                    
                    TX_DATA: begin
                        tx_out <= shift_reg[0];
                        
                        if (baud_tick == 1'b1) begin
                            parity_reg <= parity_reg^shift_reg[0];
                            shift_reg <= shift_reg>>1;
                            bit_cnt <= bit_cnt+1'b1; //POTENTIAL BUG CASE: KEEP AN EYE
                            
                            if (bit_cnt == (DATA_BITS-1)) begin
                                if (PARITY_TYPE != 0) state <= TX_PARITY;
                                else state <= TX_STOP;
                            end
                        end
                    end
                    
                    TX_PARITY: begin
                        
                        if (PARITY_TYPE ==1) begin
                            tx_out <= parity_reg; //EVEN PARITY
                        end else begin
                            tx_out <= ~parity_reg; //ODD PARITY
                        end
                        
                        if (baud_tick) begin
                            state <= TX_STOP;
                        end
                    end
                    
                    TX_STOP: begin
                        tx_out <= 1'b1;
                        
                        if (baud_tick) begin
                            if (STOP_BITS == 2) begin
                                state <= TX_STOP2;
                            end else begin
                                tx_done <= 1'b1;
                                state <= TX_IDLE;
                            end
                        end
                    end
                    
                    TX_STOP2: begin
                        tx_out  <= 1'b1;
                        
                        if (baud_tick) begin
                            tx_done  <= 1'b1;   // Pulse the done flag for the host
                            state <= TX_IDLE;
                        end
                    end
                            
                     
                endcase
            end 
        end  
endmodule
