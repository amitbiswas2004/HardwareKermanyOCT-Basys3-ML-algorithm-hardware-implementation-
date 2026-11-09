module cnn_top (
    input  logic clk,
    input  logic rst_n,
    input  logic input_valid,
    input  logic [7:0] input_pixel,
    output logic input_ready,
    output logic output_valid,
    output logic [1:0] output_class,
    output logic signed [31:0] output_logits [0:3],
    output logic signed [31:0] output_logit0,
    output logic signed [31:0] output_logit1,
    output logic signed [31:0] output_logit2,
    output logic signed [31:0] output_logit3
);
    import cnn_params_pkg::*;

    logic input_done;
    logic controller_input_ready;
    logic [13:0] input_count;
    logic input_bank; // 0: bank0 is current input; 1: bank1 is current input

    logic conv_start, pool_start, dense_start, argmax_start;
    logic [2:0] layer_id;
    logic controller_busy, result_valid_i;
    logic conv_done, pool_done, dense_done, argmax_done;

    logic [7:0] conv_input_width, conv_input_height;
    logic [6:0] conv_input_channels, conv_output_channels;
    logic [7:0] pool_input_width, pool_input_height;

    logic conv_fm_rd_en, conv_weight_rd_en, conv_mult_rd_en;
    logic [15:0] conv_fm_rd_addr, conv_weight_rd_addr;
    logic [6:0] conv_mult_rd_addr;
    logic [7:0] feature_rd_data;
    logic signed [7:0] selected_weight_data;
    logic signed [17:0] selected_mult_data;
    logic [7:0] weight1_data, weight2_data, weight3_data, weight4_data;
    logic signed [31:0] mult1_data, mult2_data, mult3_data, mult4_data;

    logic conv_pixel_valid;
    logic [7:0] conv_pixel_data;
    logic conv_busy;

    logic pool_out_valid;
    logic [15:0] pool_out_addr;
    logic [7:0] pool_out_data;
    logic pool_busy;

    logic dense_fm_rd_en;
    logic [15:0] dense_fm_rd_addr;
    logic dense_busy;
    logic signed [31:0] dense_logit0, dense_logit1, dense_logit2, dense_logit3;

    logic [1:0] argmax_class;

    logic bank0_rd_en, bank1_rd_en;
    logic [15:0] bank0_rd_addr, bank1_rd_addr;
    logic [7:0] bank0_rd_data, bank1_rd_data;
    logic bank0_wr_en, bank1_wr_en;
    logic [15:0] bank0_wr_addr, bank1_wr_addr;
    logic [7:0] bank0_wr_data, bank1_wr_data;
    logic feature_rd_en;
    logic [15:0] feature_rd_addr;
    logic load_wr_en;
    logic pool_wr_bank0, pool_wr_bank1;

    cnn_controller controller (
        .clk(clk),
        .rst_n(rst_n),
        .input_done(input_done),
        .conv_done(conv_done),
        .pool_done(pool_done),
        .dense_done(dense_done),
        .argmax_done(argmax_done),
        .input_ready(controller_input_ready),
        .conv_start(conv_start),
        .pool_start(pool_start),
        .dense_start(dense_start),
        .argmax_start(argmax_start),
        .layer_id(layer_id),
        .busy(controller_busy),
        .result_valid(result_valid_i)
    );

    // Input dimensions and channel counts taken directly from model.py.
    always_comb begin
        conv_input_width = 8'd128;
        conv_input_height = 8'd128;
        conv_input_channels = 7'd1;
        conv_output_channels = 7'd16;
        case (layer_id)
            3'd2: begin
                conv_input_width = 8'd63;
                conv_input_height = 8'd63;
                conv_input_channels = 7'd16;
                conv_output_channels = 7'd32;
            end
            3'd3: begin
                conv_input_width = 8'd30;
                conv_input_height = 8'd30;
                conv_input_channels = 7'd32;
                conv_output_channels = 7'd64;
            end
            3'd4: begin
                conv_input_width = 8'd14;
                conv_input_height = 8'd14;
                conv_input_channels = 7'd64;
                conv_output_channels = 7'd64;
            end
            default: begin end
        endcase
        pool_input_width = conv_input_width - 8'd2;
        pool_input_height = conv_input_height - 8'd2;
    end

    // Sequential input loading. The RAM is not reset; every image pixel is overwritten.
    // Deassert ready immediately after the final accepted input pixel, even
    // though the controller consumes input_done on the following clock.
    assign input_ready = controller_input_ready && !input_done;
    assign load_wr_en = input_valid && input_ready;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_count <= 14'd0;
            input_done <= 1'b0;
            input_bank <= 1'b0;
        end else begin
            input_done <= 1'b0;
            if (load_wr_en) begin
                if (input_count == IMAGE_PIXELS - 1) begin
                    input_count <= 14'd0;
                    input_done <= 1'b1;
                end else begin
                    input_count <= input_count + 1'b1;
                end
            end
            if (pool_done)
                input_bank <= ~input_bank;
        end
    end

    assign feature_rd_en = conv_fm_rd_en || dense_fm_rd_en;
    assign feature_rd_addr = conv_fm_rd_en ? conv_fm_rd_addr : dense_fm_rd_addr;
    assign feature_rd_data = input_bank ? bank1_rd_data : bank0_rd_data;

    assign bank0_rd_en = feature_rd_en && !input_bank;
    assign bank1_rd_en = feature_rd_en && input_bank;
    assign bank0_rd_addr = feature_rd_addr;
    assign bank1_rd_addr = feature_rd_addr;

    assign pool_wr_bank0 = pool_out_valid && input_bank;
    assign pool_wr_bank1 = pool_out_valid && !input_bank;

    always_comb begin
        bank0_wr_en = load_wr_en || pool_wr_bank0;
        bank1_wr_en = pool_wr_bank1;
        bank0_wr_addr = load_wr_en ? {2'b00, input_count} : pool_out_addr;
        bank1_wr_addr = pool_out_addr;
        bank0_wr_data = load_wr_en ? input_pixel : pool_out_data;
        bank1_wr_data = pool_out_data;
    end

    feature_map_ram #(.DATA_WIDTH(8), .ADDR_WIDTH(16), .DEPTH(FEATURE_MAP_DEPTH)) bank0 (
        .clk(clk), .rd_en(bank0_rd_en), .rd_addr(bank0_rd_addr), .rd_data(bank0_rd_data),
        .wr_en(bank0_wr_en), .wr_addr(bank0_wr_addr), .wr_data(bank0_wr_data)
    );
    feature_map_ram #(.DATA_WIDTH(8), .ADDR_WIDTH(16), .DEPTH(FEATURE_MAP_DEPTH)) bank1 (
        .clk(clk), .rd_en(bank1_rd_en), .rd_addr(bank1_rd_addr), .rd_data(bank1_rd_data),
        .wr_en(bank1_wr_en), .wr_addr(bank1_wr_addr), .wr_data(bank1_wr_data)
    );

    // Four independent ROMs hold only the coefficients for their respective layer.
    weight_rom_dist #(.WIDTH(8), .DEPTH(144), .INIT_FILE("memory/layer1_weights.mem")) wrom1 (
        .clk(clk), .en(conv_weight_rd_en && (layer_id == 1)), .addr(conv_weight_rd_addr), .data(weight1_data)
    );
    weight_rom_dist #(.WIDTH(8), .DEPTH(4608), .INIT_FILE("memory/layer2_weights.mem")) wrom2 (
        .clk(clk), .en(conv_weight_rd_en && (layer_id == 2)), .addr(conv_weight_rd_addr), .data(weight2_data)
    );
    weight_rom_dist #(.WIDTH(8), .DEPTH(18432), .INIT_FILE("memory/layer3_weights.mem")) wrom3 (
        .clk(clk), .en(conv_weight_rd_en && (layer_id == 3)), .addr(conv_weight_rd_addr), .data(weight3_data)
    );
    weight_rom #(.WIDTH(8), .DEPTH(36864), .INIT_FILE("memory/layer4_weights.mem")) wrom4 (
        .clk(clk), .en(conv_weight_rd_en && (layer_id == 4)), .addr(conv_weight_rd_addr), .data(weight4_data)
    );

    parameter_rom #(.DEPTH(16), .INIT_FILE("memory/layer1_multipliers.mem")) mrom1 (
        .clk(clk), .en(conv_mult_rd_en && (layer_id == 1)), .addr(conv_mult_rd_addr), .data(mult1_data)
    );
    parameter_rom #(.DEPTH(32), .INIT_FILE("memory/layer2_multipliers.mem")) mrom2 (
        .clk(clk), .en(conv_mult_rd_en && (layer_id == 2)), .addr(conv_mult_rd_addr), .data(mult2_data)
    );
    parameter_rom #(.DEPTH(64), .INIT_FILE("memory/layer3_multipliers.mem")) mrom3 (
        .clk(clk), .en(conv_mult_rd_en && (layer_id == 3)), .addr(conv_mult_rd_addr), .data(mult3_data)
    );
    parameter_rom #(.DEPTH(64), .INIT_FILE("memory/layer4_multipliers.mem")) mrom4 (
        .clk(clk), .en(conv_mult_rd_en && (layer_id == 4)), .addr(conv_mult_rd_addr), .data(mult4_data)
    );

    always_comb begin
        selected_weight_data = 8'sd0;
        selected_mult_data = 18'sd0;
        case (layer_id)
            3'd1: begin selected_weight_data = $signed(weight1_data); selected_mult_data = $signed(mult1_data[17:0]); end
            3'd2: begin selected_weight_data = $signed(weight2_data); selected_mult_data = $signed(mult2_data[17:0]); end
            3'd3: begin selected_weight_data = $signed(weight3_data); selected_mult_data = $signed(mult3_data[17:0]); end
            3'd4: begin selected_weight_data = $signed(weight4_data); selected_mult_data = $signed(mult4_data[17:0]); end
            default: begin end
        endcase
    end

    conv_engine #(.ZERO_POINT(CONV_ZERO_POINT)) convolution (
        .clk(clk), .rst_n(rst_n), .start(conv_start),
        .input_width(conv_input_width), .input_height(conv_input_height),
        .input_channels(conv_input_channels), .output_channels(conv_output_channels),
        .fm_rd_en(conv_fm_rd_en), .fm_rd_addr(conv_fm_rd_addr), .fm_rd_data(feature_rd_data),
        .weight_rd_en(conv_weight_rd_en), .weight_rd_addr(conv_weight_rd_addr), .weight_rd_data(selected_weight_data),
        .mult_rd_en(conv_mult_rd_en), .mult_rd_addr(conv_mult_rd_addr), .mult_rd_data(selected_mult_data),
        .pixel_valid(conv_pixel_valid), .pixel_data(conv_pixel_data), .busy(conv_busy), .done(conv_done)
    );

    maxpool_stream pool (
        .clk(clk), .rst_n(rst_n), .start(pool_start),
        .input_width(pool_input_width), .input_height(pool_input_height),
        .channels(conv_output_channels),
        .pixel_valid(conv_pixel_valid), .pixel_data(conv_pixel_data),
        .out_valid(pool_out_valid), .out_addr(pool_out_addr), .out_data(pool_out_data),
        .busy(pool_busy), .done(pool_done)
    );

    dense_engine #(
        .FEATURES(DENSE_FEATURES),
        .ZERO_POINT(DENSE_ZERO_POINT),
        .BIAS_FILE("memory/layer5_dense_biases.mem"),
        .MULT_FILE("memory/layer5_dense_multiplier.mem"),
        .WEIGHT_FILE("memory/layer5_dense_weights_packed.mem")
    ) classifier (
        .clk(clk), .rst_n(rst_n), .start(dense_start),
        .feature_rd_en(dense_fm_rd_en), .feature_rd_addr(dense_fm_rd_addr), .feature_rd_data(feature_rd_data),
        .logit0(dense_logit0), .logit1(dense_logit1), .logit2(dense_logit2), .logit3(dense_logit3),
        .busy(dense_busy), .done(dense_done)
    );

    argmax classifier_argmax (
        .clk(clk), .rst_n(rst_n), .start(argmax_start),
        .logit0(dense_logit0), .logit1(dense_logit1), .logit2(dense_logit2), .logit3(dense_logit3),
        .class_index(argmax_class), .done(argmax_done)
    );

    always_comb begin
        output_class = argmax_class;
        output_valid = result_valid_i;
        output_logits[0] = dense_logit0;
        output_logits[1] = dense_logit1;
        output_logits[2] = dense_logit2;
        output_logits[3] = dense_logit3;
        output_logit0 = dense_logit0;
        output_logit1 = dense_logit1;
        output_logit2 = dense_logit2;
        output_logit3 = dense_logit3;
    end
endmodule
