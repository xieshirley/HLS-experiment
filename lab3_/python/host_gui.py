# host_gui.py —— 上位机画板（实验三 G7）：28×28 手写画板 + 重心居中 + 串口发帧 + 计时
# 运行：.venv\Scripts\python.exe python\host_gui.py [--port COMx] [--baud 115200|1000000]
import argparse, sys, time, threading
import tkinter as tk
import numpy as np
import serial
import serial.tools.list_ports

sys.path.insert(0, __file__.rsplit('\\', 1)[0])
from frame import build_frame, IMG_LEN

CELL = 12          # 每像素显示尺寸
SIZE = 28
CANVAS = SIZE * CELL


class App:
    def __init__(self, root, port, baud):
        self.root = root
        self.img = np.zeros((SIZE, SIZE), dtype=np.uint8)
        self.ser = None
        self.port = port
        self.baud = baud
        self.last_ms = 0.0

        self.cv = tk.Canvas(root, width=CANVAS, height=CANVAS, bg='black')
        self.cv.pack()
        self.cv.bind('<B1-Motion>', self.draw)
        self.cv.bind('<Button-1>', self.draw)

        bar = tk.Frame(root); bar.pack()
        tk.Button(bar, text='Clear', command=self.clear).pack(side='left')
        tk.Button(bar, text='Send', command=self.send).pack(side='left')
        tk.Label(bar, text='Centroid:').pack(side='left')
        self.center_var = tk.BooleanVar(value=True)
        tk.Checkbutton(bar, variable=self.center_var).pack(side='left')
        self.result_lbl = tk.Label(root, text='result: -', font=('Consolas', 24))
        self.result_lbl.pack()
        self.time_lbl = tk.Label(root, text='time: - ms', font=('Consolas', 14))
        self.time_lbl.pack()
        self.port_lbl = tk.Label(root, text=f'port={port} baud={baud}', font=('Consolas', 10))
        self.port_lbl.pack()

        self.root.after(200, self.poll_serial)

    def draw(self, e):
        x, y = e.x // CELL, e.y // CELL
        if 0 <= x < SIZE and 0 <= y < SIZE:
            # 笔触 3x3 圆点（黑底白字，与 MNIST 一致）
            for i in range(-1, 2):
                for j in range(-1, 2):
                    xx, yy = x + i, y + j
                    if 0 <= xx < SIZE and 0 <= yy < SIZE:
                        self.img[yy, xx] = 255
            self.redraw()

    def redraw(self):
        self.cv.delete('all')
        for y in range(SIZE):
            for x in range(SIZE):
                if self.img[y, x]:
                    self.cv.create_rectangle(x*CELL, y*CELL, (x+1)*CELL, (y+1)*CELL,
                                             fill='white', outline='white')

    def clear(self):
        self.img[:] = 0
        self.redraw()
        self.result_lbl.config(text='result: -')
        self.time_lbl.config(text='time: - ms')

    def centroid_center(self, img):
        ys, xs = np.mgrid[0:SIZE, 0:SIZE]
        m = img.astype(np.float64).sum()
        if m == 0:
            return img
        cx, cy = (xs * img).sum() / m, (ys * img).sum() / m
        dx, dy = int(round(SIZE/2 - 0.5 - cx)), int(round(SIZE/2 - 0.5 - cy))
        out = np.zeros_like(img)
        for y in range(SIZE):
            for x in range(SIZE):
                sx, sy = x - dx, y - dy
                if 0 <= sx < SIZE and 0 <= sy < SIZE:
                    out[y, x] = img[sy, sx]
        return out

    def send(self):
        img = self.centroid_center(self.img) if self.center_var.get() else self.img
        frame = build_frame(img.astype(np.uint8).tobytes(), seq=0)
        if self.ser is None:
            self.result_lbl.config(text='no serial')
            return
        t0 = time.perf_counter()
        self.ser.write(frame)
        self.ser.flush()
        # 读 1 字节结果（带超时）
        self.ser.timeout = 1.0
        b = self.ser.read(1)
        t1 = time.perf_counter()
        self.last_ms = (t1 - t0) * 1000.0
        if b:
            self.result_lbl.config(text=f'result: {b[0]}')
            self.time_lbl.config(text=f'time: {self.last_ms:.1f} ms')
        else:
            self.result_lbl.config(text='timeout')
            self.time_lbl.config(text=f'time: {self.last_ms:.1f} ms')

    def poll_serial(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        if self.ser is None and self.port:
            try:
                self.ser = serial.Serial(self.port, self.baud, timeout=1.0)
                self.port_lbl.config(text=f'port={self.port} baud={self.baud} OPEN')
            except Exception as e:
                self.port_lbl.config(text=f'port={self.port} ERR {e}')
        elif self.ser is not None and self.port and self.port not in ports:
            self.ser.close(); self.ser = None
            self.port_lbl.config(text=f'port={self.port} baud={self.baud} CLOSED')
        self.root.after(1000, self.poll_serial)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default=None)
    ap.add_argument('--baud', type=int, default=115200)
    args = ap.parse_args()
    root = tk.Tk()
    root.title('lab3 手写数字画板')
    App(root, args.port, args.baud)
    root.mainloop()


if __name__ == '__main__':
    main()
