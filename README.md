# HardwareKermanyOCT – Basys 3 optimized pipelined RTL

This project is derived exclusively from the supplied `rtl_ok/` source set. It targets the Digilent Basys 3 board's Artix-7 **XC7A35T-1CPG236C** device.

## What changed for Basys 3

- The two 63,504 x 8 feature-map banks are explicitly marked for BRAM inference.
- The largest Conv4 coefficient ROM (36,864 x 8) is explicitly marked for block ROM.
- Conv1–Conv3 coefficient ROMs, the packed dense-weight ROM, and multiplier/bias tables are explicitly marked for distributed ROM. This avoids exceeding the Basys 3's 50 BRAM36 blocks with the original placement strategy.
- Convolution accumulation is reduced to 24 signed bits, dense accumulation to 25 signed bits, and Q24 multipliers to 18 signed bits. `scripts/check_basys3_bounds.py` checks these widths against the exact supplied coefficient memories.
- The convolution compute schedule still uses one MAC lane. It is deliberately serial and low-resource; this is not a throughput-optimized multi-lane accelerator.
- A Basys 3 wrapper accepts image bytes through the on-board USB-UART bridge and displays the class on LEDs.

## CNN datapath

`128x128x1 -> Conv1(16) -> ReLU -> Pool -> Conv2(32) -> ReLU -> Pool -> Conv3(64) -> ReLU -> Pool -> Conv4(64) -> ReLU -> Pool -> 2304-feature dense -> 4-class argmax`.

The four pools retain floor-sized 2x2 behavior. The first pooled tensor is 63x63x16; the final pooled tensor is 6x6x64 = 2304 features.

## Basys 3 board interface

Synthesis top: `basys3_uart_top`.

- Clock: 100 MHz oscillator on W5.
- Reset: center pushbutton `btnC` (active-high; wrapper converts to active-low core reset).
- UART input: USB-UART RX on B18, 115200 baud, 8 data bits, no parity, 1 stop bit.
- LED[1:0]: class code (`00` CNV, `01` DME, `10` DRUSEN, `11` NORMAL).
- LED[2]: latched result-ready indicator.
- LED[3]: `input_ready` (high while accepting a frame).

The UART wrapper accepts exactly 16,384 raw bytes in row-major order per image. Send the bytes from a `.mem` file using:

```bash
python -m pip install pyserial
python scripts/send_image_uart.py simulation/testbench_vectors/tb_img_CNV_expected_CNV.mem COM5
```

Replace `COM5` with the serial port shown by your operating system. The host script converts each hexadecimal line to one raw byte before transmitting. Send one frame at a time; wait for LED[2] before sending the next frame. The receiver intentionally has no flow-control channel because the core accepts a frame and then runs inference before accepting another.

## Build in Vivado

1. Extract this ZIP while preserving the `rtl/`, `memory/`, `simulation/`, `constraints/` and `scripts/` folders.
2. From the extracted project directory, run:

   ```tcl
   vivado -mode batch -source scripts/create_basys3_project.tcl
   ```

3. Open `vivado_project/HardwareKermanyOCT_Basys3.xpr`.
4. Confirm the part is `xc7a35tcpg236-1`, synthesis top is `basys3_uart_top`, and `constraints/basys3_uart_top.xdc` is enabled.
5. Run **Run Synthesis**, then **Run Implementation**. Inspect `report_utilization` and `report_timing_summary`.
6. Do not program the board until there are no critical synthesis errors, all required I/O pins are constrained, and timing passes at the 10 ns clock target.

The core testbench top is `cnn_accuracy_tb`. In Vivado, choose it as the simulation top when running the four-image behavioral test. The testbench uses `simulation/testbench_vectors/`; the ROMs use `memory/`. Ensure both folders are visible from the simulator's working directory if the simulator reports a missing `$readmemh` file.

Icarus Verilog can be used as an additional open-source check:

```bash
bash simulation/run_iverilog.sh
```

## Resource estimate

See [`BASYS3_RESOURCE_ESTIMATE.md`](BASYS3_RESOURCE_ESTIMATE.md). The estimated planned use is approximately 41 of 50 BRAM36 blocks, about 259 Kibit of the device's 400 Kibit maximum distributed RAM (plus a small pool buffer), and roughly 7 DSP48E1s for the main CNN arithmetic. These are architectural estimates, not Vivado measurements. Actual packing, LUTRAM mapping, DSP inference and timing must be confirmed by synthesis and implementation on the target part.

## Verification status and limitations

- `scripts/check_reference_predictions.py`: checks the software fixed-point reference against all four provided image vectors; this is not RTL simulation.
- `scripts/check_basys3_bounds.py`: verifies the reduced accumulator and multiplier widths against the checked-in fixed `.mem` files.
- `scripts/export_mem.py`: validates source coefficient memories and recreates the packed dense ROM from `reference/bit_true_hw_files/`.
- `simulation/cnn_accuracy_tb.sv`: end-to-end HDL testbench supplied for Vivado/ Icarus; HDL simulation has not been run in this environment because no HDL simulator or Vivado installation is available here.
- No Vivado synthesis, place-and-route, timing closure or board programming has been performed. Do not interpret the resource estimates as a synthesis pass or a guarantee that the FPGA will not fail.

The original RTL's convolution zero-point default of 0 and dense zero-point of 86 are retained. `model.py` prints the quantized convolution output zero-points, but those values are not serialized into the provided coefficient memories. Confirm the printed convolution zero-points before claiming exact agreement with the PyTorch quantized model.
