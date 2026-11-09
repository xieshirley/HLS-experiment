open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
set ip [get_ips sync_fifo_2x4096]
set_property -dict [list \
    CONFIG.INTERFACE_TYPE        {Native} \
    CONFIG.Fifo_Implementation   {Common_Clock_Block_RAM} \
    CONFIG.Input_Data_Width      {2} \
    CONFIG.Input_Depth           {4096} \
    CONFIG.Performance_Options   {First_Word_Fall_Through} \
    CONFIG.Reset_Pin             {true} \
    CONFIG.Reset_Type            {Synchronous_Reset} \
    CONFIG.Read_Data_Count       {true} \
    CONFIG.Read_Data_Count_Width {13} \
    CONFIG.Write_Data_Count      {false} \
] $ip
generate_target {instantiation_template synthesis simulation} $ip
puts "=== RESULT ==="
puts "WIDTH=[get_property CONFIG.Input_Data_Width $ip]  DEPTH=[get_property CONFIG.Input_Depth $ip]"
puts "IMPL=[get_property CONFIG.Fifo_Implementation $ip]  PERF=[get_property CONFIG.Performance_Options $ip]"
puts "=== VEO ==="
set veo [glob -nocomplain D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs/sources_1/ip/sync_fifo_2x4096/*.veo]
foreach f $veo {
    set fh [open $f r]; puts [read $fh]; close $fh
}
puts "=== DONE ==="