// =====================================================================
// matmul_tb.cpp —— 测试激励（Testbench），各实验版本通用
// 功能：
//   1. 用确定性公式生成测试矩阵 A、B（结果可复现，便于调试）；
//   2. 用纯软件方式（long long 累加）计算黄金参考 C_sw；
//   3. 调用被测顶层函数 matmul_top 得到 C_hw，逐元素比对；
//   4. 全部一致返回 0（csim 通过），否则返回 1。
// =====================================================================
#include <cstdio>
#include "matmul.h"

// 生成确定性测试数据，取值范围 [-9, 9]，避免溢出且便于人工核对
static data_t gen_a(int i, int j) { return (data_t)((i * 13 + j * 7 + 3) % 19) - 9; }
static data_t gen_b(int i, int j) { return (data_t)((i * 11 + j * 5 + 1) % 17) - 8; }

// 黄金参考模型：软件计算 C = A x B（用 64 位累加，保证参考值不溢出）
static void matmul_golden(data_t A[N][N], data_t B[N][N], data_t C[N][N])
{
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
        {
            long long sum = 0;
            for (int k = 0; k < N; k++)
                sum += (long long)A[i][k] * (long long)B[k][j];
            C[i][j] = (data_t)sum;
        }
}

int main()
{
    data_t A[N][N], B[N][N], C_hw[N][N], C_sw[N][N];

    // 1) 生成测试数据
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
        {
            A[i][j] = gen_a(i, j);
            B[i][j] = gen_b(i, j);
        }

    // 2) 软件黄金参考 & 硬件（HLS）结果
    matmul_golden(A, B, C_sw);
    matmul_top(A, B, C_hw);

    // 3) 逐元素比对
    int errors = 0;
    long long max_diff = 0;
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
        {
            long long diff = (long long)C_hw[i][j] - (long long)C_sw[i][j];
            if (diff < 0) diff = -diff;
            if (diff > max_diff) max_diff = diff;
            if ((long long)C_hw[i][j] != (long long)C_sw[i][j])
            {
                if (errors < 5)   // 最多打印前 5 处错误，避免刷屏
                    printf("  [错] C_hw[%2d][%2d] = %lld, 期望 %lld\n",
                           i, j, (long long)C_hw[i][j], (long long)C_sw[i][j]);
                errors++;
            }
        }

    printf("矩阵规模: %d x %d, 比较元素个数: %d\n", N, N, N * N);
    printf("最大绝对误差: %lld, 错误元素个数: %d\n", max_diff, errors);

    if (errors == 0)
    {
        printf("*** 测试通过 (TEST PASSED) ***\n");
        return 0;
    }
    printf("*** 测试失败 (TEST FAILED) ***\n");
    return 1;
}
