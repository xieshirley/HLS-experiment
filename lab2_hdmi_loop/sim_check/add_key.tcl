open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
set f D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs/sources_1/new/key_mode.v
if {[llength [get_files -quiet $f]] == 0} { add_files -norecurse $f; puts "ADDED key_mode.v" }
update_compile_order -fileset sources_1
puts "KEYFILE=[llen [get_files -of_objects [get_filesets sources_1] -filter {NAME =~ *key_mode*}]]"
puts "DONE"