module fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input clk,
    input rst_n,
    input wr_en,
    input rd_en,
    input [DATA_WIDTH-1:0]din,
    input [ADDR_WIDTH:0] full_threshold,
    input [ADDR_WIDTH:0] empty_threshold,
    
    output wire almost_full,
    output wire almost_empty,  
    output wire [DATA_WIDTH-1:0]dout,
    output wire full,
    output wire empty,
    output reg [ADDR_WIDTH:0]data_count
);
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] read_ptr;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            write_ptr <= 0;
            read_ptr <= 0;
            data_count <= 0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: data_count <= data_count + 1;
                2'b01: data_count <= data_count - 1;
                default: data_count <= data_count;
            endcase
            
            if (wr_en && !full) begin
                mem[write_ptr] <= din;
                write_ptr <= write_ptr +1;
            end
            if (rd_en && !empty) begin
                read_ptr <= read_ptr + 1;
            end             
        end
    end
    assign full         = (data_count == (1 << ADDR_WIDTH));
    assign empty        = (data_count == 0);
    assign almost_full  = (data_count >= full_threshold);
    assign almost_empty = (data_count <= empty_threshold);
    assign dout         = mem[read_ptr];
endmodule