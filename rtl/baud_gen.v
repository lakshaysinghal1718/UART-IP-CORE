module baud_gen #(
    parameter N=434,
    parameter N_rx=27
)(
    input wire clk,
    input wire rst_n,
    output reg baud_tick, 
    output reg sample_tick
);

    localparam TX_WIDTH=$clog2(N);
    localparam RX_WIDTH=$clog2(N_rx);

    reg [TX_WIDTH-1:0] tx_count;
    reg [RX_WIDTH-1:0] rx_count;

    //TX Counter
    always @(posedge clk) begin
        if (!rst_n) begin 
            tx_count<=0;
            baud_tick<=1'b0;
        end else begin 
            if (tx_count==N-1) begin
                tx_count<=0;
                baud_tick<=1'b1;
            end else begin
                tx_count<= tx_count+1'b1;
                baud_tick<=1'b0;
            end
        end
    end
    
    //RX Counter
    always @(posedge clk) begin
        if (!rst_n) begin 
            rx_count<=0;
            sample_tick<=1'b0;
        end else begin 
            if (rx_count==N_rx-1) begin
                rx_count<=0;
                sample_tick<=1'b1;
            end else begin
                rx_count<= rx_count+1'b1;
                sample_tick<=1'b0;
            end
        end
    end
endmodule