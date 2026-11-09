---
name: lab3-board-bringup
description: 实验三专用：达芬奇开发板上板与排障（烧写流程、共阳数码管段码、串口/驱动）。当需要烧 bit、上板调试、数码管不亮或串口不通时使用。
---

# lab3-board-bringup —— 上板与排障

## 烧写流程（hw_server 已在后台）

- 参考 `vivado/program_hw.tcl`：`open_hw_manager` → `connect_hw_server -url localhost:3270` → `open_hw_target` → `refresh_hw_device -update_hw_probes false`（清残留探针）→ 设 PROGRAM.FILE → `program_hw_devices`。
- 前提：板子已上电、JTAG 已接。报 `debug hub not detected` 先查时钟/复位。

## 数码管（共阳极，关键）

- 段选 `seg_led[7:0]`（a~g,dp）、位选 `seg_sel[5:0]`，**均为低有效**（共阳 → 段码取反）。
- 结果显示在最右位（seg_sel[0]）。
- 数字段码（共阳，段 a..g 顺序，低电平点亮，需按实际位序映射）：先写一个段码表并用仿真/上板自检核对。
- LED[3:0] 高电平点亮，同步显示结果低 4 位。

## 串口/驱动

- 板载 CH340：插板后设备管理器应出现 COM 口；不出 → 装 WCH CH340 驱动。
- 波特率 115200（默认）/ 1Mbps（优化档，50MHz/50 精确分频）。
- 上位机 pyserial；回传结果建议用单字节类别 + 可选校验。

## 上电自检顺序

1. 上电数码管 888888 自检约 1 秒。
2. 串口回环（上位机发 → FPGA 回）。
3. 解帧（帧头/长度/校验）。
4. 推理核 + 数码管/LED 回显。
