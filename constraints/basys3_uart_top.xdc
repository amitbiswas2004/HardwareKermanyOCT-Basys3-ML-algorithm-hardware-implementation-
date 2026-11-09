## Digilent Basys 3 / XC7A35T-1CPG236C constraints
## 100 MHz oscillator, center pushbutton reset, USB-UART RX, LEDs 0..3.
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports clk100mhz]
create_clock -add -name sys_clk -period 10.000 -waveform {0.000 5.000} [get_ports clk100mhz]

set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports btnC]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports uart_rxd]

set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## uart_rxd is asynchronous; it is synchronized in uart_rx_8n1.
set_false_path -from [get_ports uart_rxd]
set_false_path -from [get_ports btnC]
