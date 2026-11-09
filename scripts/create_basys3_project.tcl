# Run with: vivado -mode batch -source scripts/create_basys3_project.tcl
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_dir [file join $root_dir vivado_project]

create_project -force HardwareKermanyOCT_Basys3 $project_dir -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [glob -nocomplain [file join $root_dir rtl *.sv]]
add_files -norecurse $rtl_files
set_property top basys3_uart_top [current_fileset]

add_files -fileset constrs_1 -norecurse [file join $root_dir constraints basys3_uart_top.xdc]

# Keep the memory folder at the project root because the RTL uses memory/*.mem.
set mem_files [glob -nocomplain [file join $root_dir memory *.mem]]
add_files -norecurse $mem_files
foreach f $mem_files {
    set_property file_type {Memory Initialization Files} [get_files $f]
}

add_files -fileset sim_1 -norecurse [file join $root_dir simulation cnn_accuracy_tb.sv]
set_property top cnn_accuracy_tb [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created Basys 3 project for xc7a35tcpg236-1 at $project_dir"
puts "Synthesis top: basys3_uart_top; simulation top: cnn_accuracy_tb"
puts "NOTE: Keep the memory/ folder visible from the Vivado simulation/synthesis working directory."
