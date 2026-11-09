// End-to-end layer sequencer. conv_start and pool_start are one-cycle pulses.
module cnn_controller (
    input  logic clk,
    input  logic rst_n,
    input  logic input_done,
    input  logic conv_done,
    input  logic pool_done,
    input  logic dense_done,
    input  logic argmax_done,
    output logic input_ready,
    output logic conv_start,
    output logic pool_start,
    output logic dense_start,
    output logic argmax_start,
    output logic [2:0] layer_id,
    output logic busy,
    output logic result_valid
);
    typedef enum logic [4:0] {
        S_LOAD,
        S_C1_START, S_C1_CONV, S_C1_POOL,
        S_C2_START, S_C2_CONV, S_C2_POOL,
        S_C3_START, S_C3_CONV, S_C3_POOL,
        S_C4_START, S_C4_CONV, S_C4_POOL,
        S_DENSE_START, S_DENSE_WAIT,
        S_ARGMAX_START, S_ARGMAX_WAIT,
        S_OUTPUT
    } state_t;
    state_t state;
    logic pool_done_seen;

    always_comb begin
        input_ready = (state == S_LOAD);
        conv_start = (state == S_C1_START) || (state == S_C2_START)
                  || (state == S_C3_START) || (state == S_C4_START);
        pool_start = conv_start;
        dense_start = (state == S_DENSE_START);
        argmax_start = (state == S_ARGMAX_START);
        result_valid = (state == S_OUTPUT);
        busy = !(state == S_LOAD || state == S_OUTPUT);
        layer_id = 3'd0;
        case (state)
            S_C1_START, S_C1_CONV, S_C1_POOL: layer_id = 3'd1;
            S_C2_START, S_C2_CONV, S_C2_POOL: layer_id = 3'd2;
            S_C3_START, S_C3_CONV, S_C3_POOL: layer_id = 3'd3;
            S_C4_START, S_C4_CONV, S_C4_POOL: layer_id = 3'd4;
            default: layer_id = 3'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_LOAD;
            pool_done_seen <= 1'b0;
        end else begin
            if (pool_done)
                pool_done_seen <= 1'b1;

            case (state)
                S_LOAD: if (input_done) state <= S_C1_START;
                S_C1_START: begin pool_done_seen <= 1'b0; state <= S_C1_CONV; end
                S_C1_CONV: if (conv_done) begin
                    if (pool_done || pool_done_seen) state <= S_C2_START;
                    else state <= S_C1_POOL;
                end
                S_C1_POOL: if (pool_done || pool_done_seen) state <= S_C2_START;

                S_C2_START: begin pool_done_seen <= 1'b0; state <= S_C2_CONV; end
                S_C2_CONV: if (conv_done) begin
                    if (pool_done || pool_done_seen) state <= S_C3_START;
                    else state <= S_C2_POOL;
                end
                S_C2_POOL: if (pool_done || pool_done_seen) state <= S_C3_START;

                S_C3_START: begin pool_done_seen <= 1'b0; state <= S_C3_CONV; end
                S_C3_CONV: if (conv_done) begin
                    if (pool_done || pool_done_seen) state <= S_C4_START;
                    else state <= S_C3_POOL;
                end
                S_C3_POOL: if (pool_done || pool_done_seen) state <= S_C4_START;

                S_C4_START: begin pool_done_seen <= 1'b0; state <= S_C4_CONV; end
                S_C4_CONV: if (conv_done) begin
                    if (pool_done || pool_done_seen) state <= S_DENSE_START;
                    else state <= S_C4_POOL;
                end
                S_C4_POOL: if (pool_done || pool_done_seen) state <= S_DENSE_START;

                S_DENSE_START: state <= S_DENSE_WAIT;
                S_DENSE_WAIT: if (dense_done) state <= S_ARGMAX_START;
                S_ARGMAX_START: state <= S_ARGMAX_WAIT;
                S_ARGMAX_WAIT: if (argmax_done) state <= S_OUTPUT;
                S_OUTPUT: state <= S_LOAD;
                default: state <= S_LOAD;
            endcase
        end
    end
endmodule
