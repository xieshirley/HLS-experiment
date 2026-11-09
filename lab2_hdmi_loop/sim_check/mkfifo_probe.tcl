open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
if {[llength [get_ips -quiet sync_fifo_2x4096]] == 0} {
    create_ip -name fifo_generator -vendor xilinx.com -library ip -module_name sync_fifo_2x4096
}
set ip [get_ips sync_fifo_2x4096]
puts "VLNV=[get_property IPDEF $ip]"
puts "=== relevant CONFIG properties ==="
foreach p [list_property $ip] {
    if {[string match "CONFIG.*" $p]} {
        set low [string tolower $p]
        if {[string match "*implementation*" $low] || [string match "*depth*" $low] || \
            [string match "*data_width*" $low] || [string match "*performance*" $low] || \
            [string match "*data_count*" $low] || [string match "*clock_type*" $low] || \
            [string match "*reset*" $low] || [string match "*interface_type*" $low]} {
            puts "  $p = [get_property $p $ip]"
        }
    }
}
puts "=== DONE ==="