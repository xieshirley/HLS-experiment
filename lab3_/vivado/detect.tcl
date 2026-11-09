# detect.tcl —— 检测 JTAG 设备
open_hw_manager
connect_hw_server -url localhost:3270 -allow_non_jtag
open_hw_target
puts "HW_DEVICES=[get_hw_devices]"
foreach d [get_hw_devices] {
    puts "  DEV: $d  PART=[get_property PART $d]"
}
exit
