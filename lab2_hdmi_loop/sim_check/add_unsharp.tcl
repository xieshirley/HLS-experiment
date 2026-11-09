open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
set files [list \
  D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs/sources_1/imports/hls/unsharp3x3/unsharp3x3.v \
  D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs/sources_1/imports/hls/unsharp3x3/unsharp3x3_wlb_lbbkb.v \
  D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs/sources_1/imports/hls/unsharp3x3/unsharp3x3_wlb_lbdEe.v ]
foreach f $files {
  if {[llength [get_files -quiet $f]] == 0} { add_files -norecurse $f; puts "ADDED $f" }
}
update_compile_order -fileset sources_1
puts "UNSHARP_FILES=[llen [get_files -of_objects [get_filesets sources_1] -filter {NAME =~ *unsharp*}]]"
puts "BATCH_DONE"