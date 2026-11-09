open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
set f D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs/sources_1/new/video_dbg.v
if {[llength [get_files -quiet $f]] == 0} {
    add_files -norecurse $f
    puts "ADDED video_dbg.v"
}
update_compile_order -fileset sources_1
puts "FILES=[get_files -of_objects [get_filesets sources_1] -filter {NAME =~ *video_dbg*}]"
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
puts "BATCH_DONE"