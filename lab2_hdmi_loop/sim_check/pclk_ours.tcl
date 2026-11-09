open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
open_run impl_1
if {[llength [get_clocks -quiet pixel_clk]] == 0} {
    create_clock -period 6.734 -name pixel_clk [get_nets pixel_clk]
}
update_timing -full
puts "=== ??????????????/???? hdmi_rx ???==="
set worst 99.0
set n 0
foreach p [get_timing_paths -delay_type max -max_paths 400] {
    set src [get_property STARTPOINT_PIN $p]
    set dst [get_property ENDPOINT_PIN $p]
    set sl  [get_property SLACK $p]
    set pat $src$dst
    if {[string match "*/R" $dst] || [string match "*/S" $dst] || [string match "*/CLR" $dst]} { continue }
    if {![string match "*u_video_core*" $pat] && ![string match "*u_video_sync*" $pat]} { continue }
    incr n
    if {$n <= 6} { puts "OUR SLACK=$sl  $src -> $dst" }
    if {$sl < $worst} { set worst $sl }
}
puts "OUR_WORST_SLACK=$worst  (? $n ??? video_core/video_sync ?)"
puts "BATCH_DONE"