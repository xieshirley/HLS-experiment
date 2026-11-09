# quantize.py —— 定点量化 + numpy 逐位参考实现 + 导出 weights.h / testdata（实验三 G3）
# 与 hls/nn_accel/nn.cpp 的定点运算逐位一致（int8 激活/权重、int32 累加、每层移位 requant + ReLU）
# 运行：.venv\Scripts\python.exe python\quantize.py
import os, sys, json, struct
import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mnist_io import load_mnist

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'data')
MODEL_DIR = os.path.join(ROOT, 'model')
HLS_DIR = os.path.join(ROOT, 'hls', 'nn_accel')
TESTDATA = os.path.join(ROOT, 'testdata')
os.makedirs(TESTDATA, exist_ok=True)

MEAN, STD = 0.1307, 0.3081
NCAL = 2000       # 标定图像数
NTEST = 1000      # 导出测试向量数（csim 对拍用）


# ---------- 定点原语（与 nn.cpp 一致） ----------
def requant(acc, shift):
    r = (1 << (shift - 1)) if shift > 0 else 0
    v = (acc + r) >> shift          # numpy 有符号右移 = 算术移位(向下取整)，同 C
    return np.clip(v, 0, 127).astype(np.int8)   # ReLU + 饱和


def conv2d_np(A, W):
    # A [N,ic,H,W] int64, W [oc,ic,kh,kw] int8 -> [N,oc,OH,OW] int64
    N, ic, H, Wd = A.shape
    oc, ic2, kh, kw = W.shape
    OH, OW = H - kh + 1, Wd - kw + 1
    acc = np.zeros((N, oc, OH, OW), dtype=np.int64)
    for k in range(kh):
        for l in range(kw):
            a = A[:, :, k:k + OH, l:l + OW]          # [N,ic,OH,OW]
            w = W[:, :, k, l].astype(np.int64)        # [oc,ic]
            acc += np.einsum('nicd,oi->nocd', a, w)
    return acc


def fc_np(A, W):
    return A.astype(np.int64) @ W.astype(np.int64).T   # [N,in] @ [out,in].T -> [N,out]


def maxpool_np(A, k=2):
    N, C, H, W = A.shape
    OH, OW = H // k, W // k
    return A[:, :, :OH * k, :OW * k].reshape(N, C, OH, k, OW, k).max(axis=(3, 5))


def quantize_weights(Wf, S_w=None):
    if hasattr(Wf, 'detach'):
        Wf = Wf.detach().cpu().numpy()
    Wf = np.asarray(Wf).astype(np.float64)
    if S_w is None:
        S_w = float(np.abs(Wf).max() / 127.0)
    W = np.clip(np.round(Wf / S_w), -128, 127).astype(np.int8)
    return W, S_w


def forward_int(X, lut, W1, B1, sh1, W2, B2, sh2, WF1, BF1, shf1, WF2, BF2):
    a0 = lut[X]                            # [N,28,28] int8
    a0 = a0[:, None, :, :].astype(np.int64)
    acc1 = conv2d_np(a0, W1) + B1[None, :, None, None]
    a1 = requant(acc1, sh1)
    a1p = maxpool_np(a1.astype(np.int64)).astype(np.int8)
    acc2 = conv2d_np(a1p.astype(np.int64), W2) + B2[None, :, None, None]
    a2 = requant(acc2, sh2)
    a2p = maxpool_np(a2.astype(np.int64)).astype(np.int8)
    af = a2p.reshape(a2p.shape[0], -1)     # C 序展平 = oc*25 + oh*5 + ow
    acc3 = fc_np(af, WF1) + BF1
    a3 = requant(acc3, shf1)
    logits = fc_np(a3.astype(np.int64), WF2) + BF2
    return logits


def pick_shift(acc):
    m = int(np.maximum(0, acc).max())
    if m <= 127:
        return 0
    return int(np.ceil(np.log2(m / 127.0)))


def c_init(a):
    a = np.asarray(a)
    if a.ndim <= 1:
        return '{' + ','.join(str(int(v)) for v in a) + '}'
    return '{' + ','.join(c_init(sub) for sub in a) + '}'


def c_decl(decl, arr):
    return f'static const {decl} = ' + c_init(arr) + ';\n'


