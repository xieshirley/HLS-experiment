open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
set ip [get_ips sync_fifo_2x4096]
set_property -dict [list CONFIG.Data_Count {true}] $ip
set_property -dict [list CONFIG.Read_Data_Count {true} CONFIG.Read_Data_Count_Width {13} CONFIG.Write_Data_Count {false}] $ip
generate_target {instantiation_template synthesis simulation} $ip
puts "=== RESULT ==="
foreach p {CONFIG.Data_Count CONFIG.Read_Data_Count CONFIG.Read_Data_Count_Width CONFIG.Input_Data_Width CONFIG.Input_Depth CONFIG.Performance_Options CONFIG.Reset_Type} {
    puts "$p = [get_property $p $ip]"
}
puts "=== VEO PORTS ==="
set fh [open [lindex [glob D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs/sources_1/ip/sync_fifo_2x4096/*.veo] 0] r]
set txt [read $fh]; close $fh
set s [string first "INST_TAG\n" $txt]; set e [string first "INST_TAG_END" $txt]
puts [string range $txt $s $e]
puts "=== DONE ==="