# HLS 实验

Vivado HLS 课程实验集合，每个实验一个独立子目录。

## 实验列表

| 实验 | 目录 | 说明 |
|------|------|------|
| 实验一 | [lab1_matmul_baseline](lab1_matmul_baseline) | 矩阵乘法 baseline |
| 实验二 | lab2_xxx | 待补充 |
| 实验三 | lab3_xxx | 待补充 |

## 目录结构

```
HLS-experiment/
├── lab1_matmul_baseline/   # 实验一：矩阵乘法 baseline
├── lab2_xxx/               # 实验二（待补充）
└── lab3_xxx/               # 实验三（待补充）
```

## 复现方式

每个实验目录下都有一个 `run_hls.tcl`，在 Vivado HLS 中执行即可复现：

```bash
vivado_hls -f run_hls.tcl
```