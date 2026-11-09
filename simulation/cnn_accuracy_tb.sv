`timescale 1ns/1ps

module cnn_accuracy_tb;
    localparam integer IMAGE_PIXELS = 128 * 128;
    localparam integer MAX_WAIT_CYCLES = 50_000_000;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic input_valid = 1'b0;
    logic [7:0] input_pixel = 8'd0;
    logic input_ready;
    logic output_valid;
    logic [1:0] output_class;
    wire signed [31:0] output_logits [0:3];
    logic signed [31:0] output_logit0;
    logic signed [31:0] output_logit1;
    logic signed [31:0] output_logit2;
    logic signed [31:0] output_logit3;

    logic [7:0] test_image [0:IMAGE_PIXELS-1];
    integer total_images = 0;
    integer correct_ground_truth = 0;
    integer correct_software_prediction = 0;
    integer timeout_cycles;

    cnn_top dut (
        .clk(clk), .rst_n(rst_n), .input_valid(input_valid), .input_pixel(input_pixel),
        .input_ready(input_ready), .output_valid(output_valid), .output_class(output_class),
        .output_logits(output_logits), .output_logit0(output_logit0), .output_logit1(output_logit1),
        .output_logit2(output_logit2), .output_logit3(output_logit3)
    );

    always #5 clk = ~clk;

    function automatic [8*6-1:0] class_name(input integer class_index);
        case (class_index)
            0: class_name = "CNV";
            1: class_name = "DME";
            2: class_name = "DRUSEN";
            3: class_name = "NORMAL";
            default: class_name = "UNKNOWN";
        endcase
    endfunction

    task automatic run_image;
        input [8*100-1:0] filename;
        input integer ground_truth;
        input integer software_prediction;
        integer pixel_index;
        integer wait_cycles;
        begin
            $display("Loading %0s", filename);
            $readmemh(filename, test_image);

            rst_n = 1'b0;
            input_valid = 1'b0;
            input_pixel = 8'd0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;

            for (pixel_index = 0; pixel_index < IMAGE_PIXELS; pixel_index = pixel_index + 1) begin
                @(negedge clk);
                while (!input_ready)
                    @(negedge clk);
                input_pixel = test_image[pixel_index];
                input_valid = 1'b1;
                @(negedge clk);
                input_valid = 1'b0;
            end

            wait_cycles = 0;
            while (!output_valid) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > MAX_WAIT_CYCLES)
                    $fatal(1, "Timeout waiting for output from %0s", filename);
            end
            @(negedge clk);

            total_images = total_images + 1;
            if (output_class == ground_truth)
                correct_ground_truth = correct_ground_truth + 1;
            if (output_class == software_prediction)
                correct_software_prediction = correct_software_prediction + 1;

            $display("  ground truth: %0s (%0d), software: %0s (%0d), RTL: %0s (%0d)",
                     class_name(ground_truth), ground_truth,
                     class_name(software_prediction), software_prediction,
                     class_name(output_class), output_class);
            $display("  logits: %0d, %0d, %0d, %0d; processing cycles: %0d",
                     output_logit0, output_logit1, output_logit2, output_logit3, wait_cycles);
        end
    endtask

    initial begin
        run_image("simulation/testbench_vectors/tb_img_CNV_expected_CNV.mem", 0, 0);
        run_image("simulation/testbench_vectors/tb_img_DME_expected_DME.mem", 1, 1);
        run_image("simulation/testbench_vectors/tb_img_DRUSEN_expected_DRUSEN.mem", 2, 2);
        run_image("simulation/testbench_vectors/tb_img_NORMAL_expected_NORMAL.mem", 3, 3);

        $display("");
        $display("RTL accuracy: %0d/%0d = %0.2f%% against ground truth",
                 correct_ground_truth, total_images,
                 100.0 * correct_ground_truth / total_images);
        $display("RTL agreement: %0d/%0d = %0.2f%% against software predictions",
                 correct_software_prediction, total_images,
                 100.0 * correct_software_prediction / total_images);
        $finish;
    end
endmodule
