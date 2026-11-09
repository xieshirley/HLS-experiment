/*****************************************************************************
 * 实验2 任务2：3×3 高斯平滑 —— 顶层头文件（编译期宏固定分辨率，方案1）
 *
 * 设计要点（与参考模板 gray8_gauss2d_3x3.cpp 的差异）：
 *   1) 去掉 y/x/w/h 标量端口，接口为纯 AXI4-Stream（ap_ctrl_none 可过 cosim）
 *   2) 帧尺寸由编译期宏 GAUSS_W/GAUSS_H 固定（换分辨率 = 改宏重综合）
 *   3) MAX_COLS 为行缓存最大宽度上限（≥ 最大行宽，支持多分辨率扩展）
 *****************************************************************************/
#ifndef GAUSS3X3_H
#define GAUSS3X3_H

#include <ap_int.h>
#include <ap_fixed.h>
#include <hls_stream.h>

// ===== 编译期宏：固定分辨率（方案1）=====
#define GAUSS_W   1920        // 图像宽度（每行有效像素数）
#define GAUSS_H   1080        // 图像高度（有效行数）
// 注意：行缓存最大宽度 MAX_COLS 定义在 gauss3x3.cpp 中（include ht_video_mem.h 之后），
// 因为 MAX_COLS 也是 ht_video_mem.h 的模板参数名，不能在头文件提前定义成宏

#define REF_ROWS  3           // 窗口行数
#define REF_COLS  3           // 窗口列数

typedef ap_uint<8>  T1;       // 像素灰度类型
typedef ap_fixed<12,4>  T2;   // 卷积系数类型（12bit，4bit整数8bit小数）
typedef ap_fixed<18,10> T3;   // 累加器类型（18bit，8bit整数10bit小数）

// 顶层函数声明（纯流式：src→dst，无标量端口）
void gauss3x3(hls::stream<T1> &src, hls::stream<T1> &dst);

#endif