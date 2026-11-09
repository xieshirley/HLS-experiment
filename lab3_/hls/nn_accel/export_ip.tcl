# export_ip.tcl —— 把 nn_top 导出为 Vivado IP（ip_catalog），供集成工程例化
open_project nn_accel
open_solution solution1
export_design -format ip_catalog -description "MNIST int8 fixed-point neural network accelerator"
puts "IP_EXPORTED"
exit
