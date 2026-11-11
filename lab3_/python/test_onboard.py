# test_onboard.py —— 上板识别测试：从 MNIST 测试集抽 N 张，经 COM 口发帧，统计正确率与耗时
# 运行：.venv\Scripts\python.exe python\test_onboard.py --port COM6 --baud 1000000 --n 100
#
# 时间构成说明（重要）：
#   上位机只能测到「发出帧 -> 收到结果」的**往返总时间**，看不到 FPGA 内部的 ap_start/ap_done。
#   因此这里把总分时间拆成三段：
#     串口传输 = 帧长(791B) × 10bit / 波特率        （协议固定，可精确计算）
#     回传字节 = 1B × 10bit / 波特率
#     板上推理 = 总计 - 串口传输 - 回传字节          （推算值，含少量 USB/驱动开销）
#   想要**实测**推理时间，需在 FPGA 侧加周期计数器并随结果回传（需重新综合）。
import argparse, sys, time
import numpy as np
import serial

sys.path.insert(0, __file__.rsplit('\\', 1)[0])
from mnist_io import load_mnist
from frame import build_frame

FRAME_BYTES = 791      # 帧头2+长度2+序号1+图像784+CRC2
RET_BYTES = 1          # 回传类别 1 字节


def centroid_center(img):
    ys, xs = np.mgrid[0:28, 0:28]
    m = img.astype(np.float64).sum()
    if m == 0:
        return img
    cx, cy = (xs * img).sum() / m, (ys * img).sum() / m
    dx, dy = int(round(13.5 - cx)), int(round(13.5 - cy))
    out = np.zeros_like(img)
    for y in range(28):
        for x in range(28):
            sx, sy = x - dx, y - dy
            if 0 <= sx < 28 and 0 <= sy < 28:
                out[y, x] = img[sy, sx]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default='COM6')
    ap.add_argument('--baud', type=int, default=115200)
    ap.add_argument('--n', type=int, default=20)
    ap.add_argument('--center', action='store_true', help='做重心居中')
    args = ap.parse_args()

    # 理论串口耗时（ms）
    t_frame_tx = FRAME_BYTES * 10.0 / args.baud * 1000.0
    t_ret_rx = RET_BYTES * 10.0 / args.baud * 1000.0

    (_, _), (teX, teY) = load_mnist('data')
    ser = serial.Serial(args.port, args.baud, timeout=2.0)
    time.sleep(0.5)
    ser.reset_input_buffer()

    print(f'port={args.port} baud={args.baud}  帧长={FRAME_BYTES}B  '
          f'理论串口={t_frame_tx:.1f}ms 回传={t_ret_rx:.2f}ms', flush=True)
    print('idx  true pred         总(ms)   串口(ms)  推理(ms)', flush=True)

    correct = 0
    tot, tx, inf = [], [], []
    for i in range(args.n):
        img = teX[i]
        if args.center:
            img = centroid_center(img)
        frame = build_frame(img.astype(np.uint8).tobytes(), seq=i & 0xFF)
        t0 = time.perf_counter()
        ser.write(frame)
        ser.flush()
        b = ser.read(1)
        dt = (time.perf_counter() - t0) * 1000.0
        pred = b[0] if b else -1
        ok = (pred == teY[i])
        correct += ok
        t_infer = dt - t_frame_tx - t_ret_rx
        tot.append(dt); tx.append(t_frame_tx); inf.append(t_infer)
        print(f'{i:3d} {teY[i]:5d} {pred:4d} {"OK" if ok else " X"}  '
              f'{dt:8.1f} {t_frame_tx:9.1f} {t_infer:9.1f}', flush=True)

    ser.close()
    print(f'=== {correct}/{args.n} correct ===', flush=True)
    print(f'平均: 总={np.mean(tot):.1f}ms  串口={np.mean(tx):.1f}ms  '
          f'推理(推算)={np.mean(inf):.1f}ms', flush=True)
    print('注：推理是「总 - 串口 - 回传」推算值，含少量 USB/驱动开销；'
          '要实测需 FPGA 回传周期计数。', flush=True)


if __name__ == '__main__':
    main()
