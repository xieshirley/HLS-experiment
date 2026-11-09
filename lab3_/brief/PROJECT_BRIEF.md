# 项目简报（上下文包）—— 交给 AI 的完整信息清单

> 这是指导书 §3「给 AI 的信息清单」的汇编。原则：宁可多给背景，不要让 AI 猜。

## 1. 目标与功能要求（= 需求文档）

见 `../AGENTS.md` §0 与 §4。核心功能链路：上位机画板(28×28 黑底白字) → 串口发帧 → FPGA 解帧 → HLS 定点推理 → 数码管(最右位)+LED[3:0] 显示 → 回传结果 → 上位机计时。

质量要求（一并声明，是验收依据）：
- MNIST 测试集定点精度损失自定达标线并论证（目标 < 1%）。
- 推理核综合 II=1；DSP ≤ 60（板载 60 个，注意展开度预算）。

## 2. 硬件系统架构与连接关系

- 数据链路：笔记本 → USB 转 UART 模块 → 板载串口(CH340) → FPGA 推理 → 数码管/LED 回显。
- 板载资源：数码管 6 位 8 段（共阳极）、LED[3:0]、按键 key[3:0]、触摸按键。
- 实拍连接：笔记本 USB 口 → USB 转 UART 白小板 → 排线接板载串口座；另一条 USB 线接板载 CH340/供电。上电数码管 888888 自检约 1 秒。
- 详细引脚见 `brief/pins.md` 与 `doc/DaVinci_FPGA_IO.xdc`。

## 3. 开发板 FPGA 引脚定义

器件 `xc7a35tfgg484-2`，LVCMOS33，50MHz。全部引脚（时钟/复位/UART/LED/数码管/按键）见 `brief/pins.md`（已上板验证）。不要自己编引脚。

## 4. 开发环境与版本（含软件在哪、怎么调）

| 项 | 值 |
|---|---|
| Vivado / Vivado HLS | 2018.3，装在 `D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\`（**不是** C:\Xilinx） |
| HLS 调用 | `loader.bat -exec vivado_hls -f <脚本>.tcl`（**不要用 vivado_hls.bat**；必须在完全权限下跑，见 AGENTS.md §2） |
| Vivado 调用 | 走 MCP（TCL 模式）或 `vivado.bat -mode batch -source <脚本>.tcl` |
| 器件 | xc7a35tfgg484-2（WebPACK，无需 license） |
| OS | Windows |
| Python | 训练/上位机用 `.venv\Scripts\python.exe`（Python 3.13，torch CPU/numpy/matplotlib/pyserial/pillow） |
| 语言约束 | **C++03**（2018.3 不支持 C++11 新语法，必须提前声明）；源码 GBK 无 BOM |
| 串口工具 | pyserial（上位机）；串口调试助手可选 |

## 5. 约束与资源预算

- 时钟 50MHz（周期 20ns）。
- 器件资源：20,800 LUT / 41,600 FF / 90 DSP / 1,800Kb BRAM；本实验 DSP ≤ 60。
- 推理核 II 目标 = 1；WNS ≥ 0。
- 识别时间目标：先给宽松目标（如 115200 下 < 100ms），逐步收紧（优化档 1Mbps）。

## 6. 验收标准（做到什么算完成）

见 `../AGENTS.md` §8 清单。要点：浮点 acc≥99%、定点损失<1%、定点 C 仿真与 Python 逐样本一致、综合 II=1 且 DSP≤60、上板 5 次≥4 正确、错包不卡死、时间构成表+至少一项优化实测。
