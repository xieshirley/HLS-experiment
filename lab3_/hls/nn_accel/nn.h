#ifndef NN_H
#define NN_H

#include <ap_int.h>

// 实验三定点推理核（与 brief/方案书.md 一致）
// Conv1(1->16,3x3)->MaxPool->Conv2(16->32,3x3)->MaxPool->FC(800->64->10)
// 定点：激活 int8、权重 int8、累加 int32、每层移位 requant（2 的幂）

typedef ap_int<32> acc_t;   // 累加器
typedef ap_int<8>  act_t;   // 激活/权重（int8）

#define CONV1_IC 1
#define CONV1_OC 16
#define CONV2_IC 16
#define CONV2_OC 32
#define FC1_IN  800   // 5*5*32
#define FC1_OUT 64
#define FC2_OUT 10

// 顶层：输入 28x28 图像(uint8)，输出 10 个 int32 logits
void nn_top(ap_uint<8> img[28][28], int logits[10]);

#endif
