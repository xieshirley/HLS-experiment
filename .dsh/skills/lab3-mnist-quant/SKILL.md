---
name: lab3-mnist-quant
description: 实验三专用：MNIST 训练→定点量化→导出权重 .h 的固定契约，保证 Python 定点模型与 HLS C 仿真逐位一致。当训练、量化、导出权重或比对定点精度时使用。
---

# lab3-mnist-quant —— 训练/量化/导出契约

## 目标

浮点 acc ≥ 99%；定点相对浮点损失 < 1%；Python 定点仿真与 HLS C 仿真**逐样本完全一致**（1000+ 张）。

## 环境

- 解释器：`.venv\Scripts\python.exe`（torch CPU / numpy / matplotlib / pyserial / pillow）。
- 数据：MNIST 4 个 idx 文件放 `data/`（自写 `mnist_io.py` 解析，不用 torchvision）。

## 定点契约（Python 与 HLS C 必须同规则）

1. 输入 28×28，灰度 0..255。预处理：**重心居中**（0 阶矩质心平移到中心）→ 归一化到 int8（如 `x' = (x - 128) >> ?`，缩放与偏置统一约定）。
2. 权重 int8，激活 int8；乘法 int8×int8 → int32 累加；累加后按层内统一 scale 移位舍入回 int8（**round-half-away-from-zero**，与 C 的 `(x + (1<<(s-1))) >> s` 保持一致）。
3. 每层 scale/bias 存 `model/quant.json`；权重导出为 `hls/nn_accel/weights.h` 的 `const` 数组（布局：`W1[o][k][kh][kw]`、`b1[o]`，int8）。
4. 测试向量：`testdata/vec_in.bin`（N 张预处理后 int8，784B/张）、`testdata/vec_ref.bin`（N 个 int32 类别 logit 或 argmax），是 Python↔HLS 一致性契约。

## 一致性验证方法

- Python 侧定点推理写成**与 C 相同的逐层循环**（不调 torch 算子，纯 numpy 循环），输出全精度 logit 到 `vec_ref.bin`。
- HLS csim 读 `vec_in.bin`，输出 logit；比对二者 `cmp` 结果 0 失配。

## 量化方案要点（写进报告）

- 位宽：建议权重/激活 int8，累加 int32（最大 784 项 int8×int8 累加 < 2^31，安全）。
- 缩放：per-tensor 或 per-layer scale（2 的幂，便于移位），论证与实测精度损失。
- 记录定点 vs 浮点精度对比表（测试集 acc）。
