# ============================================================
# program_hw_xsct.tcl ?? ??? Vivado GUI ?????????
#   ???
#     D:\software\vivado18_3\systemfile\SDK\2018.3\bin\xsct.bat program_hw_xsct.tcl
#   ???hw_server ?? 3270 ??????? start_hw_server.bat?
#   ???xsct ??? connect ???? hw_server ? 3121?
#         ? 3121 ?? Windows ??????? -> ??????? -url ?? 3270
# ============================================================
set BIT  {D:/HLS/HLS-experiment/lab2_hdmi_loop/bit_out/hdmi_loop_V11_MODE_key_runtime.bit}
set HWS  tcp:127.0.0.1:3270

connect -url $HWS
puts "--- targets ---"
foreach t [targets] { puts "  $t" }

set dev [lindex [targets] 0]
if {$dev eq ""} { error "?? JTAG ????????? / JTAG ? / Digilent ??" }

targets -set -filter {name =~ "*xc7a35t*"}
fpga -file $BIT
puts "=== PROGRAM DONE (xsct) ==="
exit