def main():
    ck = torch.load(os.path.join(MODEL_DIR, 'float.pt'), map_location='cpu')
    sd = ck['state_dict']
    print('[quant] float test_acc =', ck.get('test_acc'), flush=True)

    # 输入 LUT：p -> (p/255-mean)/std * S_in，S_in 使最亮像素映射到 127
    S_in = int(127.0 / ((1.0 - MEAN) / STD))
    lut_f = (np.arange(256).astype(np.float64) / 255.0 - MEAN) / STD * S_in
    lut = np.clip(np.round(lut_f), -128, 127).astype(np.int8)
    S0 = 1.0 / S_in
    print(f'[quant] S_in={S_in} lut range=[{lut.min()},{lut.max()}]', flush=True)

    # ---- conv1 ----
    W1, S_w1 = quantize_weights(sd['conv1.weight'])
    B1 = np.round(sd['conv1.bias'].numpy() / (S_w1 * S0)).astype(np.int32)

    # ---- conv2 ----
    W2, S_w2 = quantize_weights(sd['conv2.weight'])
    # (B2 依赖 S_1，在标定出 shift1 后再算)

    # ---- fc1/fc2 权重量化（与 shift 无关） ----
    WF1, S_wf1 = quantize_weights(sd['fc1.weight'])
    WF2, S_wf2 = quantize_weights(sd['fc2.weight'])

    # ---- 标定 shift（逐层，用 NCAL 张训练图） ----
    (trX, _), _ = load_mnist(DATA)
    Xcal = trX[:NCAL]
    a0 = lut[Xcal][:, None, :, :].astype(np.int64)
    acc1 = conv2d_np(a0, W1) + B1[None, :, None, None]
    sh1 = pick_shift(acc1)
    a1 = requant(acc1, sh1)
    a1p = maxpool_np(a1.astype(np.int64)).astype(np.int8)
    S1 = S_w1 * S0 * (2 ** sh1)

    B2 = np.round(sd['conv2.bias'].numpy() / (S_w2 * S1)).astype(np.int32)
    acc2 = conv2d_np(a1p.astype(np.int64), W2) + B2[None, :, None, None]
    sh2 = pick_shift(acc2)
    a2 = requant(acc2, sh2)
    a2p = maxpool_np(a2.astype(np.int64)).astype(np.int8)
    S2 = S_w2 * S1 * (2 ** sh2)

    af = a2p.reshape(a2p.shape[0], -1)
    BF1 = np.round(sd['fc1.bias'].numpy() / (S_wf1 * S2)).astype(np.int32)
    acc3 = fc_np(af, WF1) + BF1
    shf1 = pick_shift(acc3)
    a3 = requant(acc3, shf1)
    S3 = S_wf1 * S2 * (2 ** shf1)

    BF2 = np.round(sd['fc2.bias'].numpy() / (S_wf2 * S3)).astype(np.int32)

    print(f'[quant] shifts: conv1={sh1} conv2={sh2} fc1={shf1}', flush=True)

    # ---- 全测试集定点精度 ----
    (_, _), (teX, teY) = load_mnist(DATA)
    N = len(teX)
    correct = 0
    BS = 512
    for b in range(0, N, BS):
        Xb = teX[b:b + BS]
        lg = forward_int(Xb, lut, W1, B1, sh1, W2, B2, sh2, WF1, BF1, shf1, WF2, BF2)
        correct += int((lg.argmax(1) == teY[b:b + BS]).sum())
    acc = correct / N
    print(f'[quant] fixed-point test_acc = {acc*100:.3f}%  ({correct}/{N})', flush=True)

    # ---- 导出 weights.h ----
    lines = []
    lines.append('// 由 python/quantize.py 自动生成 —— 勿手改')
    lines.append(f'// 定点：int8 激活/权重、int32 累加、移位 requant；float 精度 {ck["test_acc"]*100:.2f}% -> 定点 {acc*100:.2f}%')
    lines.append('')
    lines.append(c_decl('act_t INPUT_LUT[256]', lut))
    lines.append(f'static const int SHIFT1 = {sh1};\n')
    lines.append(c_decl('act_t W1[16][1][3][3]', W1))
    lines.append(c_decl('acc_t B1[16]', B1))
    lines.append(f'static const int SHIFT2 = {sh2};\n')
    lines.append(c_decl('act_t W2[32][16][3][3]', W2))
    lines.append(c_decl('acc_t B2[32]', B2))
    lines.append(f'static const int SHIFT_FC1 = {shf1};\n')
    lines.append(c_decl('act_t WF1[64][800]', WF1))
    lines.append(c_decl('acc_t BF1[64]', BF1))
    lines.append(c_decl('act_t WF2[10][64]', WF2))
    lines.append(c_decl('acc_t BF2[10]', BF2))
    with open(os.path.join(HLS_DIR, 'weights.h'), 'w') as f:
        f.write('\n'.join(lines))
    print('[quant] wrote weights.h', flush=True)

    # ---- 导出 testdata（NTEST 张：vec_in.bin / vec_ref.bin） ----
    Xt = teX[:NTEST]
    with open(os.path.join(TESTDATA, 'vec_in.bin'), 'wb') as f:
        f.write(Xt.astype(np.uint8).tobytes())
    lg = forward_int(Xt, lut, W1, B1, sh1, W2, B2, sh2, WF1, BF1, shf1, WF2, BF2)
    with open(os.path.join(TESTDATA, 'vec_ref.bin'), 'wb') as f:
        f.write(lg.astype(np.int32).tobytes())
    print(f'[quant] wrote testdata ({NTEST} images)', flush=True)

    # ---- 保存量化参数 ----
    qmeta = {'S_in': S_in, 'S0': S0, 'S_w1': S_w1, 'S_w2': S_w2,
             'S_wf1': S_wf1, 'S_wf2': S_wf2,
             'shift1': sh1, 'shift2': sh2, 'shift_fc1': shf1,
             'fixed_test_acc': acc, 'float_test_acc': ck['test_acc']}
    with open(os.path.join(MODEL_DIR, 'quant.json'), 'w') as f:
        json.dump(qmeta, f, indent=2, ensure_ascii=False)
    print('[quant] wrote quant.json', flush=True)

    # 达标判定：定点相对浮点下降 < 1%（绝对百分点）
    drop = ck['test_acc'] - acc
    print(f'[quant] acc drop = {drop*100:.3f}%', flush=True)
    assert drop < 0.01, f'fixed-point acc drop {drop*100:.2f}% >= 1%'

if __name__ == '__main__':
    main()
