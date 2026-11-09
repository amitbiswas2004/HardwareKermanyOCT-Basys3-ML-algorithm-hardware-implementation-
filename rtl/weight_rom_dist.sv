// Synchronous LUTRAM/distributed-ROM implementation for modest coefficient tables.
module weight_rom_dist #(
    parameter integer WIDTH = 8,
    parameter integer ADDR_WIDTH = 16,
    parameter integer DEPTH = 144,
    parameter INIT_FILE = "memory/layer1_weights.mem"
) (
    input  logic                  clk,
    input  logic                  en,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [WIDTH-1:0]      data
);
    (* rom_style = "distributed" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (en)
            data <= mem[addr];
    end
endmodule
