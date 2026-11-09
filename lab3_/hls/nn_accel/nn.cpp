#include "nn.h"
#include "weights.h"

// =====================================================================
// 实验三定点推理核（扁平化版：减少 FSM 状态，让 Vivado 综合能过）
// 把每层的空间循环(oc,oh,ow)压成单层 flat 循环 + 常数除法解索引；
// 归约循环保持 (ic,kh,kw) 但 taps 可被 HLS 自动处理。整数加法可结合，
// 累加顺序变化不影响逐位结果。
// =====================================================================

static inline act_t requant(acc_t acc, int shift) {
    acc_t round = (shift > 0) ? (acc_t)(1 << (shift - 1)) : (acc_t)0;
    acc_t v = (acc + round) >> shift;
    act_t a = (v > 127) ? (act_t)127 : ((v < 0) ? (act_t)0 : (act_t)v);
    return a;
}

void nn_top(ap_uint<8> img[28][28], int logits[10]) {
#pragma HLS INTERFACE ap_memory port=img
#pragma HLS INTERFACE ap_memory port=logits

    static act_t a1[CONV1_OC][26][26];
    static act_t a1p[CONV1_OC][13][13];
    static act_t a2[CONV2_OC][11][11];
    static act_t a2p[CONV2_OC][5][5];
    static act_t af[FC1_IN];
    static act_t a3[FC1_OUT];

    int i, ic, kh, kw;

    // ---- Conv1: flat over (16*26*26) ----
conv1:
    for (i = 0; i < CONV1_OC * 26 * 26; i++) {
        int oc = i / 676;
        int oh = (i / 26) % 26;
        int ow = i % 26;
        acc_t acc = B1[oc];
        for (kh = 0; kh < 3; kh++)
            for (kw = 0; kw < 3; kw++)
                acc += (acc_t)W1[oc][0][kh][kw] * INPUT_LUT[(int)img[oh + kh][ow + kw]];
        a1[oc][oh][ow] = requant(acc, SHIFT1);
    }

    // ---- MaxPool1: flat over (16*13*13) ----
pool1:
    for (i = 0; i < CONV1_OC * 13 * 13; i++) {
        int oc = i / 169;
        int oh = (i / 13) % 13;
        int ow = i % 13;
        act_t m = a1[oc][oh * 2][ow * 2];
        if (a1[oc][oh * 2][ow * 2 + 1] > m) m = a1[oc][oh * 2][ow * 2 + 1];
        if (a1[oc][oh * 2 + 1][ow * 2] > m) m = a1[oc][oh * 2 + 1][ow * 2];
        if (a1[oc][oh * 2 + 1][ow * 2 + 1] > m) m = a1[oc][oh * 2 + 1][ow * 2 + 1];
        a1p[oc][oh][ow] = m;
    }

    // ---- Conv2: flat over (32*11*11)，归约 (ic,kh,kw) ----
conv2:
    for (i = 0; i < CONV2_OC * 11 * 11; i++) {
        int oc = i / 121;
        int oh = (i / 11) % 11;
        int ow = i % 11;
        acc_t acc = B2[oc];
        for (ic = 0; ic < CONV2_IC; ic++)
            for (kh = 0; kh < 3; kh++)
                for (kw = 0; kw < 3; kw++)
                    acc += (acc_t)W2[oc][ic][kh][kw] * a1p[ic][oh + kh][ow + kw];
        a2[oc][oh][ow] = requant(acc, SHIFT2);
    }

    // ---- MaxPool2: flat over (32*5*5) ----
pool2:
    for (i = 0; i < CONV2_OC * 5 * 5; i++) {
        int oc = i / 25;
        int oh = (i / 5) % 5;
        int ow = i % 5;
        act_t m = a2[oc][oh * 2][ow * 2];
        if (a2[oc][oh * 2][ow * 2 + 1] > m) m = a2[oc][oh * 2][ow * 2 + 1];
        if (a2[oc][oh * 2 + 1][ow * 2] > m) m = a2[oc][oh * 2 + 1][ow * 2];
        if (a2[oc][oh * 2 + 1][ow * 2 + 1] > m) m = a2[oc][oh * 2 + 1][ow * 2 + 1];
        a2p[oc][oh][ow] = m;
    }

    // ---- flatten a2p -> af: af[i] = a2p[i/25][(i/5)%5][i%5] ----
flat:
    for (i = 0; i < FC1_IN; i++) {
        af[i] = a2p[i / 25][(i / 5) % 5][i % 5];
    }

    // ---- FC1: 800 -> 64 ----
fc1:
    for (i = 0; i < FC1_OUT; i++) {
        acc_t acc = BF1[i];
        for (ic = 0; ic < FC1_IN; ic++)
            acc += (acc_t)WF1[i][ic] * af[ic];
        a3[i] = requant(acc, SHIFT_FC1);
    }

    // ---- FC2: 64 -> 10 ----
fc2:
    for (i = 0; i < FC2_OUT; i++) {
        acc_t acc = BF2[i];
        for (ic = 0; ic < FC1_OUT; ic++)
            acc += (acc_t)WF2[i][ic] * a3[ic];
        logits[i] = acc.to_int();
    }
}
