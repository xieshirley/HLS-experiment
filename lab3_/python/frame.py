# frame.py —— 帧协议（实验三，与 FPGA frame_decode.v / brief/方案书.md 一致）
# 帧：0xA5 0x5A | len(2B LE)=784 | seq(1B) | image(784B) | crc16(2B LE)
# CRC16-CCITT-FALSE：poly 0x1021, init 0xFFFF, 不反转, xorout 0；覆盖 [len..image]
import struct

HDR = bytes([0xA5, 0x5A])
IMG_LEN = 784


def crc16_ccitt(data):
    crc = 0xFFFF
    for b in data:
        crc ^= (b & 0xFF) << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def build_frame(img_bytes, seq):
    assert len(img_bytes) == IMG_LEN, f'img must be {IMG_LEN} bytes'
    length = struct.pack('<H', IMG_LEN)
    seqb = bytes([seq & 0xFF])
    payload = length + seqb + img_bytes
    crc = struct.pack('<H', crc16_ccitt(payload))
    return HDR + payload + crc


def parse_frame(buf, idx):
    """在 buf 中从 idx 起找一帧，返回 (frame_img_bytes, seq, next_idx)；找不到返回 (None, None, idx+1)。"""
    n = len(buf)
    while idx + 2 <= n and not (buf[idx] == 0xA5 and buf[idx + 1] == 0x5A):
        idx += 1
    if idx + 2 + 2 + 1 + IMG_LEN + 2 > n:
        return None, None, idx
    length = struct.unpack('<H', buf[idx + 2:idx + 4])[0]
    if length != IMG_LEN:
        return None, None, idx + 1
    seq = buf[idx + 4]
    img = buf[idx + 5:idx + 5 + IMG_LEN]
    crc_field = struct.unpack('<H', buf[idx + 5 + IMG_LEN:idx + 5 + IMG_LEN + 2])[0]
    payload = buf[idx + 2:idx + 5 + IMG_LEN]
    if crc16_ccitt(payload) != crc_field:
        return None, None, idx + 2          # CRC 错，丢弃重同步
    return img, seq, idx + 5 + IMG_LEN + 2
