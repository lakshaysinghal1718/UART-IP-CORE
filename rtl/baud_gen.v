module baud_gen #(
    parameter IBRD = 27,
    parameter FBRD = 8
)(
    input wire clk,
    input wire rst_n,
    output reg baud_tick, 
    output reg sample_tick
);
    reg [5:0] phase_acc;
    reg [15:0] sys_count; // rx_clock
    reg [3:0] tick_count; //counts 16 sample_ticks for generation of one baud_tick
    
    wire [6:0] acc_next = phase_acc + FBRD;
    wire carry_out = acc_next[6];
    
    wire [15:0] target_count = (IBRD-1) + carry_out; 
    
    always @(posedge clk) begin
        if (!rst_n) begin
            sys_count <= 16'd0;
            sample_tick <= 1'b0;
            phase_acc <= 6'd0;
        end else begin
            if (sys_count == target_count) begin
                sys_count <= 16'd0;
                sample_tick <= 1'b1;
                phase_acc <= acc_next[5:0];
            end else begin
                sys_count <= sys_count + 1;
                sample_tick <= 1'b0;
            end
        end
    end
    
    always @(posedge clk) begin
        if(!rst_n) begin
            tick_count <= 4'd0;
            baud_tick <= 1'b0;
        end else begin
            baud_tick <= 1'b0;
            
            if (sample_tick == 1'b1) begin
                tick_count <= tick_count + 1'b1;
                if (tick_count == 4'd15) begin
                    baud_tick <= 1'b1;
                end
            end
        end
    end
    
endmodule