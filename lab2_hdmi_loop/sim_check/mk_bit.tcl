open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
open_run impl_1
write_bitstream -force D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.runs/impl_1/hdmi_loop.bit
puts "BIT_DONE"
puts "=== ???? ==="
puts [get_property STATS.WNS [current_design]]