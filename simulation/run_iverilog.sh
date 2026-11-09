#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

iverilog -g2012 -s cnn_accuracy_tb -o simulation/cnn_accuracy_tb.vvp \
  rtl/cnn_params_pkg.sv \
  rtl/feature_map_ram.sv \
  rtl/weight_rom.sv \
  rtl/weight_rom_dist.sv \
  rtl/parameter_rom.sv \
  rtl/mac_requant_pipeline.sv \
  rtl/conv_engine.sv \
  rtl/maxpool_stream.sv \
  rtl/dense_engine.sv \
  rtl/argmax.sv \
  rtl/cnn_controller.sv \
  rtl/cnn_top.sv \
  rtl/uart_rx_8n1.sv \
  rtl/basys3_uart_top.sv \
  simulation/cnn_accuracy_tb.sv

vvp simulation/cnn_accuracy_tb.vvp
