# AGENTS.md —— 实验三「手写数字识别的 AI 部署」项目指令

本文件由 DSH 在每次会话/子代理自动加载。所有条目是**硬约束（事实）**，不是建议。
本实验不提供参考代码；代码全部由 Agent 生成，用户担任信息官/指挥官/验收员。

## 0. 项目定位

- 目标：MNIST 手写数字 → 上位机画板(28×28,黑底白字) → USB 转串口发帧 → FPGA(xc7a35tfgg484-2) 内 UART 解帧 → **Vivado HLS 2018.3** 定点神经网络推理 → 数码管(最右位)+LED[3:0] 显示 → 回传结果 → 上位机计时。
- 质量线：定点相对浮点精度损失 < 1%；综合 II=1；板载 DSP ≤ 60；识别时间越短越优。
- 工作区：`D:\HLS\HLS-experiment\lab3_`。仓库根：`D:\HLS\HLS-experiment`。

## 1. 路径真相表（本机实测，禁止用指导书里的 C:\Xilinx 路径）

| 工具 | 真实路径 |
|---|---|
| Vivado | `D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\vivado.bat` |
| Vivado HLS 启动器 | `D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\loader.bat` |
| 器件 | `xc7a35tfgg484-2`（Artix-7，WebPACK，**无需 license**） |
| 引脚约束 | `D:\HLS\HLS-experiment\lab3_\doc\DaVinci_FPGA_IO.xdc` |
| 训练 Python | `D:\HLS\HLS-experiment\lab3_\.venv\Scripts\python.exe`（**唯一**项目解释器） |
| MNIST 数据 | `D:\HLS\HLS-experiment\lab3_\data\` |
| 演示视频 | `D:\HLS\HLS-experiment\lab3_\doc\效果演示-手写数字识别.mp4` |

## 2. 工具调用铁律

1. **HLS 一律这样调**（不要用 `vivado_hls.bat`，它经 msys `tee` 会在沙箱下崩）：
   `cmd /c '"D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\loader.bat" -exec vivado_hls -f <脚本>.tcl'`
   用 `scripts/hls_run.ps1 -Tcl <脚本>` 封装。
2. **HLS 的 csim/csynth/cosim 必须在完全权限（非沙箱）下运行**：Vivado 自带 msys2 的 cat/tee 在沙箱下无法建命名管道（Win32 error 5）。
3. **Vivado 综合/实现/bitstream 走 MCP**：`vivado_start` → `vivado_execute` → `launch_runs`+`wait_on_run`。GUI 不启动（TCL 模式）。
4. **不要用裸 `python`/`pip`**（PATH 指向 3.6.0）；用 `.venv\Scripts\python.exe`。
5. 不写 workspace(`lab3_`)之外（改 `~/.dsh` 或仓库根 `.dsh` 除外，需完全权限）；不碰 `lab1_/lab2_/` 目录。

## 3. 语言与编码

- **HLS/RTL 源码用 C++03**：禁 `auto`/`vector`/`nullptr`/范围 for/`std::` 新特性；定点用 `ap_int/ap_uint/ap_fixed/hls::stream`。
- 源码文件（.c/.h/.cpp/.v/.xdc）编码统一 **GBK、无 BOM**；`.md` 用 UTF-8；`.tcl` 脚本注释用 ASCII（避免 2018.3 读中文注释出问题）。
- 综合报 C++11 语法错误时，先怀疑自己写了新语法，再改回 C++03。

## 4. 固定工程约束

- 时钟 50 MHz（周期 20 ns），`create_clock -period 20`；复位 `sys_rst_n` 低有效。
- DSP ≤ 60；推理核目标 **II=1**；时序收敛 WNS ≥ 0。
- 串口默认 115200，优化档 **1 Mbps**（50MHz/50 精确分频）。784B 一帧在 115200 ≈ 68 ms，是识别时间的主要瓶颈。
- 数码管：**共阳极、6 位动态扫描**；位选低有效、段选低有效（共阳 → 段码取反）。最右位显示结果，LED[3:0] 同步显示结果低 4 位（高电平点亮）。
- IO 电平 LVCMOS33；约束从 doc/DaVinci_FPGA_IO.xdc 取，不要自己编引脚。

## 5. 工作方式（指挥官手册）

- **先方案后代码**：先出系统方案（模块划分/帧协议/网络结构/量化位宽/DSP 预算，每项带理由），用户审核通过才写代码。
- **小步闭环**：UART 回环 → 解帧 → 推理核 → 数码管，每步自证（仿真/日志）再进下一步。
- **一次只改一处**；批量修改必须拆开逐个验证。
- **反馈只喂事实**：贴完整报错日志；上板现象描述成可验证事实（"数码管显示 E 而非 3""串口收到 0xBB 03 0xEE"），不要只说"不对"。
- 每轮与 Agent 的实质性交互，追加一行到 `logs/AI_LOG.md`（字段：日期时间/交互目的/Prompt 摘要/产出/可用性/人工修改类型/备注）。

## 6. license 真相（按本机实际）

`xc7a35t` 是 WebPACK 器件，**本实验不需要任何 license**。不要设置 `XILINXD_LICENSE_FILE`，也不要指向 `D:\software\vivado18_3\VIVADO2018.3\VIVADO2018.3\*.lic`（其中的 `license.lic` 是含 `SERVER satexu` 的浮动许可，指向后反而报错）。

## 7. 已知坑（提示卡，用户决定何时喂给 AI）

1. 预处理不做重心居中 → 现场识别率崩，且验收现场无法补救。
2. DSP 只有 60 个 → 不预算展开度，综合必超。
3. 115200 下 784 字节一帧 ≈ 68 ms → 时间瓶颈大概率在串口。
4. 2018.3 不支持 C++11 语法。
5. 数码管共阳极、动态扫描 → 段选/位选极性接错就全灭。

## 8. 验收清单（做到什么算完成）

- 浮点测试集 acc ≥ 99%；定点损失 < 1%；定点 C 仿真与 Python 定点逐样本一致。
- 综合 II=1、DSP≤60、WNS≥0；bitstream 生成。
- 上板：手写→发送→识别→数码管显示，连续 5 次 ≥4 正确；错包/乱码不卡死。
- 识别时间构成表 + 至少一项优化前后实测对比。
- AI 日志覆盖 T2≥1、T3≥3、T4≥4、T5≥2；报告 6~12 页。

## 9. 目录约定

- `hls/nn_accel/`：HLS 推理核（nn.cpp/nn.h/tb_nn.cpp/weights.h/run_hls.tcl）。
- `rtl/`：手写 RTL（uart_rx/uart_tx/frame_decode/seg_display/lab3_top）。
- `vivado/`：Vivado 工程脚本（create_project/build_bitstream/program_hw）与 xdc。
- `python/`：train_float/quantize/export_weights/mnist_io/host_gui/frame/bench。
- `testdata/`：定点测试向量（vec_in.bin / vec_ref.bin），是 Python↔HLS 一致性的契约。
- `logs/`：AI_LOG.md、调试日志.md、时间统计.md。
