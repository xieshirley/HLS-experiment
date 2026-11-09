open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
open_run impl_1
puts "=== ????????148.5MHz -> 6.734ns????? ==="
if {[llength [get_clocks -quiet pixel_clk]] == 0} {
    create_clock -period 6.734 -name pixel_clk [get_nets pixel_clk]
}
update_timing -full
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts "PIXEL_WNS=$wns"
puts "=== pixel_clk ??? 5 ? ==="
foreach p [get_timing_paths -delay_type max -max_paths 5] {
    set src [get_property STARTPOINT_PIN $p]
    set dst [get_property ENDPOINT_PIN $p]
    set sl  [get_property SLACK $p]
    set lv  [get_property LOGIC_LEVELS $p]
    puts "SLACK=$sl  LOGIC=$lv  $src -> $dst"
}
puts "=== ??????? ==="
puts [report_timing_summary -return_string -no_detailed_paths -max_paths 1]
puts "BATCH_DONE"