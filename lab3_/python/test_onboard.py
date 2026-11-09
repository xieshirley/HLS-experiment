# test_onboard.py —— 上板识别测试：从 MNIST 测试集抽 N 张，经 COM 口发帧，统计正确率与耗时
# 运行：.venv\Scripts\python.exe python\test_onboard.py --port COM6 --n 20
import argparse, sys, time
import numpy as np
import serial

sys.path.insert(0, __file__.rsplit('\\', 1)[0])
from mnist_io import load_mnist
from frame import build_frame


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

    (_, _), (teX, teY) = load_mnist('data')
    ser = serial.Serial(args.port, args.baud, timeout=2.0)
    time.sleep(0.5)
    ser.reset_input_buffer()

    correct = 0
    times = []
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
        times.append(dt)
        pred = b[0] if b else -1
        ok = (pred == teY[i])
        correct += ok
        print(f'img {i:2d}: true={teY[i]} pred={pred}  {"OK" if ok else "X"}  {dt:.1f} ms', flush=True)
    ser.close()
    print(f'=== {correct}/{args.n} correct, avg={np.mean(times):.1f} ms ===', flush=True)


if __name__ == '__main__':
    main()
