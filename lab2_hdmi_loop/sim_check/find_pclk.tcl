open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
open_run impl_1
puts "=== pixel_clk ?? / ??? ==="
foreach n [get_nets -hier -filter {NAME =~ *pixel_clk*}] { puts "NET: $n" }
foreach p [get_pins -of_objects [get_nets -hier -filter {NAME =~ *pixel_clk }] -filter {DIRECTION == OUT}] { puts "DRV PIN: $p  CELL=[get_property REF_NAME [get_cells -of_objects $p]]" }
foreach p [get_pins -of_objects [get_nets -hier -filter {NAME =~ *pclk*}] -filter {DIRECTION == OUT}] { puts "PCLK DRV: $p  CELL=[get_property REF_NAME [get_cells -of_objects $p]]" }
puts "=== DONE ==="