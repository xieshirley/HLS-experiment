# run_hls.tcl —— 实验三 HLS 推理核流程（2018.3）
# 用法（完全权限下）： pwsh scripts/hls_run.ps1 -Tcl hls/nn_accel/run_hls.tcl
open_project -reset nn_accel
add_files nn.cpp
add_files -tb tb_nn.cpp
set_top nn_top
open_solution -reset solution1
set_part {xc7a35tfgg484-2}
create_clock -period 20 -name default

# G4：定点 C 仿真（与 python/quantize.py 逐位对拍）
csim_design

# G5：C 综合（读 II / DSP / 时序报告）
csynth_design

# cosim_design -rtl verilog
# export_design -format ip_catalog

exit
