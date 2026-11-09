/*****************************************************************************
 * 实验2 任务1：RGB 转灰度 —— Testbench（自动逐点比对，输出 PASS/FAIL）
 *
 * 测试内容（核固定 1080p 帧尺寸，图案覆盖 0/255 极值、灰阶、纯色、随机）：
 *   1) 1080p 组合图案（灰阶条含 0/255 + 纯红/绿/蓝/灰 + 白/黑/低灰 + 随机块）
 *   2) 1080p 渐变（R/G/B 三通道渐变，覆盖 0/255）
 *   3) 1080p 黑白棋盘（含 0/255 极值）
 *   4) 1080p 随机帧
 *   5) 1080p 极值分区帧（白/黑/低灰/纯灰/纯红绿蓝）
 * 判定：CPU 参考实现（BT.601 整数移位）逐像素比对，统计错误数与最大误差。
 * 运行：csim 直接执行，退出码 0=全部 PASS，非 0=存在 FAIL。
 *****************************************************************************/
#include "rgb2gray.h"
#include <cstdio>
#include <cstdlib>

// ---------------------------------------------------------------- 图案生成
// 生成有效区坐标 (r,c) 处的 RGB888 测试像素（固定 1080p，覆盖 0/255 极值）
static ap_uint<24> gen_pixel(int r, int c, int w, int h, int pattern)
{
    int R, G, B;
    switch (pattern) {
    case 0: {   // 组合：上=16级灰阶条（含0/255），中=纯色块，下=极值+随机
        if (r < h / 3) {
            int v = (c * 16 / (w > 1 ? w : 1)) * 17;      // 0,17,...,255
            R = G = B = v;
        } else if (r < h * 2 / 3) {
            int q = c * 4 / (w > 1 ? w : 1);
            if      (q < 1) { R = 255; G = 0;   B = 0;   }              // 纯红
            else if (q < 2) { R = 0;   G = 255; B = 0;   }              // 纯绿
            else if (q < 3) { R = 0;   G = 0;   B = 255; }              // 纯蓝
            else            { R = 128; G = 128; B = 128; }              // 纯灰
        } else {
            int q = c * 4 / (w > 1 ? w : 1);
            if      (q < 1) { R = 255; G = 255; B = 255; }              // 纯白
            else if (q < 2) { R = 0;   G = 0;   B = 0;   }              // 纯黑
            else if (q < 3) { R = 7;   G = 7;   B = 7;   }              // 低灰
            else {
                unsigned s = (unsigned)(r * w + c) * 2654435761u + 12345u;
                R = (int)((s >> 16) & 255); G = (int)((s >> 8) & 255); B = (int)(s & 255);
            }
        }
        break;
    }
    case 1: {   // 渐变帧：R 沿行、G 沿列、B 混合（覆盖 0/255）
        R = r * 255 / (h > 1 ? h - 1 : 1);
        G = c * 255 / (w > 1 ? w - 1 : 1);
        B = (r + c) * 255 / (h + w > 2 ? h + w - 2 : 1);
        break;
    }
    case 2: {   // 随机帧（固定种子，可复现）
        unsigned s = (unsigned)(r * w + c) * 40503u + 7u;
        R = (int)((s >> 16) & 255); G = (int)((s >> 8) & 255); B = (int)(s & 255);
        break;
    }
    case 3: {   // 黑白棋盘帧（交替 0/255 极值）
        int v = ((r + c) & 1) ? 255 : 0;
        R = G = B = v;
        break;
    }
    default: {  // 极值分区帧：上=白/黑，中=低灰/纯灰，下=纯红/绿/蓝
        if (r < h / 3) {
            R = G = B = (c < w / 2) ? 255 : 0;
        } else if (r < h * 2 / 3) {
            R = G = B = (c < w / 2) ? 7 : 128;
        } else {
            int q = c * 3 / (w > 1 ? w : 1);
            if      (q < 1) { R = 255; G = 0;   B = 0; }
            else if (q < 2) { R = 0;   G = 255; B = 0; }
            else            { R = 0;   G = 0;   B = 255; }
        }
        break;
    }
    }
    return ((ap_uint<24>)R << 16) | ((ap_uint<24>)G << 8) | (ap_uint<24>)B;
}

// ---------------------------------------------------------------- 单帧测试
// 返回错误像素数；err_max 输出最大绝对误差
static long long run_frame(int pattern, const char* name, int* err_max)
{
    const int w = RGB2GRAY_W;
    const int h = RGB2GRAY_H;
    hls::stream<ap_uint<24> > src;
    hls::stream<ap_uint<8>  > dst;

    // 写入输入帧（有效像素流，外部框架负责提取，tb 只送有效像素）
    for (int r = 0; r < h; r++)
        for (int c = 0; c < w; c++)
            src.write(gen_pixel(r, c, w, h, pattern));

    // 调用核（帧模式：处理 w*h 个有效像素后返回）
    rgb2gray(src, dst);

    // 逐像素读回并与 CPU 参考比对
    long long err = 0;
    int emax = 0;
    for (int r = 0; r < h; r++) {
        for (int c = 0; c < w; c++) {
            ap_uint<24> ref_pix = gen_pixel(r, c, w, h, pattern);
            ap_uint<8>  ref_y = rgb2gray_y(ref_pix.range(PIX_R_HI, PIX_R_LO),
                                           ref_pix.range(PIX_G_HI, PIX_G_LO),
                                           ref_pix.range(PIX_B_HI, PIX_B_LO));
            ap_uint<8>  got = dst.read();
            if (got != ref_y) {
                err++;
                int d = (int)got - (int)ref_y;
                if (d < 0) d = -d;
                if (d > emax) emax = d;
            }
        }
    }
    *err_max = emax;
    printf("[%s] size=%dx%d pix=%lld err=%lld maxerr=%d  %s\n",
           name, w, h, (long long)w * h, err, emax, (err == 0) ? "PASS" : "FAIL");
    return err;
}

// ---------------------------------------------------------------- 主流程
int main()
{
    long long total_err = 0;
    int emax = 0;

    printf("========== RGB2GRAY csim (HLS式纯流式核) ==========\n");

    total_err += run_frame(0, "1080p_patternA", &emax);   // 组合图案（含0/255）
    total_err += run_frame(1, "1080p_patternB", &emax);   // 渐变
    total_err += run_frame(3, "1080p_chess",    &emax);   // 黑白棋盘极值
    total_err += run_frame(2, "1080p_rand",     &emax);   // 随机
    total_err += run_frame(4, "1080p_extreme",  &emax);   // 极值分区（白黑/低灰/纯色）

    if (total_err == 0) {
        printf("========== RESULT: ALL PASS (含 0/255 极值) ==========\n");
        return 0;
    } else {
        printf("========== RESULT: FAIL total_err=%lld maxerr=%d ==========\n",
               total_err, emax);
        return 1;
    }
}