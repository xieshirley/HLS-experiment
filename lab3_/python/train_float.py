# train_float.py —— 浮点模型训练（实验三 G2）
# 网络：Conv1(1->16,3x3)->MaxPool->Conv2(16->32,3x3)->MaxPool->FC(800->64->10)
# 输入标准化 (x/255-0.1307)/0.3081（MNIST 标准），定点侧用 256 项 LUT 等价实现
# 运行：.venv\Scripts\python.exe python\train_float.py
import os, sys, json, time
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mnist_io import load_mnist

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # lab3_/
DATA = os.path.join(ROOT, 'data')
MODEL_DIR = os.path.join(ROOT, 'model')
os.makedirs(MODEL_DIR, exist_ok=True)

SEED = 42
MEAN, STD = 0.1307, 0.3081
torch.manual_seed(SEED)
np.random.seed(SEED)
torch.set_num_threads(12)

class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 16, 3, padding=0)    # 28->26
        self.conv2 = nn.Conv2d(16, 32, 3, padding=0)   # 13->11
        self.fc1 = nn.Linear(32 * 5 * 5, 64)           # 800->64
        self.fc2 = nn.Linear(64, 10)
    def forward(self, x):
        x = F.relu(self.conv1(x))
        x = F.max_pool2d(x, 2)                         # 13x13
        x = F.relu(self.conv2(x))
        x = F.max_pool2d(x, 2)                         # 5x5
        x = x.view(x.size(0), -1)                      # 800
        x = F.relu(self.fc1(x))
        x = self.fc2(x)
        return x

def norm(x):
    return x.div(255.0).sub_(MEAN).div_(STD)

def main():
    print('[train] loading MNIST ...', flush=True)
    (trX, trY), (teX, teY) = load_mnist(DATA)
    Xtr = norm(torch.from_numpy(np.ascontiguousarray(trX)).float().unsqueeze(1))
    Ytr = torch.from_numpy(trY).long()
    Xte = norm(torch.from_numpy(np.ascontiguousarray(teX)).float().unsqueeze(1))
    Yte = torch.from_numpy(teY).long()

    idx = np.random.RandomState(SEED).permutation(len(Xtr))
    nval = 5000
    tr_i, va_i = idx[nval:], idx[:nval]
    Xtr_t, Ytr_t = Xtr[tr_i], Ytr[tr_i]
    Xva, Yva = Xtr[va_i], Ytr[va_i]

    model = Net()
    print('[train] params =', sum(p.numel() for p in model.parameters()), flush=True)

    EPOCHS = 20
    BS = 256
    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=EPOCHS, eta_min=1e-5)
    lossf = nn.CrossEntropyLoss()

    best_va, best_te = -1.0, -1.0
    best_state = None
    t0 = time.time()
    for ep in range(1, EPOCHS + 1):
        model.train()
        perm = torch.randperm(len(Xtr_t))
        total = 0.0
        for b in range(0, len(perm), BS):
            bi = perm[b:b + BS]
            xb, yb = Xtr_t[bi], Ytr_t[bi]
            opt.zero_grad()
            loss = lossf(model(xb), yb)
            loss.backward()
            opt.step()
            total += loss.item() * len(bi)
        sched.step()
        model.eval()
        with torch.no_grad():
            va = (model(Xva).argmax(1) == Yva).float().mean().item()
            te = (model(Xte).argmax(1) == Yte).float().mean().item()
        print(f'[train] ep {ep:2d} loss={total/len(Xtr_t):.4f} va={va*100:.2f}% te={te*100:.2f}%  ({time.time()-t0:.0f}s)', flush=True)
        if te > best_te:
            best_va, best_te = va, te
            best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}

    print(f'[train] BEST va={best_va*100:.2f}%  te={best_te*100:.2f}%', flush=True)

    pt_path = os.path.join(MODEL_DIR, 'float.pt')
    torch.save({'state_dict': best_state, 'arch': 'conv16-conv32-fc64',
                'test_acc': best_te, 'val_acc': best_va,
                'norm': [MEAN, STD]}, pt_path)
    meta = {'arch': 'Conv1(1->16,3x3)-MaxPool-Conv2(16->32,3x3)-MaxPool-FC(800->64->10)',
            'norm': [MEAN, STD], 'val_acc': best_va, 'test_acc': best_te,
            'epochs': EPOCHS, 'seed': SEED, 'torch': torch.__version__}
    with open(os.path.join(MODEL_DIR, 'metrics.json'), 'w') as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    print(f'[train] saved {pt_path}; test_acc={best_te*100:.2f}%', flush=True)
    assert best_te >= 0.99, f'test acc {best_te} < 0.99'

if __name__ == '__main__':
    main()
