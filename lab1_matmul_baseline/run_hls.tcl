# =====================================================================
# run_hls.tcl —— Vivado HLS 2018.3 命令行脚本（本目录内运行）
# 用法：在 Vivado HLS 2018.3 命令行窗口中执行   vivado_hls -f run_hls.tcl
# 说明：初学者建议先按《实验指导书》用 GUI 手动建工程，
#       熟悉后再用本脚本做批量/可复现实验。
# 注：本脚本在 Vivado HLS 2018.3 实测通过；其它工具版本如报参数错误，按提示微调即可
# =====================================================================

set proj_name  "proj_v0_baseline"     ;# 工程名（各版本目录内不同）
set top_name   "matmul_top"
set part_name  "xc7a100tcsg324-1"      ;# 目标器件：Artix-7 100T（2018.3 实测器件；如换实验室器件请修改此处）
set clk_period 10                     ;# 时钟周期 ns（10ns 即 100MHz）

open_project -reset ${proj_name}
add_files matmul.cpp
add_files -tb matmul_tb.cpp
set_top ${top_name}

open_solution -reset solution1
set_part ${part_name}
create_clock -period ${clk_period} -name default

# ---------- 1) C 仿真：先验证功能正确性 ----------
csim_design -clean

# ---------- 2) C 综合：生成 RTL，输出延迟/II/资源报告 ----------
csynth_design

# ---------- 3) 协同仿真（可选）：验证 RTL 功能，耗时较长 ----------
# cosim_design -rtl verilog

# 本实验只做软件侧验证与综合，不需要 export_design（导出 IP）。

exit
