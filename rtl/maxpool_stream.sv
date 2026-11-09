// Streaming 2x2 max-pool. Input pixels must arrive channel-major, row-major.
// Odd trailing rows/columns are discarded, matching floor(H/2), floor(W/2).
module maxpool_stream #(
    parameter integer MAX_POOL_COLS = 63
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [7:0]  input_width,
    input  logic [7:0]  input_height,
    input  logic [6:0]  channels,
    input  logic        pixel_valid,
    input  logic [7:0]  pixel_data,
    output logic        out_valid,
    output logic [15:0] out_addr,
    output logic [7:0]  out_data,
    output logic        busy,
    output logic        done
);
    logic [7:0] width_l, height_l;
    logic [6:0] channels_l;
    logic [7:0] x_count, y_count, ch_count;
    logic [7:0] left_pixel;
    logic [7:0] previous_row_pair_max [0:MAX_POOL_COLS-1];
    logic [7:0] horizontal_max;
    logic [7:0] pooled_max;
    logic [6:0] pool_width_i, pool_height_i;
    logic [12:0] pool_plane_size_i;
    logic [17:0] out_addr_calc;
    logic active;

    assign busy = active;

    always_comb begin
        horizontal_max = (pixel_data > left_pixel) ? pixel_data : left_pixel;
        pooled_max = (horizontal_max > previous_row_pair_max[x_count >> 1])
                   ? horizontal_max : previous_row_pair_max[x_count >> 1];
        pool_width_i  = width_l >> 1;
        pool_height_i = height_l >> 1;
        pool_plane_size_i = {6'd0, pool_width_i} * {6'd0, pool_height_i};
        out_addr_calc = ({10'd0, ch_count} * {5'd0, pool_plane_size_i})
                      + ({10'd0, (y_count >> 1)} * {11'd0, pool_width_i})
                      + {10'd0, (x_count >> 1)};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            width_l  <= '0;
            height_l <= '0;
            channels_l <= '0;
            x_count <= '0;
            y_count <= '0;
            ch_count <= '0;
            left_pixel <= '0;
            active <= 1'b0;
            out_valid <= 1'b0;
            out_addr <= '0;
            out_data <= '0;
            done <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            done <= 1'b0;

            if (start) begin
                width_l   <= input_width;
                height_l  <= input_height;
                channels_l <= channels;
                x_count   <= '0;
                y_count   <= '0;
                ch_count  <= '0;
                active    <= 1'b1;
            end else if (active && pixel_valid) begin
                if (!x_count[0]) begin
                    left_pixel <= pixel_data;
                end else begin
                    if (!y_count[0]) begin
                        previous_row_pair_max[x_count >> 1] <= horizontal_max;
                    end else begin
                        out_valid <= 1'b1;
                        out_addr  <= out_addr_calc[15:0];
                        out_data  <= pooled_max;
                    end
                end

                if (x_count == width_l - 1) begin
                    x_count <= '0;
                    if (y_count == height_l - 1) begin
                        y_count <= '0;
                        if (ch_count == channels_l - 1) begin
                            ch_count <= '0;
                            active <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            ch_count <= ch_count + 1'b1;
                        end
                    end else begin
                        y_count <= y_count + 1'b1;
                    end
                end else begin
                    x_count <= x_count + 1'b1;
                end
            end
        end
    end
endmodule
