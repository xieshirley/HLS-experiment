# HLS 实验

Vivado HLS / Vivado 课程实验集合，每个实验一个独立子目录。

## 实验列表

| 实验 | 目录 | 说明 |
|------|------|------|
| 实验一 | [lab1_matmul_baseline](lab1_matmul_baseline) | 矩阵乘法 baseline |
| 实验二 | [lab2_hdmi_loop](lab2_hdmi_loop/README.md) | **HDMI 环回 + HLS 视频处理级联**：四档模式（直通 / 灰度 / 高斯平滑 / 拉普拉斯锐化），含 Vivado 工程、HLS 源码、testbench 与调试日志，均已上板验证 |
| 实验三 | lab3_xxx | 待补充 |

## 实验二速览

1080p60 HDMI 环回，把 HLS 生成的视频核插在"输入 → 处理 → 输出"之间；四档功能由编译期常量 `MODE` 选择：

| MODE | 功能 | 像素来源 | 延迟 |
|:--:|---|---|--:|
| 0 | 直入直出 | 原始 `video_rgb` 直连（零寄存器） | 0 |
| 1 | 灰度 | `rgb2gray` | 3 拍 |
| 2 | 高斯平滑 | `gauss3x3`（`[1 2 1; 2 4 2; 1 2 1]/16`，II=1） | 2211 拍 |
| 3 | 拉普拉斯锐化 | `unsharp3x3`（`[0 -1 0; -1 5 -1; 0 -1 0]`，II=1） | 2213 拍 |

```
HDMI IN ─> hdmi_rx ─> video_core(rgb2gray + gauss3x3‖unsharp3x3) ─> video_sync ─> hdmi_tx ─> HDMI OUT
```

- 器件 `xc7a35tfgg484-2`，Vivado 2018.3 / Vivado HLS 2018.3，`pixel_clk` 148.5 MHz（6.734 ns）
- 资源（锐化档）：LUT 4072/20800（19.6%）、FF 4138/41600（10.0%）、BRAM 5/50、DSP 1/90
- 时序：**WNS +0.151 ns，0 违例**

设计细节与踩坑记录（像素时钟约束、帧末补 0 行导致的 FIFO 溢出、为什么锐化必须放进 HLS 核内）见
[lab2_hdmi_loop/README.md](lab2_hdmi_loop/README.md) 以及 `lab2_hdmi_loop/doc/` 下的
`调试日志_实验2_HDMI环回与高斯级联_完整版.md`、`修改日志_v5_回退f11b691骨架重写.md`。

## 目录结构

```
HLS-experiment/
├── lab1_matmul_baseline/   # 实验一：矩阵乘法 baseline
├── lab2_hdmi_loop/         # 实验二：HDMI 环回 + HLS 视频处理级联
│   ├── README.md           #   实验二详细说明（架构 / 延迟标定 / 踩坑 / 复现）
│   ├── vivado_prj/         #   Vivado 工程（.xpr + srcs）
│   ├── hls_prj/            #   HLS 源码（rgb2gray / gauss3x3 / unsharp3x3）
│   ├── sim_check/          #   testbench + 仿真 / 构建 / 烧写脚本
│   └── doc/                #   调试日志、修改日志、引脚约束、参考源码
└── lab3_xxx/               # 实验三（待补充）
```

> 仓库只保留**源码 + 约束 + IP 配置（`.xci`）**：`.runs/`、`.cache/`、`*.hw/`、`*.ip_user_files/`、
> HLS 的 `solution1/syn|csim`、比特流、仿真波形与日志均由 `.gitignore` 排除，可重新生成。

## 复现方式

- **实验一**（Vivado HLS 工程）：进入 `lab1_matmul_baseline/`，执行：

  ```bash
  vivado_hls -f run_hls.tcl
  ```

- **实验二**（Vivado 工程 + 三个 HLS 核）：

  ```bash
  # 1) 打开工程（Vivado 2018.3，xc7a35tfgg484-2）
  vivado lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.xpr

  # 2) 重建 HLS 核（仓库已含生成 RTL，此步可选）
  cd lab2_hdmi_loop/hls_prj/unsharp3x3 && vivado_hls -f run_hls.tcl

  # 3) 选模式：改 hdmi_loop.v 顶部 localparam MODE (0/1/2/3)

  # 4) 出比特流：综合 + 实现 + write_bitstream
  cd ../../sim_check && vivado -mode batch -source build_bar.tcl
  ```

  上板烧写：先跑 `start_hw_server.bat`（本机 TCP 3121 被系统保留，改监听 3270），
  再在 Vivado Tcl 里 `connect_hw_server -url localhost:3270`，最后 `source program_hw.tcl`。
  完整步骤、模式表、延迟标定与板级 LED 诊断见 [lab2_hdmi_loop/README.md](lab2_hdmi_loop/README.md)。
