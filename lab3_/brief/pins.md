# 达芬奇开发板关键引脚（本实验用，已与 docx 表6 + DaVinci_FPGA_IO.xdc 交叉核对）

器件 `xc7a35tfgg484-2`，电平 LVCMOS33，时钟 50MHz（周期 20ns）。

| 信号 | 引脚 | 说明 |
|---|---|---|
| sys_clk | R4 | 50MHz 系统时钟 |
| sys_rst_n | U2 | 复位，低有效 |
| uart_rxd | U5 | 板载 USB 转串口(CH340) → FPGA 接收 |
| uart_txd | T6 | FPGA → 板载 CH340 发送 |
| led[3] | Y2 | 高电平点亮 |
| led[2] | V2 | 高电平点亮 |
| led[1] | R3 | 高电平点亮 |
| led[0] | R2 | 高电平点亮 |
| seg_led[7] | J14 | 段选 a~g,dp（共阳极） |
| seg_led[6] | H14 | |
| seg_led[5] | G13 | |
| seg_led[4] | K13 | |
| seg_led[3] | G15 | |
| seg_led[2] | L13 | |
| seg_led[1] | G16 | |
| seg_led[0] | H15 | |
| seg_sel[5] | G18 | 位选（6 位动态扫描） |
| seg_sel[4] | H18 | |
| seg_sel[3] | G17 | |
| seg_sel[2] | H13 | |
| seg_sel[1] | H17 | |
| seg_sel[0] | J15 | |
| key[3] | T3 | 用户按键 |
| key[2] | W2 | |
| key[1] | U1 | |
| key[0] | T1 | |
| touch_key | T5 | 触摸按键（备用） |

## 关键提醒

- 数码管**共阳极**：段选/位选低电平有效，段码需取反。
- `create_clock -period 20 -name sys_clk [get_ports sys_clk]`。
- `set_property CFGBVS VCCO`、`set_property CONFIG_VOLTAGE 3.3`（来自官方 xdc）。
- 完整 123 引脚见 `doc/DaVinci_FPGA_IO.xdc`；要别的外设(HDMI/摄像头)从那里查。
- 实验台连接：笔记本 USB → USB 转 UART 模块(白小板) → 排线接板载串口座；另一条 USB 线接板载 CH340/供电。上电数码管 888888 自检约 1 秒。
