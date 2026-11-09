open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
reset_run impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
puts "IMPL_PROGRESS=[get_property PROGRESS [get_runs impl_1]]"
open_run impl_1
puts "=== TIMING SUMMARY ==="
puts [report_timing_summary -delay_type min_max -max_paths 3 -return_string]
puts "=== CLOCKS ==="
puts [report_clocks -return_string]
puts "BATCH_DONE"