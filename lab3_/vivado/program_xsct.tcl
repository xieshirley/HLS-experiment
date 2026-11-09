# program_xsct.tcl —— 用 xsct/xsdb 烧写（绕过 Vivado 硬件管理器）
connect
after 1000
targets
fpga -file {D:/HLS/HLS-experiment/lab3_/vivado/lab3_nn_prj/lab3_nn_prj.runs/impl_1/lab3_nn_top.bit}
after 3000
puts "PROGRAM_DONE"
disconnect
exit
