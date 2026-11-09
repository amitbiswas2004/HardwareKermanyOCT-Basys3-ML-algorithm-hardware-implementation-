// Sequentially scheduled valid 3x3 convolution engine.
// One feature byte and one signed weight are consumed per cycle after pipeline fill.
// The input and weight memories are synchronous; request tags are delayed to align.
module conv_engine #(
    parameter integer ZERO_POINT = 0
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [7:0]  input_width,
    input  logic [7:0]  input_height,
    input  logic [6:0]  input_channels,
    input  logic [6:0]  output_channels,

    output logic        fm_rd_en,
    output logic [15:0] fm_rd_addr,
    input  logic [7:0]  fm_rd_data,

    output logic        weight_rd_en,
    output logic [15:0] weight_rd_addr,
    input  logic signed [7:0] weight_rd_data,

    output logic        mult_rd_en,
    output logic [6:0]  mult_rd_addr,
    input  logic signed [17:0] mult_rd_data,

    output logic        pixel_valid,
    output logic [7:0]  pixel_data,
    output logic        busy,
    output logic        done
);
    typedef enum logic [1:0] {ST_IDLE, ST_RUN, ST_DRAIN} state_t;
    state_t state;

    logic [7:0] iw_l, ih_l;
    logic [6:0] ic_l, oc_l;
    logic [7:0] x_count, y_count, ic_count, oc_count;
    logic [1:0] ky_count, kx_count;

    logic req_valid_d;
    logic req_first_d;
    logic req_last_d;

    logic [15:0] plane_size_i;
    logic [17:0] channel_offset_i;
    logic [7:0] row_index_i, column_index_i;
    logic [15:0] row_offset_i;
    logic [17:0] fm_addr_calc;
    logic [15:0] weight_addr_calc;

    logic mac_valid_in;

    assign busy = (state != ST_IDLE);
    assign mac_valid_in = req_valid_d;

    always_comb begin
        fm_rd_en = (state == ST_RUN);
        weight_rd_en = (state == ST_RUN);
        mult_rd_en = (state == ST_RUN);

        plane_size_i = {8'd0, iw_l} * {8'd0, ih_l};
        channel_offset_i = {10'd0, ic_count} * {2'd0, plane_size_i};
        row_index_i = y_count + ky_count;
        column_index_i = x_count + kx_count;
        row_offset_i = {8'd0, row_index_i} * {8'd0, iw_l};
        fm_addr_calc = channel_offset_i + {2'd0, row_offset_i} + {10'd0, column_index_i};
        weight_addr_calc = ((({8'd0, oc_count} * {9'd0, ic_l}) + {8'd0, ic_count}) * 16'd9)
                         + (ky_count * 16'd3) + kx_count;

        fm_rd_addr = fm_addr_calc[15:0];
        weight_rd_addr = weight_addr_calc;
        mult_rd_addr = oc_count[6:0];
    end

    mac_requant_pipeline #(.ZERO_POINT(ZERO_POINT)) mac_pipe (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(mac_valid_in),
        .pixel_in(fm_rd_data),
        .weight_in(weight_rd_data),
        .first_in(req_first_d),
        .last_in(req_last_d),
        .multiplier_in(mult_rd_data),
        .pixel_valid(pixel_valid),
        .pixel_out(pixel_data)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            iw_l        <= '0;
            ih_l        <= '0;
            ic_l        <= '0;
            oc_l        <= '0;
            x_count     <= '0;
            y_count     <= '0;
            ic_count    <= '0;
            oc_count    <= '0;
            ky_count    <= '0;
            kx_count    <= '0;
            req_valid_d <= 1'b0;
            req_first_d <= 1'b0;
            req_last_d  <= 1'b0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;
            req_valid_d <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        iw_l     <= input_width;
                        ih_l     <= input_height;
                        ic_l     <= input_channels;
                        oc_l     <= output_channels;
                        x_count  <= '0;
                        y_count  <= '0;
                        ic_count <= '0;
                        oc_count <= '0;
                        ky_count <= '0;
                        kx_count <= '0;
                        state    <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    // The feature-map RAM, weight ROM and multiplier ROM register
                    // these addresses on this edge. The tags are delayed alongside them.
                    req_valid_d <= 1'b1;
                    req_first_d <= (ic_count == 0) && (ky_count == 0) && (kx_count == 0);
                    req_last_d  <= (ic_count == ic_l - 1) && (ky_count == 2) && (kx_count == 2);

                    if (kx_count < 2) begin
                        kx_count <= kx_count + 1'b1;
                    end else begin
                        kx_count <= 0;
                        if (ky_count < 2) begin
                            ky_count <= ky_count + 1'b1;
                        end else begin
                            ky_count <= 0;
                            if (ic_count < ic_l - 1) begin
                                ic_count <= ic_count + 1'b1;
                            end else begin
                                ic_count <= 0;
                                if (x_count < iw_l - 3) begin
                                    x_count <= x_count + 1'b1;
                                end else begin
                                    x_count <= 0;
                                    if (y_count < ih_l - 3) begin
                                        y_count <= y_count + 1'b1;
                                    end else begin
                                        y_count <= 0;
                                        if (oc_count < oc_l - 1) begin
                                            oc_count <= oc_count + 1'b1;
                                        end else begin
                                            state <= ST_DRAIN;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                ST_DRAIN: begin
                    // Wait until the final requantized pixel has emerged from the MAC pipe.
                    if (pixel_valid) begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
