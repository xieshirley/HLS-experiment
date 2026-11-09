# build_nn.tcl —— 实验三全链路工程（UART 解帧 + HLS IP + argmax + 数码管）
set root  "D:/HLS/HLS-experiment/lab3_"
set proj  "$root/vivado/lab3_nn_prj"
set ipdir "$root/hls/nn_accel/nn_accel/solution1/impl/ip"

create_project -force lab3_nn_prj $proj -part xc7a35tfgg484-2
add_files "$root/rtl/uart_rx.v"
add_files "$root/rtl/uart_tx.v"
add_files "$root/rtl/seg_display.v"
add_files "$root/rtl/frame_decode.v"
add_files "$root/rtl/lab3_nn_top.v"
add_files -fileset constrs_1 "$root/vivado/lab3_top.xdc"

set_property ip_repo_paths $ipdir [current_project]
update_ip_catalog
create_ip -name nn_top -vendor xilinx.com -library hls -version 1.0 -module_name nn_top_0
generate_target all [get_ips nn_top_0]

set_property top lab3_nn_top [current_fileset]
update_compile_order -fileset sources_1
puts "PROJECT_READY"

launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH_PROGRESS=[get_property PROGRESS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "SYNTH FAILED" }
open_run synth_1
puts "SYNTH_OK"

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL_PROGRESS=[get_property PROGRESS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { error "IMPL FAILED" }
puts "IMPL_OK"
puts "BITSTREAM_DONE"
exit
