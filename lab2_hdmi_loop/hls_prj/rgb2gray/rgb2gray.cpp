/*****************************************************************************
 * 实验2 任务1：RGB 转灰度 —— 顶层函数（HLS 式：纯流式核）
 *
 * 设计要点：
 *   1) 点操作：每个输出像素只依赖当前输入像素，逐像素处理，天然 II=1。
 *   2) 接口为纯像素流（RGB888 in -> Y8 out），无任何同步/尺寸端口：
 *      - 同步（vs/hs/de）由核外统一同步框架处理（任务4）；
 *      - 帧尺寸为编译期常量（RGB2GRAY_W/H），核只负责逐像素变换。
 *   3) 帧模式循环：每帧处理 W*H 个有效像素后返回；ap_ctrl_none 下
 *      RTL 综合为自由运行核，处理完一帧自动进入下一帧。
 *   4) 外部框架保证只送入 DE=1 的有效像素（消隐期核输入流无数据，
 *      axis 接口 TREADY 自然等待），因此核无需关心消隐/同步时序。
 *
 * 说明：去掉 w/h 标量端口后核为纯 axis 流式设计，满足 cosim 对
 * ap_ctrl_none 设计的支持条件（hls_stream / AXI4-Stream 端口）。
 *
 * RTL 集成提示（任务4）：
 *   src/dst 为 AXI4-Stream 从/主口；输出 8bit 灰度由顶层复制到 RGB 三通道。
 *****************************************************************************/
#include "rgb2gray.h"

void rgb2gray(
        hls::stream<ap_uint<24> > &src,   // RGB888 有效像素流
        hls::stream<ap_uint<8>  > &dst)   // 8bit 灰度像素流
{
#pragma HLS INTERFACE axis port=src
#pragma HLS INTERFACE axis port=dst
#pragma HLS INTERFACE ap_ctrl_none port=return

    for (ap_uint<12> r = 0; r < RGB2GRAY_H; r++) {
        for (ap_uint<12> c = 0; c < RGB2GRAY_W; c++) {
#pragma HLS PIPELINE II=1
            ap_uint<24> p = src.read();
            ap_uint<8> r_ = p.range(PIX_R_HI, PIX_R_LO);
            ap_uint<8> g_ = p.range(PIX_G_HI, PIX_G_LO);
            ap_uint<8> b_ = p.range(PIX_B_HI, PIX_B_LO);
            ap_uint<8> y  = rgb2gray_y(r_, g_, b_);
            dst.write(y);
        }
    }
}