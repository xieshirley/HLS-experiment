# build_loopback.tcl —— 实验三 UART 回环里程碑：建工程 + 综合 + 实现 + bit
set root "D:/HLS/HLS-experiment/lab3_"
set proj "$root/vivado/lab3_prj"
create_project -force lab3_prj $proj -part xc7a35tfgg484-2
add_files "$root/rtl/uart_rx.v"
add_files "$root/rtl/uart_tx.v"
add_files "$root/rtl/seg_display.v"
add_files "$root/rtl/lab3_top.v"
add_files -fileset constrs_1 "$root/vivado/lab3_top.xdc"
set_property top lab3_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "SYNTH FAILED: [get_property PROGRESS [get_runs synth_1]]"
}
open_run synth_1
puts "SYNTH_OK"
puts [report_utilization -return_string]

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "IMPL FAILED: [get_property PROGRESS [get_runs impl_1]]"
}
puts "IMPL_OK"
puts "WNS: [get_property STATS.WNS [get_designs impl_1]]"
puts "BITSTREAM_DONE"
exit
