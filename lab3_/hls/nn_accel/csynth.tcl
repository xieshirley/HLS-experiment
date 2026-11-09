# csynth.tcl —— 仅 C 综合（G5 迭代用，csim 已验证过同一数学）
open_project -reset nn_accel
add_files nn.cpp
set_top nn_top
open_solution -reset solution1
set_part {xc7a35tfgg484-2}
create_clock -period 20 -name default
csynth_design
exit
