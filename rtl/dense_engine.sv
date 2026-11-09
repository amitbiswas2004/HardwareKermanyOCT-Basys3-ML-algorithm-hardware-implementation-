// Four-output fully-connected layer. Four 9x8 MAC lanes run in parallel.
// A shared 25x18 Q24 multiplier is reused over four cycles.
module dense_engine #(
    parameter integer FEATURES = 2304,
    parameter integer ZERO_POINT = 86,
    parameter BIAS_FILE = "memory/layer5_dense_biases.mem",
    parameter MULT_FILE = "memory/layer5_dense_multiplier.mem",
    parameter WEIGHT_FILE = "memory/layer5_dense_weights_packed.mem"
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic feature_rd_en,
    output logic [15:0] feature_rd_addr,
    input  logic [7:0] feature_rd_data,
    output logic signed [31:0] logit0,
    output logic signed [31:0] logit1,
    output logic signed [31:0] logit2,
    output logic signed [31:0] logit3,
    output logic busy,
    output logic done
);
    typedef enum logic [1:0] {ST_IDLE, ST_RUN, ST_QUANT} state_t;
    state_t state;

    logic [12:0] feature_count;
    logic req_valid_d;
    logic req_last_d;
    logic [31:0] packed_weights;
    logic weight_rom_en;

    (* rom_style = "distributed" *) logic signed [31:0] bias_mem [0:3];
    (* rom_style = "distributed" *) logic signed [31:0] multiplier_mem [0:0];
    logic signed [17:0] dense_multiplier;

    logic signed [24:0] accum [0:3];
    logic [1:0] quant_count;
    (* use_dsp = "yes" *) logic signed [42:0] quant_scaled;
    logic signed [42:0] quant_result;

    logic signed [8:0] feature_s;
    logic signed [7:0] weight0_s, weight1_s, weight2_s, weight3_s;
    logic signed [16:0] product0, product1, product2, product3;
    logic signed [24:0] next0, next1, next2, next3;

    assign busy = (state != ST_IDLE);
    assign feature_rd_en = (state == ST_RUN);
    assign feature_rd_addr = feature_count[15:0];
    assign weight_rom_en = (state == ST_RUN);

    assign feature_s = $signed({1'b0, feature_rd_data});
    assign weight0_s = $signed(packed_weights[7:0]);
    assign weight1_s = $signed(packed_weights[15:8]);
    assign weight2_s = $signed(packed_weights[23:16]);
    assign weight3_s = $signed(packed_weights[31:24]);

    (* use_dsp = "yes" *) logic signed [16:0] product0_dsp;
    (* use_dsp = "yes" *) logic signed [16:0] product1_dsp;
    (* use_dsp = "yes" *) logic signed [16:0] product2_dsp;
    (* use_dsp = "yes" *) logic signed [16:0] product3_dsp;

    always_comb begin
        product0_dsp = feature_s * weight0_s;
        product1_dsp = feature_s * weight1_s;
        product2_dsp = feature_s * weight2_s;
        product3_dsp = feature_s * weight3_s;
        product0 = product0_dsp;
        product1 = product1_dsp;
        product2 = product2_dsp;
        product3 = product3_dsp;

        next0 = accum[0] + {{8{product0[16]}}, product0};
        next1 = accum[1] + {{8{product1[16]}}, product1};
        next2 = accum[2] + {{8{product2[16]}}, product2};
        next3 = accum[3] + {{8{product3[16]}}, product3};

        quant_scaled = accum[quant_count] * dense_multiplier;
        quant_result = (quant_scaled >>> 24) + ZERO_POINT;
    end

    weight_rom_dist #(
        .WIDTH(32), .ADDR_WIDTH(16), .DEPTH(FEATURES), .INIT_FILE(WEIGHT_FILE)
    ) dense_weight_rom (
        .clk(clk), .en(weight_rom_en), .addr(feature_count[15:0]), .data(packed_weights)
    );

    initial begin
        $readmemh(BIAS_FILE, bias_mem);
        $readmemh(MULT_FILE, multiplier_mem);
    end
    assign dense_multiplier = $signed(multiplier_mem[0][17:0]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            feature_count <= '0;
            req_valid_d <= 1'b0;
            req_last_d <= 1'b0;
            quant_count <= '0;
            accum[0] <= '0; accum[1] <= '0; accum[2] <= '0; accum[3] <= '0;
            logit0 <= '0; logit1 <= '0; logit2 <= '0; logit3 <= '0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            req_valid_d <= 1'b0;

            if ((state == ST_IDLE) && start) begin
                feature_count <= '0;
                quant_count <= '0;
                accum[0] <= $signed(bias_mem[0][24:0]);
                accum[1] <= $signed(bias_mem[1][24:0]);
                accum[2] <= $signed(bias_mem[2][24:0]);
                accum[3] <= $signed(bias_mem[3][24:0]);
                state <= ST_RUN;
            end else begin
                if (state == ST_RUN) begin
                    req_valid_d <= 1'b1;
                    req_last_d <= (feature_count == FEATURES - 1);
                    if (feature_count == FEATURES - 1)
                        state <= ST_QUANT;
                    else
                        feature_count <= feature_count + 1'b1;
                end

                // Consume final registered feature/weight product before quantizing.
                if (req_valid_d) begin
                    accum[0] <= next0;
                    accum[1] <= next1;
                    accum[2] <= next2;
                    accum[3] <= next3;
                end

                if (state == ST_QUANT) begin
                    // One-cycle drain guard: req_last_d marks the last outstanding read.
                    if (!req_valid_d && !req_last_d) begin
                        case (quant_count)
                            0: logit0 <= quant_result[31:0];
                            1: logit1 <= quant_result[31:0];
                            2: logit2 <= quant_result[31:0];
                            default: logit3 <= quant_result[31:0];
                        endcase
                        if (quant_count == 3) begin
                            done <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            quant_count <= quant_count + 1'b1;
                        end
                    end
                    if (req_valid_d && req_last_d) begin
                        // The last MAC update occurs at this edge; quant starts next edge.
                        req_last_d <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
