open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
open_run impl_1
puts "=== debug cores ==="
foreach c [get_debug_cores] {
    puts "CORE=$c  TYPE=[get_property TYPE $c]"
}
puts "=== dbg_hub ?? ==="
foreach h [get_debug_cores -filter {TYPE == dbg_hub}] {
    puts "HUB=$h"
    puts "  C_USER_SCAN_CHAIN=[get_property C_USER_SCAN_CHAIN $h]"
}
foreach i [get_debug_cores -filter {TYPE == ila}] {
    puts "ILA=$i  CLK=[get_property CLK $i]"
}
puts "=== ???? ==="
foreach n [get_nets -of_objects [get_pins -of_objects [get_debug_cores -filter {TYPE == dbg_hub}] -filter {REF_PIN_NAME == clk}]] { puts "HUB CLK NET: $n" } 
puts "BATCH_DONE"