############## NET - IOSTANDARD #################################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
#############SPI Configurate Setting##############################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
############## clock and reset define##############################
create_clock -period 20.000 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property PACKAGE_PIN R4 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
set_property PACKAGE_PIN U2 [get_ports rst_n]

#####################HDMI_IN_A#######################################
create_clock -period 6.000 -name clk_hdmi_in_p -waveform {0.000 3.000}
set_property PACKAGE_PIN D22 [get_ports hdmi_ddc_scl_io]
set_property PACKAGE_PIN D21 [get_ports hdmi_ddc_sda_io]
set_property PACKAGE_PIN E22 [get_ports hdmi_in_hpd]
set_property PACKAGE_PIN C18 [get_ports clk_hdmi_in_p]
set_property PACKAGE_PIN C22 [get_ports {data_hdmi_in_p[0]}]
set_property PACKAGE_PIN B21 [get_ports {data_hdmi_in_p[1]}]
set_property PACKAGE_PIN B20 [get_ports {data_hdmi_in_p[2]}]
set_property PACKAGE_PIN E21 [get_ports hdmi_in_oen]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_ddc_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_ddc_sda_io]
set_property IOSTANDARD TMDS_33 [get_ports clk_hdmi_in_n]
set_property IOSTANDARD TMDS_33 [get_ports clk_hdmi_in_p]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_in_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_in_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_in_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_in_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_in_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_in_p[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_in_oen]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_in_hpd]
######################HDMI_OUT_B#######################################
set_property PACKAGE_PIN B17 [get_ports clk_hdmi_out_p]
set_property PACKAGE_PIN A18 [get_ports {data_hdmi_out_p[0]}]
set_property PACKAGE_PIN A15 [get_ports {data_hdmi_out_p[1]}]
set_property PACKAGE_PIN A13 [get_ports {data_hdmi_out_p[2]}]
set_property PACKAGE_PIN C20 [get_ports hdmi_out_oen]
set_property IOSTANDARD TMDS_33 [get_ports clk_hdmi_out_n]
set_property IOSTANDARD TMDS_33 [get_ports clk_hdmi_out_p]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_out_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_out_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_out_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_out_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_out_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {data_hdmi_out_p[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_out_oen]

#=============================================================================
# 像素时钟域约束（原 XDC 漏掉了！）
#   pixel_clk / pixel_clk_5x 是从 HDMI 输入 TMDS 时钟里恢复出来的，
#   不 create_clock 的话整个像素域（video_core / gauss3x3 / video_sync / dvi 编码）
#   都是"未约束路径"，P&R 不会为 148.5MHz 做任何优化 —— 高斯核因此跑飞。
#   1080p60：像素时钟 148.5MHz → 6.734ns
#=============================================================================
create_clock -period 6.734 -name pixel_clk [get_nets pixel_clk]

#=============================================================================
#=============================================================================
# 异步时钟域划分（XDC 里不能写 if，全部用直接语句）
#   sys_clk(50MHz/按键消抖)、clk_out1(10MHz)、clk_out2(200MHz)、
#   pixel_clk(148.5MHz，从 HDMI 输入 TMDS 恢复) 四者互相异步：
#     * hdmi_rx 内部用同步器跨 10M/200M 与像素域
#     * 按键模式号用"格雷码 + 2 级同步器"跨到像素域（key_mode.v）
#   不做 clock group 时，u_key_mode → mode_meta 会被按 6.734ns 分析，
#   实测报 -3.392ns 违例（把异步当同步）。
#=============================================================================
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_nets pixel_clk]] \
    -group [get_clocks -of_objects [get_ports sys_clk]] \
    -group [get_clocks clk_out1_mmcm] \
    -group [get_clocks clk_out2_mmcm]

#=============================================================================
# 调试 LED（达芬奇板：led[0]=R2 led[1]=R3 led[2]=V2 led[3]=Y2，LVCMOS33）
#=============================================================================
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN Y2 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
#=============================================================================
# 任务四：按键引脚（抄自达芬奇官方 DaVinci_FPGA_IO.xdc）
#   key[0]=T1   key[1]=U1   key[2]=W2   key[3]=T3   （均 LVCMOS33，按下为低）
#   顶层只用 key[0] 切模式，其余三位预留但引脚必须约束（否则无法布线/会报错）
#   sys_clk（50MHz 消抖时钟）已在文件开头 create_clock -period 20.000 + R4
#=============================================================================
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33} [get_ports {key[0]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33} [get_ports {key[1]}]
set_property -dict {PACKAGE_PIN W2 IOSTANDARD LVCMOS33} [get_ports {key[2]}]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33} [get_ports {key[3]}]