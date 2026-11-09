#=============================================================================
# program_hw.tcl —— 一次性编程：bit 与 probes(.ltx) 用同一份构建，直接烧
#   用法（Vivado 2018.3，Tcl Console）：
#       cd D:/HLS/HLS-experiment/lab2_hdmi_loop/sim_check
#       source program_hw.tcl
#
#   为什么用它：Hardware Manager 的 GUI 有时会保留"上一次"的 probes 配置，
#   于是出现
#     ERROR: [Labtools 27-3412] Mismatch between the design programmed into the
#     device ... and the probes file(s) ... hw_probe 'xxx' ... port index '4'
#   本脚本先 refresh_hw_device -update_hw_probes false（清掉残留探针），
#   再把 PROGRAM.FILE / PROBES.FILE / FULL_PROBES.FILE 一起设好才 programming。
#
#   前提：HDMI 输入要在线（dbg_hub 时钟 = pixel_clk = HDMI 恢复时钟），
#         否则会报 "debug hub core was not detected"。
#=============================================================================

set BIT {D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.runs/impl_1/hdmi_loop.bit}
set LTX {D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.runs/impl_1/debug_nets.ltx}

if {![file exists $BIT]} { error "找不到比特流: $BIT （先跑 Generate Bitstream）" }
if {![file exists $LTX]} { error "找不到探针文件: $LTX （综合/实现时没生成 debug_nets.ltx）" }

puts "BIT: $BIT  ([file size $BIT] bytes)"
puts "LTX: $LTX  ([file size $LTX] bytes)"

set HW_URL {localhost:3270}
open_hw_manager
connect_hw_server -url $HW_URL -allow_non_jtag
open_hw_target

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
puts "DEVICE: $dev"

# 关键：先刷新但不更新探针，清掉上一次会话残留的 probes
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE      $BIT $dev
set_property PROBES.FILE       $LTX $dev
set_property FULL_PROBES.FILE  $LTX $dev

program_hw_devices $dev
refresh_hw_device $dev

puts "=== PROGRAM DONE ==="
foreach c [get_hw_ilas -of_objects $dev] {
    puts "  ILA: $c"
    foreach p [get_hw_probes -of_objects $c] { puts "    PROBE: $p" }
}
puts "如果上面列出了 5 个 probe（dbg_gray_beats / dbg_gauss_beats ...），就可以在 GUI 里 Run Trigger 了"
