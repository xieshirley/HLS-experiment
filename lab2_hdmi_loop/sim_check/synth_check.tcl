open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
puts "SYNTH_PROGRESS=[get_property PROGRESS [get_runs synth_1]]"
puts "BATCH_DONE"
