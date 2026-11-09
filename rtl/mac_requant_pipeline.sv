// One 9x8 signed MAC lane followed by a 24x18 Q24 requantization multiply.
// Widths are proven by scripts/check_basys3_bounds.py for the supplied fixed weights.
module mac_requant_pipeline #(
    parameter integer ZERO_POINT = 0
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                valid_in,
    input  logic [7:0]          pixel_in,
    input  logic signed [7:0]   weight_in,
    input  logic                first_in,
    input  logic                last_in,
    input  logic signed [17:0]  multiplier_in,
    output logic                pixel_valid,
    output logic [7:0]          pixel_out
);
    logic signed [8:0] pixel_s;
    (* use_dsp = "yes" *) logic signed [16:0] product_d;
    logic product_valid_d;
    logic first_d, last_d;
    logic signed [17:0] multiplier_d;

    logic signed [23:0] accumulator;
    logic signed [23:0] sum_next;
    (* use_dsp = "yes" *) logic signed [41:0] scaled_d;
    logic scaled_valid_d;
    logic signed [41:0] shifted_value;

    assign pixel_s = $signed({1'b0, pixel_in});

    always_comb begin
        if (first_d)
            sum_next = {{7{product_d[16]}}, product_d};
        else
            sum_next = accumulator + {{7{product_d[16]}}, product_d};
        shifted_value = (scaled_d >>> 24) + ZERO_POINT;
    end

    function automatic logic [7:0] saturate_u8(input logic signed [41:0] value);
        begin
            if (value < 0)
                saturate_u8 = 8'd0;
            else if (value > 255)
                saturate_u8 = 8'd255;
            else
                saturate_u8 = value[7:0];
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_d       <= '0;
            product_valid_d <= 1'b0;
            first_d         <= 1'b0;
            last_d          <= 1'b0;
            multiplier_d    <= '0;
            accumulator     <= '0;
            scaled_d        <= '0;
            scaled_valid_d  <= 1'b0;
            pixel_valid     <= 1'b0;
            pixel_out       <= '0;
        end else begin
            product_valid_d <= valid_in;
            scaled_valid_d  <= 1'b0;
            pixel_valid     <= scaled_valid_d;

            if (valid_in) begin
                product_d    <= pixel_s * weight_in;
                first_d      <= first_in;
                last_d       <= last_in;
                multiplier_d <= multiplier_in;
            end

            if (product_valid_d) begin
                if (last_d) begin
                    scaled_d       <= sum_next * multiplier_d;
                    scaled_valid_d <= 1'b1;
                    accumulator    <= '0;
                end else begin
                    accumulator <= sum_next;
                end
            end

            if (scaled_valid_d)
                pixel_out <= saturate_u8(shifted_value);
        end
    end
endmodule
