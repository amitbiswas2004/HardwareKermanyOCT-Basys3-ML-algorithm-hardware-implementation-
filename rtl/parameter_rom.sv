// Synchronous ROM for per-output-channel Q24 multipliers.
module parameter_rom #(
    parameter integer ADDR_WIDTH = 7,
    parameter integer DEPTH = 16,
    parameter INIT_FILE = "memory/layer1_multipliers.mem"
) (
    input  logic                  clk,
    input  logic                  en,
    input  logic [ADDR_WIDTH-1:0]  addr,
    output logic signed [31:0]    data
);
    (* rom_style = "distributed" *) logic [31:0] mem [0:DEPTH-1];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (en) begin
            if (addr < DEPTH)
                data <= $signed(mem[addr]);
            else
                data <= 32'sd0;
        end
    end
endmodule
