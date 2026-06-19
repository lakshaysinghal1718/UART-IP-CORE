    module uart_rx #(
        parameter DATA_BITS = 8,
        parameter PARITY_TYPE = 0,
        parameter STOP_BITS = 1
    )(
        input clk,
        input rst_n,
        input rx_in,
        input sample_tick,
        
        output reg [DATA_BITS-1:0]rx_data,
        output reg rx_valid,
        output reg frame_err,
        output reg parity_err
    );
    
        reg [2:0]state;
        reg [$clog2(DATA_BITS)-1:0]bit_cnt;
        reg [DATA_BITS-1:0]shift_reg;
        reg parity_reg;
        reg [3:0]oversample_cnt; // will parameterize later
        reg rx_sync1;
        reg rx_sync2;
        
        localparam RX_IDLE   = 3'd0,
                   RX_START  = 3'd1,
                   RX_DATA   = 3'd2,
                   RX_PARITY = 3'd3,
                   RX_STOP   = 3'd4,
                   RX_STOP2  = 3'd5;
                    
        always @(posedge clk) begin
            if (!rst_n) begin
                state      <= RX_IDLE;
                bit_cnt        <= 'd0;
                shift_reg      <= 'd0;
                parity_reg    <= 1'b0;
                oversample_cnt <= 'd0;
                rx_data        <= 'd0;
                rx_valid      <= 1'b0;
                frame_err     <= 1'b0;
                parity_err    <= 1'b0;
                rx_sync1      <= 1'b1;
                rx_sync2      <= 1'b1;
            end else begin
                rx_sync1 <= rx_in;
                rx_sync2 <= rx_sync1;
                
                case(state)
                    RX_IDLE: begin
                        rx_valid <= 1'b0;
                        parity_err <= 1'b0;
                        frame_err <= 1'b0;
                        
                        if (rx_sync2 == 1'b0) begin
                            oversample_cnt <= 'd0;
                            state      <= RX_START;
                        end
                    end
                    
                    RX_START: begin
                        if (sample_tick == 1'b1) begin
                            oversample_cnt <= oversample_cnt + 1'b1;
                            
                            if (oversample_cnt == 4'd7) begin
                                
                                if (rx_sync2 == 1'b0) begin
                                    state <= RX_DATA;
                                    bit_cnt <= 'd0;
                                    parity_reg <= 1'b0;
                                end else begin
                                    state <= RX_IDLE; // GLITCH
                                end
                            end
                        end
                    end
                    
                    RX_DATA: begin
                        if (sample_tick == 1'b1) begin
                            oversample_cnt <= oversample_cnt +1'b1;
                            
                            if (oversample_cnt == 4'd7) begin
                                shift_reg <= {rx_sync2, shift_reg[DATA_BITS-1:1]};
                                parity_reg <= parity_reg^rx_sync2;
                                
                                if (bit_cnt == (DATA_BITS-1)) begin
                                    if (PARITY_TYPE != 0) state <= RX_PARITY;
                                    else state <= RX_STOP;
                                end else bit_cnt <= bit_cnt + 1'b1;
                            end
                        end
                    end
                    
                    RX_PARITY: begin
                        if (sample_tick == 1'b1) begin
                            oversample_cnt <= oversample_cnt + 1'b1;
                            
                            if (oversample_cnt == 4'd7) begin
                                
                                if (PARITY_TYPE == 1) parity_err <= (rx_sync2 != parity_reg); //EVEN PARITY
                                else parity_err <= (rx_sync2 != ~parity_reg); //ODD PARITY
                                
                                state <= RX_STOP;
                                end
                        end
                    end
                    
                    RX_STOP: begin
                        if (sample_tick == 1'b1) begin
                            oversample_cnt <= oversample_cnt + 1'b1;
                            
                            if (oversample_cnt == 4'd7) begin
                                
                                if (STOP_BITS == 1) begin
                                    state <= RX_IDLE;
                                    if (rx_sync2 == 1) begin
                                        rx_valid <= 1;
                                        rx_data <= shift_reg;
                                    end
                                    else frame_err <= 1;
                                    end
                                    
                                else begin
                                    if(rx_sync2 == 1) begin
                                        state <= RX_STOP2;
                                        rx_data <= shift_reg;
                                    end
                                    else begin
                                        state <= RX_IDLE;
                                        frame_err <= 1;
                                    end
                                end
                            end
                        end
                    end
                    
                    RX_STOP2: begin
                        if (sample_tick == 1'b1) begin
                            oversample_cnt <= oversample_cnt + 1'b1;
                            
                            if (oversample_cnt == 4'd7) begin
                                if(rx_sync2 == 1'b1) rx_valid <= 1'b1;
                                
                                else frame_err <= 1'b1;
                                state <= RX_IDLE;
                            end
                        end
                    end
                                    
                                
                endcase
            end                                 
        end
    endmodule        