# program_hw.tcl —— 实验三烧写（JTAG + hw_server localhost:3270）
# 用法（Vivado Tcl 或 batch）：source vivado/program_hw.tcl
set BIT {D:/HLS/HLS-experiment/lab3_/vivado/lab3_nn_prj/lab3_nn_prj.runs/impl_1/lab3_nn_top.bit}

if {![file exists $BIT]} { error "找不到比特流: $BIT" }
puts "BIT: $BIT  ([file size $BIT] bytes)"

open_hw_manager
connect_hw_server -url localhost:3270 -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
puts "DEVICE: $dev"
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $BIT $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "=== PROGRAM DONE ==="
