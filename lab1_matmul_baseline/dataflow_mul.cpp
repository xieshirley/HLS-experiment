#include "matmul.h"

// 加载A：从顶层端口读A到片上缓存 bufA
void load_A(dtype A[N][N], dtype bufA[N][N]){
    for(int i=0;i<N;i++){
        k:for(int k=0;k<N;k++){
            bufA[i][k] = A[i][k];
        }
    }
}

// 加载B：从顶层端口读B到片上缓存 bufB
void load_B(dtype B[N][N], dtype bufB[N][N]){
    for(int k=0;k<N;k++){
        j:for(int j=0;j<N;j++){
            bufB[k][j] = B[k][j];
        }
    }
}

// 矩阵乘内核
void matmul_core(dtype bufA[N][N], dtype bufB[N][N], dtype bufC[N][N]){
    int i,j,k;
    for(i=0;i<N;i++){
        matmul_core_label2:for(j=0;j<N;j++){
            dtype sum = 0;
            matmul_core_label1:for(k=0;k<N;k++){
                sum += bufA[i][k] * bufB[k][j];
            }
            bufC[i][j] = sum;
        }
    }
}

// 写回C：把计算好的bufC输出到顶层端口C
void store(dtype bufC[N][N], dtype C[N][N]){
    for(int i=0;i<N;i++){
        store_label3:for(int j=0;j<N;j++){
            C[i][j] = bufC[i][j];
        }
    }
}

// 顶层函数，DATAFLOW放在这里
void matmul_top(dtype A[N][N], dtype B[N][N], dtype C[N][N])
{
    // ========== 重点：这三个局部数组就是PIPO缓存！ ==========
    // 只在进程之间传递，不是顶层端口，HLS自动生成乒乓buffer
    dtype bufA[N][N];
    dtype bufB[N][N];
    dtype bufC[N][N];

    load_A(A, bufA);
    load_B(B, bufB);
    matmul_core(bufA, bufB, bufC);
    store(bufC, C);
}
