module argmax (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic signed [31:0] logit0,
    input  logic signed [31:0] logit1,
    input  logic signed [31:0] logit2,
    input  logic signed [31:0] logit3,
    output logic [1:0] class_index,
    output logic done
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            class_index <= 2'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                if ((logit0 >= logit1) && (logit0 >= logit2) && (logit0 >= logit3))
                    class_index <= 2'd0;
                else if ((logit1 >= logit2) && (logit1 >= logit3))
                    class_index <= 2'd1;
                else if (logit2 >= logit3)
                    class_index <= 2'd2;
                else
                    class_index <= 2'd3;
                done <= 1'b1;
            end
        end
    end
endmodule
