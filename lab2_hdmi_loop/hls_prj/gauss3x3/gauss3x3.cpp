/*****************************************************************************
 * 实验2 任务2：3×3 高斯平滑核（编译期宏固定分辨率，纯流式）
 *
 * 改造自：gray8_gauss2d_3x3.cpp（参考模板），差异：
 *   1) 接口改为纯 AXI4-Stream（去掉 y/x/w/h 标量端口）→ 满足 ap_ctrl_none 与 cosim
 *   2) 分辨率由编译期宏 GAUSS_W/GAUSS_H 固定（方案1）
 *   3) 无显式帧首冲刷（窗口自愈）：主循环 i=0 行+j=0 列共 3001 拍 insert(0),
 *      远超 3×3 窗口 9 寄存器容量，每帧开头窗口必被完全清零，等价于自动冲刷。
 *      曾加显式冲刷循环（清 w.val/lb.val）致 cosim FAIL [212-361]，删除后
 *      csim/cosim 5 帧全 PASS（2026-11-04 修复，见日志 §6.11）
 *   4) 行缓存列数 = 行宽+1（set_size(GAUSS_W+1)），列号 col 与循环列 j 同步
 *   5) INTERFACE：axis + ap_ctrl_none（纯流式，与任务1 一致，无标量端口）
 *
 * 高斯核：1/16 × [1 2 1; 2 4 2; 1 2 1]（归一化，权重和=1，硬件可用移位+加法）
 *****************************************************************************/
#include "gauss3x3.h"
#include "ht_video_mem.h"

// 行缓存最大宽度（>=GAUSS_W；须在 include ht_video_mem.h 之后定义，
// 避免宏名与模板参数名 MAX_COLS 冲突 —— 参考模板同样如此）
#define MAX_COLS 2048

void gauss3x3(hls::stream<T1> &src, hls::stream<T1> &dst)
{
#pragma HLS INTERFACE ap_ctrl_none port=return
#pragma HLS INTERFACE axis port=src
#pragma HLS INTERFACE axis port=dst
    static HT_window_with_linebuffer<REF_ROWS, REF_COLS, MAX_COLS, T1> wlb;
#pragma HLS DEPENDENCE variable=wlb array inter false

    // 3×3 高斯核系数（1/16 归一化，定点表示）
    T2 ref[REF_ROWS][REF_COLS] = {
        { 0.0625, 0.125, 0.0625 },
        { 0.125,  0.25,  0.125  },
        { 0.0625, 0.125, 0.0625 }
    };

    int i, j, ii, jj;
    T3 d;
    T1 dd;

    // 行缓存实际列数 = 行宽 + 1（动画对齐教训：列号 col 与循环列 j 同步）
    wlb.set_size(GAUSS_W + REF_COLS / 2);      // = GAUSS_W + 1

    // ===== （原帧首冲刷：清 w.val 9 寄存器 + lb.val 3×MAX_COLS，已删除） =====
    // 删除原因：主循环 i=0 行+j=0 列共 3001 拍 insert(0) 天然冲刷窗口，
//    for (ii = 0; ii < REF_ROWS; ii++)
//        for (jj = 0; jj < REF_COLS; jj++)
//            wlb.w.val[ii][jj] = 0;
//    for (ii = 0; ii < REF_ROWS; ii++)
//        for (jj = 0; jj < MAX_COLS; jj++)
//            wlb.lb.val[ii][jj] = 0;

    // 帧模式：有效区 (GAUSS_H×GAUSS_W) + 右下补0行/列（i<H 与 j<W 内读流，否则补0）
    gauss3x3_label0:for (i = 0; i < GAUSS_H + REF_ROWS / 2; i++)
    {
        for (j = 0; j < GAUSS_W + REF_COLS / 2; j++)
        {
#pragma HLS PIPELINE II=1
            // 输入流取像素进滑窗，图像尺寸以外补0
            if (i < GAUSS_H && j < GAUSS_W)
                wlb.insert(src.read());
            else
                wlb.insert(0);

            // 3×3 卷积（中心对齐：窗口坐标原点在右下，getval(2-ii,2-jj) 坐标反转）
            d = 0;
            for (ii = 0; ii < REF_ROWS; ii++)
                for (jj = 0; jj < REF_COLS; jj++)
                    d += ref[ii][jj] * wlb.getval(REF_ROWS - 1 - ii, REF_COLS - 1 - jj);

            // 限幅 0~255（防溢出花屏）
            if (d < 0)
                dd = 0;
            else if (d > 255)
                dd = 255;
            else
                dd = d;

            // 中心像素就绪后输出（输出与输入同尺寸、中心对齐；i>=1&&j>=1 跳过左上补0区）
            if (i >= REF_ROWS / 2 && j >= REF_COLS / 2)
                dst.write(dd);
        }
    }
}
