# Source after opening the created project, or run from Vivado batch mode.
# Example: vivado -mode batch -source scripts/create_basys3_project.tcl
# Then open the .xpr and launch synthesis/implementation in the GUI.
# This script can also be sourced from the Tcl console after project creation.
if {[current_project -quiet] eq ""} {
    error "Open HardwareKermanyOCT_Basys3.xpr first, then source this script."
}
set_property top basys3_uart_top [current_fileset]
update_compile_order -fileset sources_1
synth_design -top basys3_uart_top -part xc7a35tcpg236-1
report_utilization -file [file join [get_property DIRECTORY [current_project]] basys3_utilization_synth.rpt]
report_timing_summary -file [file join [get_property DIRECTORY [current_project]] basys3_timing_synth.rpt]
