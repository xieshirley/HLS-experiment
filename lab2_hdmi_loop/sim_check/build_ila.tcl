open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
open_run impl_1
puts "=== ???pixel_clk ??==="
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -group pixel_clk]]
puts "PIXEL_WNS=$wns"
puts "=== ?? ==="
set rpt [report_utilization -return_string]
puts [regexp -all -inline -line {.*(Slice LUTs\*|Slice Registers|Block RAM Tile|RAMB18E1).*} $rpt]
puts "BATCH_DONE"