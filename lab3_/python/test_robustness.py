# test_robustness.py —— 健壮性：错包/乱码/截断后必须能重同步并继续识别
# 用法：.venv\Scripts\python.exe python\test_robustness.py --port COM6 --baud 1000000
import argparse, sys, time, random
import serial

sys.path.insert(0, __file__.rsplit('\\', 1)[0])
from mnist_io import load_mnist
from frame import build_frame


def send_valid(ser, img, seq):
    f = build_frame(img.tobytes(), seq & 0xFF)
    ser.reset_input_buffer()
    ser.write(f)
    ser.flush()
    b = ser.read(1)
    return b[0] if b else -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default='COM6')
    ap.add_argument('--baud', type=int, default=115200)
    args = ap.parse_args()

    (_, _), (teX, teY) = load_mnist('data')
    ser = serial.Serial(args.port, args.baud, timeout=1.0)
    time.sleep(0.3)

    print(f'port={args.port} baud={args.baud}', flush=True)
    print('baseline      :', send_valid(ser, teX[0], 0), '(true', teY[0], ')', flush=True)

    # 1) 图像字节被翻转 -> CRC 错
    bad = bytearray(build_frame(teX[0].tobytes(), 1))
    bad[10] ^= 0xFF
    ser.write(bytes(bad)); ser.flush(); time.sleep(0.2)
    print('after bad-crc :', send_valid(ser, teX[1], 2), '(true', teY[1], ')', flush=True)

    # 2) 300 字节随机乱码（无帧头）
    random.seed(1)
    ser.write(bytes(random.randint(0, 255) for _ in range(300))); ser.flush(); time.sleep(0.2)
    print('after garbage :', send_valid(ser, teX[2], 3), '(true', teY[2], ')', flush=True)

    # 3) 截断帧（只发 200 字节）
    ser.write(build_frame(teX[0].tobytes(), 4)[:200]); ser.flush(); time.sleep(0.2)
    print('after trunc   :', send_valid(ser, teX[3], 5), '(true', teY[3], ')', flush=True)

    ser.close()
    print('=== robustness done ===', flush=True)


if __name__ == '__main__':
    main()
