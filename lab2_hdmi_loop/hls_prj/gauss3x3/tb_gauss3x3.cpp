/*****************************************************************************
 * 实验2 任务2：3×3 高斯平滑 —— Testbench（自动逐点比对，输出 PASS/FAIL）
 *
 * 测试内容（核固定 1080p 帧尺寸，图案覆盖 0/255 极值、棋盘、随机、渐变）：
 *   1) 1080p 灰阶组合（含 0/255）
 *   2) 1080p 渐变（覆盖 0/255）
 *   3) 1080p 黑白棋盘（交替 0/255 极值）
 *   4) 1080p 随机帧（固定种子）
 *   5) 1080p 极值分区帧（白/黑/低灰/纯灰/渐变）
 * 判定：CPU 参考模型（四边补0 + 整数核 1/16 归一化 >>4 + 限幅）逐像素比对。
 * 运行：csim 直接执行，退出码 0=全部 PASS，非 0=存在 FAIL。
 *****************************************************************************/
#include "gauss3x3.h"
#include <cstdio>
#include <cstdlib>

// ---------------------------------------------------------------- 图案生成
// 生成有效区坐标 (r,c) 处的灰度测试像素（固定 1080p，覆盖 0/255 极值）
static ap_uint<8> gen_gray(int r, int c, int w, int h, int pattern)
{
    int v;
    switch (pattern) {
    case 0: {   // 组合：上=16级灰阶条（含0/255），下=黑白棋盘
        if (r < h / 2)
            v = (c * 16 / (w > 1 ? w : 1)) * 17;            // 0,17,...,255
        else
            v = ((r + c) & 1) ? 255 : 0;
        break;
    }
    case 1: {   // 渐变帧（R 沿行、G 沿列，覆盖 0/255）
        v = ((r * 255 / (h > 1 ? h - 1 : 1)) +
             (c * 255 / (w > 1 ? w - 1 : 1))) >> 1;
        break;
    }
    case 2: {   // 黑白棋盘帧（交替 0/255 极值）
        v = ((r + c) & 1) ? 255 : 0;
        break;
    }
    case 3: {   // 随机帧（固定种子，可复现）
        unsigned s = (unsigned)(r * w + c) * 40503u + 7u;
        v = (int)((s >> 8) & 255);
        break;
    }
    default: {  // 极值分区：上=白/黑，中=低灰/纯灰，下=渐变（覆盖 0/255）
        if (r < h / 3)
            v = (c < w / 2) ? 255 : 0;
        else if (r < h * 2 / 3)
            v = (c < w / 2) ? 7 : 128;
        else
            v = c * 255 / (w > 1 ? w - 1 : 1);
        break;
    }
    }
    return (ap_uint<8>)v;
}

// ---------------------------------------------------------------- CPU 参考模型
// 四边补0 的 3×3 高斯参考：ref(r,c) = clamp( Σ K(i,j)·pad(r+i-1,c+j-1) >> 4 )
static int ref_gauss(int r, int c, const ap_uint<8>* img, int w, int h)
{
    static const int K[3][3] = { {1,2,1}, {2,4,2}, {1,2,1} };
    int acc = 0;
    for (int ii = -1; ii <= 1; ii++) {
        for (int jj = -1; jj <= 1; jj++) {
            int rr = r + ii, cc = c + jj;
            int v = (rr >= 0 && rr < h && cc >= 0 && cc < w) ? (int)img[rr * w + cc] : 0;
            acc += v * K[ii+1][jj+1];
        }
    }
    int y = acc >> 4;                 // 归一化 1/16（正数截断，与核定点一致）
    if (y < 0)   y = 0;
    if (y > 255) y = 255;
    return y;
}

// ---------------------------------------------------------------- 单帧测试
// 返回错误像素数；err_max 输出最大绝对误差
static long long run_frame(int pattern, const char* name, int* err_max)
{
    const int w = GAUSS_W;
    const int h = GAUSS_H;
    hls::stream<ap_uint<8> > src;
    hls::stream<ap_uint<8> > dst;

    // 生成整帧灰度参考，并写入输入流（有效像素流，外部框架负责提取）
    ap_uint<8>* img = new ap_uint<8>[w * h];
    for (int r = 0; r < h; r++) {
        for (int c = 0; c < w; c++) {
            ap_uint<8> v = gen_gray(r, c, w, h, pattern);
            img[r * w + c] = v;
            src.write(v);
        }
    }

    // 调用核（帧模式：处理 w*h 个有效像素后返回）
    gauss3x3(src, dst);

    // 逐像素读回并与 CPU 参考比对（核输出与输入同尺寸、中心对齐）
    long long err = 0;
    int emax = 0;
    for (int r = 0; r < h; r++) {
        for (int c = 0; c < w; c++) {
            int ref = ref_gauss(r, c, img, w, h);
            ap_uint<8> got = dst.read();
            if ((int)got != ref) {
                err++;
                int d = (int)got - ref;
                if (d < 0) d = -d;
                if (d > emax) emax = d;
            }
        }
    }
    delete[] img;
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

    printf("========== GAUSS3X3 csim (HLS式纯流式核) ==========\n");

    total_err += run_frame(0, "1080p_patternA", &emax);   // 灰阶组合（含0/255）
    total_err += run_frame(1, "1080p_patternB", &emax);   // 渐变
    total_err += run_frame(2, "1080p_chess",    &emax);   // 黑白棋盘极值
    total_err += run_frame(3, "1080p_rand",     &emax);   // 随机
    total_err += run_frame(4, "1080p_extreme",  &emax);   // 极值分区（白黑/低灰/渐变）

    if (total_err == 0) {
        printf("========== RESULT: ALL PASS (含 0/255 极值) ==========\n");
        return 0;
    } else {
        printf("========== RESULT: FAIL total_err=%lld maxerr=%d ==========\n",
               total_err, emax);
        return 1;
    }
}