# create_project.tcl —— 实验三 UART 回环里程碑工程（小步闭环第 1 步）
# 用法：vivado -mode batch -source vivado/create_project.tcl
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
puts "PROJECT_CREATED"
exit
