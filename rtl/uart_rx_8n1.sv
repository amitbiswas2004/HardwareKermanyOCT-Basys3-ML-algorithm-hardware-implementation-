// 8-N-1 UART receiver, asynchronous RX input synchronized to clk.
module uart_rx_8n1 #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD = 115_200
) (
    input  logic clk,
    input  logic rst_n,
    input  logic uart_rxd,
    output logic [7:0] data,
    output logic valid
);
    localparam integer CLKS_PER_BIT = (CLOCK_HZ + BAUD/2) / BAUD;
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;
    localparam integer CW = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {IDLE, START_BIT, DATA_BITS, STOP_BIT} state_t;
    state_t state;

    (* ASYNC_REG = "TRUE" *) logic rx_meta;
    (* ASYNC_REG = "TRUE" *) logic rx_sync;
    logic [CW-1:0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta  <= 1'b1;
            rx_sync  <= 1'b1;
            state    <= IDLE;
            clk_count <= '0;
            bit_index <= '0;
            shift_reg <= '0;
            data      <= '0;
            valid     <= 1'b0;
        end else begin
            rx_meta <= uart_rxd;
            rx_sync <= rx_meta;
            valid <= 1'b0;

            case (state)
                IDLE: begin
                    clk_count <= '0;
                    if (!rx_sync) state <= START_BIT;
                end

                START_BIT: begin
                    if (clk_count == HALF_BIT-1) begin
                        clk_count <= '0;
                        if (!rx_sync) begin
                            bit_index <= 3'd0;
                            state <= DATA_BITS;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA_BITS: begin
                    if (clk_count == CLKS_PER_BIT-1) begin
                        clk_count <= '0;
                        shift_reg[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) state <= STOP_BIT;
                        else bit_index <= bit_index + 1'b1;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                STOP_BIT: begin
                    if (clk_count == CLKS_PER_BIT-1) begin
                        clk_count <= '0;
                        if (rx_sync) begin
                            data <= shift_reg;
                            valid <= 1'b1;
                        end
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
