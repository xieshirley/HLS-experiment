# HLS 实验

Vivado HLS 课程实验集合，每个实验一个独立子目录。

## 实验列表

| 实验 | 目录 | 说明 |
|------|------|------|
| 实验一 | [lab1_matmul_baseline](lab1_matmul_baseline) | 矩阵乘法 baseline |
| 实验二 | [lab2_hdmi_loop](lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs) | HDMI 回环：HLS 实现 rgb2gray 灰度转换与 gauss3x3 高斯平滑，已完成两者联合仿真；灰度转换完成上板验证 |
| 实验三 | lab3_xxx | 待补充 |

## 目录结构

```
HLS-experiment/
├── lab1_matmul_baseline/   # 实验一：矩阵乘法 baseline
├── lab2_hdmi_loop/         # 实验二：HDMI 回环（仅提交 vivado_prj/hdmi_loop/hdmi_loop.srcs）
└── lab3_xxx/               # 实验三（待补充）
```

## 复现方式

- 实验一（Vivado HLS 工程）：进入 `lab1_matmul_baseline/`，执行：

  ```bash
  vivado_hls -f run_hls.tcl
  ```

- 实验二（Vivado 工程）：`.xpr` 未入库，新建 Vivado 工程后导入 `lab2_hdmi_loop/vivado_prj/hdmi_loop/hdmi_loop.srcs`（Vivado 2018.3，器件 xc7a35tfgg484-2）。
