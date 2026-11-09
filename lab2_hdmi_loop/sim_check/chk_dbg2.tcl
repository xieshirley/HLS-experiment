open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
open_run impl_1
puts "=== debug cores (filter TYPE) ==="
foreach c [get_debug_cores] { puts "CORE=$c" }
puts "--- hub ---"
foreach h [get_debug_cores -filter {TYPE == dbg_hub}] {
    puts "HUB=$h"
    puts "  USER_SCAN_CHAIN=[get_property C_USER_SCAN_CHAIN $h]"
    set p [get_pins -of_objects $h -filter {REF_PIN_NAME == clk}]
    puts "  HUB_CLK_PIN=$p"
    if {[llength $p]} { puts "  HUB_CLK_NET=[get_nets -of_objects $p]" }
}
puts "--- ila ---"
foreach i [get_debug_cores -filter {TYPE == ila}] { puts "ILA=$i" }
puts "BATCH_DONE"