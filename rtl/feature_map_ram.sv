// Synchronous simple-dual-port RAM. No reset on the memory array so Vivado
// can infer block RAM. Every location used by a frame is overwritten before read.
module feature_map_ram #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ADDR_WIDTH = 16,
    parameter integer DEPTH      = 63504
) (
    input  logic                  clk,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0]  rd_addr,
    output logic [DATA_WIDTH-1:0]  rd_data,
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0]  wr_addr,
    input  logic [DATA_WIDTH-1:0]  wr_data
);
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end
endmodule
