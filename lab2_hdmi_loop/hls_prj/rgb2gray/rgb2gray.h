/*****************************************************************************
 * 实验2 任务1：RGB 转灰度 —— 头文件（HLS式纯流式核）
 *
 * 帧尺寸为编译期常量（1080p 固定）：HLS式架构下同步与帧尺寸
 * 全部由核外统一同步框架确定，核不携带任何同步/尺寸端口。
 *****************************************************************************/
#ifndef RGB2GRAY_H_
#define RGB2GRAY_H_

#include <ap_int.h>
#include <hls_stream.h>

// 帧尺寸常量（与基座工程 1080p HDMI 一致）
#define RGB2GRAY_W 1920
#define RGB2GRAY_H 1080

// 像素位域（RGB888 打包在 24bit 内）
#define PIX_R_HI 23
#define PIX_R_LO 16
#define PIX_G_HI 15
#define PIX_G_LO 8
#define PIX_B_HI 7
#define PIX_B_LO 0

// BT.601 近似灰度公式：Y = (66R + 129G + 25B + 128) >> 8
// 公式结果天然落在 0~255，无需限幅（Python 20万随机采样验证）
inline ap_uint<8> rgb2gray_y(ap_uint<8> r, ap_uint<8> g, ap_uint<8> b)
{
    ap_uint<32> t = (ap_uint<32>)66 * r + 129 * g + 25 * b + 128;
    return (ap_uint<8>)(t >> 8);
}

// 顶层函数声明（实现在 rgb2gray.cpp，tb 通过本头文件调用）
void rgb2gray(
        hls::stream<ap_uint<24> > &src,
        hls::stream<ap_uint<8>  > &dst);

#endif