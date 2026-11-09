// tb_nn.cpp —— 定点推理核测试台（与 python/quantize.py 导出的 testdata 逐位对拍）
#include <cstdio>
#include "nn.h"

static const char* IN_PATH  = "D:/HLS/HLS-experiment/lab3_/testdata/vec_in.bin";
static const char* REF_PATH = "D:/HLS/HLS-experiment/lab3_/testdata/vec_ref.bin";
static const int N = 1000;

int main() {
    FILE* fi = fopen(IN_PATH, "rb");
    FILE* fr = fopen(REF_PATH, "rb");
    if (!fi || !fr) {
        printf("ERROR: cannot open testdata (%s / %s)\n", IN_PATH, REF_PATH);
        return 2;
    }

    ap_uint<8> img[28][28];
    int logits[10];
    int ref[10];
    int mismatch = 0, first_bad = -1;

    for (int n = 0; n < N; n++) {
        unsigned char raw[784];
        if (fread(raw, 1, 784, fi) != 784) { printf("ERROR: short read at %d\n", n); break; }
        if (fread(ref, sizeof(int), 10, fr) != 10) { printf("ERROR: short ref at %d\n", n); break; }
        for (int r = 0; r < 28; r++)
            for (int c = 0; c < 28; c++)
                img[r][c] = raw[r * 28 + c];

        nn_top(img, logits);

        for (int c = 0; c < 10; c++) {
            if (logits[c] != ref[c]) {
                mismatch++;
                if (first_bad < 0) first_bad = n;
                break;
            }
        }
    }
    fclose(fi); fclose(fr);

    printf("CSIM_RESULT: %d/%d images bit-exact, %d mismatches (first bad=%d)\n",
           N - mismatch, N, mismatch, first_bad);
    return mismatch == 0 ? 0 : 1;
}
