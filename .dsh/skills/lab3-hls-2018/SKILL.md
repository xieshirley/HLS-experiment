---
name: lab3-hls-2018
description: 实验三专用：Vivado HLS 2018.3 的正确调用方式与 C++03 编写/综合规则。当需要跑 csim/csynth/cosim、写 HLS 源码、读综合报告或排查 HLS 报错时使用。
---

# lab3-hls-2018 —— Vivado HLS 2018.3 调用与编码规范

## 调用方式（唯一正确，见 AGENTS.md §2）

- 命令：`cmd /c '"D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\loader.bat" -exec vivado_hls -f <脚本>.tcl'`
- **不要**用 `vivado_hls.bat`（经 msys tee，沙箱下崩）。
- **必须在完全权限（非沙箱）下运行**：2018.3 内部调用 msys2 cat/tee，沙箱拦截命名管道 → Win32 error 5。
- 用 `scripts/hls_run.ps1 -Tcl <脚本>.tcl` 封装（tee 到 logs/hls_run.log，返回退出码）。

## run_hls.tcl 模板（2018.3 实测）

```tcl
open_project -reset nn_accel
add_files nn.cpp
add_files -tb tb_nn.cpp
set_top nn_top
open_solution -reset solution1
set_part {xc7a35tfgg484-2}
create_clock -period 20 -name default
csim_design
csynth_design
# cosim_design -rtl verilog   # 可选，耗时
# export_design -format ip_catalog   # 导出 IP 供 Vivado 集成
exit
```

## C++03 铁律（2018.3 不支持 C++11）

- 禁 `auto`/`nullptr`/范围 for/`std::vector`/`std::array`/初始化列表/`constexpr`。
- 定点用 `ap_int<N>`/`ap_uint<N>`/`ap_fixed<W,I>`；流用 `hls::stream<T>`。
- 数组作接口用 `#pragma HLS INTERFACE ap_memory port=a`；流接口 `#pragma HLS INTERFACE axis port=s`。
- 权重放头文件 `weights.h` 的 `const` 数组（on-chip，不需 AXI master）。

## 报告解读

- 综合后看 `solution1/syn/report/top_csynth.rpt`：Performance(Interval/Latency)、Utilization(DSP/BRAM/LUT/FF)。
- `II=1` 看 `Latency (cycles)` 与 `Interval`；DSP 看 `Utilization Estimates` 的 DSP48E。
- 时序不收敛看 `syn/report/top_csynth.rpt` 的 timing 摘要，或 Vivado 侧 WNS。

## 常见报错

- `cat.exe/tee.exe ... couldn't create signal pipe` → 沙箱问题，换完全权限。
- C++ 语法报错 → 先查是否用了 C++11。
- `cannot find crt1.o` / 链接错误 → csim 的 g++ 环境，确认用 loader.bat 启动（它会 set 环境）。
