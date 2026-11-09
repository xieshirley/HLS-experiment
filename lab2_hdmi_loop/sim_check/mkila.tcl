open_project D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr
if {[llength [get_ips -quiet dbg_ila]] == 0} {
    create_ip -name ila -vendor xilinx.com -library ip -module_name dbg_ila
}
set ip [get_ips dbg_ila]
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES  {5} \
    CONFIG.C_PROBE0_WIDTH   {1} \
    CONFIG.C_PROBE1_WIDTH   {7} \
    CONFIG.C_PROBE2_WIDTH   {16} \
    CONFIG.C_PROBE3_WIDTH   {24} \
    CONFIG.C_PROBE4_WIDTH   {24} \
    CONFIG.C_DATA_DEPTH     {1024} \
    CONFIG.C_TRIGIN_EN      {false} \
    CONFIG.C_ADV_TRIGGER    {false} \
    CONFIG.C_EN_STRG_QUAL   {1} \
    CONFIG.C_INPUT_PIPE_STAGES {0} \
] $ip
generate_target {instantiation_template synthesis simulation} $ip
puts "=== RESULT ==="
foreach p {CONFIG.C_NUM_OF_PROBES CONFIG.C_PROBE0_WIDTH CONFIG.C_PROBE1_WIDTH CONFIG.C_PROBE2_WIDTH CONFIG.C_PROBE3_WIDTH CONFIG.C_PROBE4_WIDTH CONFIG.C_DATA_DEPTH} { puts "$p=[get_property $p $ip]" }
puts "=== VEO ==="
set fh [open [lindex [glob D:/HLS/HLS-experiment/lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs/sources_1/ip/dbg_ila/*.veo] 0] r]
set txt [read $fh]; close $fh
set s [string first "INST_TAG" $txt]; set e [string first "INST_TAG_END" $txt]
puts [string range $txt $s $e]
puts "=== DONE ==="