# mnist_io.py —— MNIST 下载与解析（不依赖 torchvision，自写 idx 解析器）
# 用法：from mnist_io import load_mnist
#   (X_train, y_train), (X_test, y_test) = load_mnist(data_dir='../data')
import os, gzip, struct, hashlib, ssl, time, shutil, urllib.request
import numpy as np

FILES = {
    'train-images-idx3-ubyte.gz': 'f68b3c2dcbeaaa9fbdd348bbdeb94873',
    'train-labels-idx1-ubyte.gz': 'd53e105ee54ea40749a09fcbcd1e9432',
    't10k-images-idx3-ubyte.gz':  '9fb629c4189551a2d022fa330f9573f3',
    't10k-labels-idx1-ubyte.gz':  'ec29112dd5afa0611ce80d1b7f02629c',
}
# 镜像按顺序尝试（GCS 官方镜像优先，其次 S3，最后原始站点）
MIRRORS = [
    'https://storage.googleapis.com/cvdf-datasets/mnist/',
    'https://ossci-datasets.s3.amazonaws.com/mnist/',
    'http://yann.lecun.com/exdb/mnist/',
]
# 本机系统证书库对部分 https 报 "Missing Subject Key Identifier"，用不校验证书的上下文下载公开数据
_SSL_CTX = ssl._create_unverified_context()


def _download(url, dest, timeout=45, retries=4):
    last = None
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'lab3-mnist/1.0'})
            with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CTX) as r, open(dest, 'wb') as f:
                shutil.copyfileobj(r, f, 65536)
            return
        except Exception as e:
            last = e
            print(f'    attempt {attempt}/{retries} fail: {e}', flush=True)
            time.sleep(2)
    raise last


def ensure_data(data_dir):
    os.makedirs(data_dir, exist_ok=True)
    for name, md5 in FILES.items():
        path = os.path.join(data_dir, name)
        if os.path.exists(path):
            if hashlib.md5(open(path, 'rb').read()).hexdigest() == md5:
                continue
            os.remove(path)
        ok = False
        for base in MIRRORS:
            url = base + name
            try:
                print(f'[mnist_io] download {url} ...', flush=True)
                _download(url, path)
                if hashlib.md5(open(path, 'rb').read()).hexdigest() == md5:
                    ok = True
                    break
                os.remove(path)
            except Exception as e:
                print(f'[mnist_io] fail {url}: {e}')
        if not ok:
            raise RuntimeError(f'cannot download {name} from any mirror')


def _parse_idx(path):
    with gzip.open(path, 'rb') as f:
        magic = struct.unpack('>I', f.read(4))[0]
        ndim = magic & 0xFF          # 低字节是维度数
        dtype = (magic >> 8) & 0xFF  # 0x08=uint8
        assert dtype == 0x08, f'unsupported dtype 0x{dtype:02x}'
        dims = struct.unpack('>' + 'I' * ndim, f.read(4 * ndim))
        data = np.frombuffer(f.read(), dtype=np.uint8).reshape(dims)
    return data


def load_mnist(data_dir='data'):
    ensure_data(data_dir)
    trX = _parse_idx(os.path.join(data_dir, 'train-images-idx3-ubyte.gz'))
    trY = _parse_idx(os.path.join(data_dir, 'train-labels-idx1-ubyte.gz'))
    teX = _parse_idx(os.path.join(data_dir, 't10k-images-idx3-ubyte.gz'))
    teY = _parse_idx(os.path.join(data_dir, 't10k-labels-idx1-ubyte.gz'))
    return (trX, trY), (teX, teY)
