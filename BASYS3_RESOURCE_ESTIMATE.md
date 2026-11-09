# Basys 3 target assessment (XC7A35T-1CPG236C)

## Device ceiling

The Basys 3 board uses the Artix-7 XC7A35T-1CPG236C. The device provides 50 RAMB36-equivalent block-RAM blocks (1,800 Kb), 90 DSP48E1 slices, 20,800 LUTs and up to 400 Kb of distributed RAM. Confirmed against Digilent's Basys 3 product/reference material and AMD DS180.

## Deliberate memory placement in this build

| Memory | Depth x width | Intended implementation | Estimated resource |
|---|---:|---|---:|
| Feature-map bank 0 | 63,504 x 8 | BRAM36 | 16 blocks |
| Feature-map bank 1 | 63,504 x 8 | BRAM36 | 16 blocks |
| Conv1 weights | 144 x 8 | Distributed ROM | 1,152 bits |
| Conv2 weights | 4,608 x 8 | Distributed ROM | 36,864 bits |
| Conv3 weights | 18,432 x 8 | Distributed ROM | 147,456 bits |
| Conv4 weights | 36,864 x 8 | Block ROM | 9 blocks |
| Dense packed weights | 2,304 x 32 | Distributed ROM | 73,728 bits |
| Per-channel multipliers, dense bias/multiplier | 181 x 32 | Distributed ROM | 5,792 bits |
| Pooling row buffer | 63 x 8 | Registers/LUTRAM | 504 bits |

**Estimated BRAM use: 41 / 50 blocks**, leaving about 9 blocks before other synthesis effects. This assumes each 8-bit, 63,504-deep feature-map memory maps as 16 RAMB36 blocks and the 36,864-deep Conv4 ROM maps as 9 RAMB36 blocks. Actual Vivado results are authoritative.

The deliberately distributed coefficient memories total approximately **264,992 bits (about 259 Kibit)**. Including the 504-bit pooling row buffer, the planned distributed storage is about 265.5 Kibit, around 65% of the device's 400-Kibit maximum distributed-RAM capacity. Considering the 64-bit depth granularity of LUTRAMs and the separate ROM instances, a rough mapping is about **4,256 LUTRAM cells** versus approximately 6,400 LUTRAM-capable LUTs on the device (about 66.5%). This is a significant SLICEM/LUTRAM allocation; inspect both `Block RAM Tile` and `LUT as Distributed RAM` in `report_utilization`.

## Arithmetic narrowing

The supplied fixed `.mem` files were examined with `scripts/check_basys3_bounds.py`. It proves conservative absolute-sum bounds for every output channel with unsigned 8-bit inputs:

- Maximum Conv4 accumulator magnitude: 7,060,440; signed 24-bit maximum is 8,388,607.
- Maximum dense accumulator magnitude including bias: 12,561,662; signed 25-bit maximum is 16,777,215.
- Maximum absolute Q multiplier: 76,935; signed 18-bit maximum is 131,071.

Therefore this build uses 24-bit convolution accumulators, 25-bit dense accumulators, and 18-bit Q24 multipliers for the exact supplied coefficient files. If any weights, biases or multipliers are regenerated, rerun the bounds script before using these narrowed widths.

The main datapath multipliers are sized to fit the DSP48E1 25x18 multiplier shape: four 9x8 dense MAC products, one 25x18 dense requantization product, one 9x8 convolution product and one 24x18 convolution requantization product. This suggests roughly 7 DSP48E1s for the principal CNN arithmetic; address arithmetic and mapping may alter the final count.

## Expected runtime

The one-lane convolution schedule processes 39,191,616 convolution multiply-accumulate terms per frame. At a 100 MHz clock, the raw arithmetic lower bound is about 0.392 seconds per image, before address, pipeline-drain and controller overhead. The UART transfer itself takes about 1.42 seconds for 16,384 bytes at 115,200 baud, 8-N-1.

## What is and is not verified

- The 4 provided memory-vector files reproduce their expected class using the Python fixed-point reference checker.
- The width-bound script passes for the current memory files.
- The dense weight packing is reproducible from the original `rtl_ok/bit_true_hw_files`.
- No Vivado synthesis, implementation, timing closure or board programming was run in this environment. The resource estimates above are structural projections, not measured utilization. Run synthesis for `xc7a35tcpg236-1` and inspect the reports before programming.

The CNN core's original conv zero-point default of 0 and dense zero-point of 86 are retained. `model.py` prints each convolution output zero-point but the export files do not contain those values; bit-exact PyTorch quantized inference therefore still requires confirming those printed values.
