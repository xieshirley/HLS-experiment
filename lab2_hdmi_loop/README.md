# 实验二：HDMI 环回 + HLS 视频处理级联（灰度 / 高斯平滑 / 拉普拉斯锐化）

在达芬奇 A35T 板（`xc7a35tfgg484-2`）上完成 1080p60 HDMI 环回，并把 HLS 生成的视频核插入
"输入 → 处理 → 输出" 通路。四档功能由 `hdmi_loop.v` 里的一个编译期常量 `MODE` 选择。

```
HDMI IN ──> hdmi_rx ──video_rgb/de/hs/vs──> video_core ──> video_sync ──> hdmi_tx ──> HDMI OUT
                                             (HLS 核)      (同步重建)
```

* 工具：Vivado 2018.3 / Vivado HLS 2018.3
* 视频：1920×1080@60，`pixel_clk = 148.5 MHz`（6.734 ns），1 行 = 2200 拍（1920 有效 + 280 消隐），1125 行/帧
* 资源（锐化档，实现后）：LUT 4072/20800（19.6%）、FF 4138/41600（10.0%）、BRAM 5/50、DSP 1/90
* 时序：WNS **+0.151 ns**，TNS 0，违例端点 0

---

## 1. 四档模式

| MODE | 功能 | 送编码器的像素 | 同步方式 | 总延迟 |
|:--:|---|---|---|:--:|
| **0** | 直入直出 | `video_rgb` 纯直连（**零寄存器**，等价厂家原始环回） | 直接用 `hdmi_rx` 的 hs/vs/de | 0 |
| **1** | 灰度 | `rgb2gray` | DE 跟核 `TVALID`（`USE_FIFO_OUT=0`） | 3 拍 |
| **2** | 高斯平滑 | `gauss3x3` | 定长 DE 延迟 + 像素 FIFO（`USE_FIFO_OUT=1`） | 2211 拍 |
| **3** | 拉普拉斯锐化 | `unsharp3x3` | 同上 | 2213 拍 |

切换方式（任务四已实现**运行时**切换）：**按 KEY0 一次，模式 +1（模 4）**，
当前模式显示在 `led[1:0]` 上（`00`=直通 `01`=灰度 `10`=平滑 `11`=锐化）。

> 四档在硬件里**同时存在**（三路 `video_sync` 并行 + 4 选 1 mux），
> 所以**一颗比特流覆盖全部四档**，不再需要为每档单独综合。

---

## 2. `video_core.v`：两个 HLS 核并联

```
rgb_in ──> rgb2gray ──┬─────────────────────────────> gray_out / gray_valid
   de_in              ├──[16 深弹性 FIFO]──> gauss3x3   ──> gauss_out / gauss_valid
                      └──[16 深弹性 FIFO]──> unsharp3x3 ──> sharp_out / sharp_valid
```

* 每个核前面各有一个 **16 深弹性 FIFO**：HLS 核每行会顶住 1 拍（每行推进 1921 次、
  只拿到 1920 个输入像素），由 FIFO 吸收，**不丢像素**；
* 两个核**并联**、各走各的出口，**不需要任何跨核对齐**（这是踩坑后改的架构，见 §5）；
* 灰度核 `dst` 的 `TREADY` 恒接 `1'b1`，不反压。

### HLS 核参数（csynth 实测）

| 核 | 功能 | 系数 | II | 流水级数 | Latency | Trip Count |
|---|---|---|:--:|:--:|--:|--:|
| `rgb2gray` | RGB→YUV 取 Y | 定点 0.299/0.587/0.114 | 1 | — | — | — |
| `gauss3x3` | 3×3 高斯平滑 | `[1 2 1; 2 4 2; 1 2 1]/16` | **1** | 5 | 2,076,604 | 2,076,601 |
| `unsharp3x3` | 3×3 拉普拉斯锐化 | `[0 -1 0; -1 5 -1; 0 -1 0]` | **1** | 7 | 2,076,606 | 2,076,601 |

两个核都用 `hls::stream` 接口 + `ap_ctrl_none`，每拍一像素（1080p60 只用 148.5 MHz 的 1/1 时钟）。

### 拉普拉斯锐化核（`hls_prj/unsharp3x3/unsharp3x3.cpp`）

```c
T2 ref[REF_ROWS][REF_COLS] = {
    {  0, -1,  0 },
    { -1,  5, -1 },
    {  0, -1,  0 }
};
typedef ap_fixed<22,12> T4;            // 取值 [−1020, 1275]，需 12 位整数位
T4 d;
d = 0;
for (ii) for (jj) d += (T4)ref[ii][jj] * (T4)wlb.getval(REF_ROWS-1-ii, REF_COLS-1-jj);

if (d < 0) dd = 0; else if (d > 255) dd = 255; else dd = d;
```

即 `out = 5*center − (up + down + left + right)`。三条性质（`tb_unsharp_num.v` 实测）：

| 输入 | 输出 | 说明 |
|---|---|---|
| 平坦区 | `5c − 4c = c` | 恒等，**不变亮也不变暗** |
| 线性渐变 | 恒等 | 与高斯平滑同性质 |
| 台阶边缘 | 过冲/欠冲 | 例：`5×219 − 657 = 438 → 限幅 255`；`−219 → 0` |

---

## 3. `video_sync.v`：输出同步重建

处理核本身有 1 行多的延迟，必须把 `hs/vs/de` 一起延迟同样的拍数才能对上。

| 信号 | 做法 |
|---|---|
| `hs` / `vs` | 3 bit 打包进同一条 **SRL 移位链**，按 `LATENCY` 精确延迟（`use_fifo_out=0` 时 DE 也走这条链） |
| `de`（FIFO 模式） | 用**输入 DE 的定长延迟**做显示窗口，像素从 **4096 深 FIFO** 里按 FIFO 顺序取出 |
| 诊断输出 | `und_evt`（DE 有效但 FIFO 空 → 黑像素）、`ovf_evt`（FIFO 满丢像素 → 撕裂） |

`LATENCY` 由实测确定（见 §4），`LAT = (LATENCY < 2) ? 2 : LATENCY` 防止 `LATENCY=1` 时位选出错。

---

## 4. 延迟标定（关键数字）

| 量 | 数值 | 怎么测的 |
|---|--:|---|
| 高斯流比输入 DE 晚 | **2211 拍** | `tb_offset.v`：`LAT=2205` 时相位偏移 **+6** → 2205+6 |
| 拉普拉斯流比高斯流再晚 | **2 拍** | csynth 流水级数 7 vs 5 |
| 像素 FIFO 在途像素（对齐 FIFO 峰值） | 约 1924~1928 | `tb_sharp_full.v` |

`hdmi_loop.v` 里的常量：

```verilog
localparam integer SYNC_BASE   = 2211;   // 实测 gauss 流延迟
localparam integer SYNC_MARGIN = 0;      // 留余量只会把黑条从左边缘挪到右边缘
localparam integer SHARP_PIPE  = 2;      // 锐化核比高斯核多 2 级流水
localparam integer SYNC_LATENCY = (MODE == 2) ? SYNC_BASE + SYNC_MARGIN :              // 2211
                                  (MODE == 3) ? SYNC_BASE + SYNC_MARGIN + SHARP_PIPE : 3;  // 2213
```

> 校准方法：若 `SYNC_LATENCY` 偏小 → DE 比数据早到 → 左边黑条 + `led[2]` 亮；
> 偏大 → 数据被截 → 右边黑条。用 `led[2]/led[3]` 二分即可，不必靠肉眼数像素。

完整推导与测量数据见 **[doc/调试日志_实验2_最终版.md](doc/调试日志_实验2_最终版.md)**。

---

## 4.5 任务四：按键运行时切换模式

### 4.5.1 顶层改动

| 改动 | 内容 |
|---|---|
| 新增端口 | `input [3:0] key`（按下为低） |
| 新增模块 | `sources_1/new/key_mode.v`：消抖 + 边沿检测 + 模式计数 |
| 三路同步并行 | `u_sync_gray`(LAT=3) / `u_sync_gauss`(LAT=2211) / `u_sync_sharp`(LAT=2213) |
| 4 选 1 mux | 按 `mode_pix` 选 直通 / 灰度 / 平滑 / 锐化，统一打 1 拍后送 `dvi_transmitter_top` |
| LED | `led[1:0]`=模式号，`led[2]`=当前档欠载，`led[3]`=当前档溢出 |

### 4.5.2 消抖与跨时钟域

```verilog
key_mode #(.CLK_FREQ(50_000_000), .DEB_MS(15), .KEY_ACTIVE_LOW(1)) u_key_mode(...);
```

* **计数消抖**：电平必须稳定 **15 ms**（50 MHz → 750,000 拍）才被承认；
  抖动期间计数器反复清零，短于 15 ms 的毛刺直接被吃掉。
* **边沿检测**：只在「未按 → 按下」的消抖后跳变产生 1 拍脉冲 → **长按不会连跳**。
* **模 4 计数用格雷码**：步进 `00→01→11→10→00`，每次只变 1 位；
  这样跨到 `pixel_clk`（148.5 MHz）域时用普通 **2 级同步器**就安全，不会出现非法中间码。
* 消抖跑在 **`sys_clk`（50 MHz，板上独立晶振）** 上，与 HDMI 有无输入无关；
  `led[1:0]` 也取自 sys 域，所以**没有 HDMI 输入时按键仍能看到模式变化**。

### 4.5.3 XDC 引脚（抄自达芬奇官方 `DaVinci_FPGA_IO.xdc`）

```tcl
# key[0]=T1  key[1]=U1  key[2]=W2  key[3]=T3  （LVCMOS33，按下为低）
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33} [get_ports {key[0]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33} [get_ports {key[1]}]
set_property -dict {PACKAGE_PIN W2 IOSTANDARD LVCMOS33} [get_ports {key[2]}]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33} [get_ports {key[3]}]
```

`sys_clk`（50 MHz 消抖时钟）用官方引脚 **R4**，约束 `create_clock -period 20.000`。

> **踩坑一**：加按键后 `u_key_mode → mode_meta`（sys_clk → pixel_clk）这条跨域路径
> 被按 6.734 ns 分析，实测 **WNS −3.392 ns**。必须声明四域异步：
>
> ```tcl
> set_clock_groups -asynchronous \
>     -group [get_clocks -of_objects [get_nets pixel_clk]] \
>     -group [get_clocks -of_objects [get_ports sys_clk]] \
>     -group [get_clocks clk_out1_mmcm] \
>     -group [get_clocks clk_out2_mmcm]
> ```
>
> **踩坑二**：**XDC 文件不支持 `if` 语句**（`CRITICAL WARNING: Command 'if' is not supported`），
> 我曾用 `if` 包裹这段约束，结果整段被忽略 → WNS 恶化到 −4.726 ns。去掉 `if` 后 **WNS +0.374 ns**。

### 4.5.4 验证

| 项 | 结果 |
|---|---|
| `tb_key_mode.v` | **PASS**：带抖动按一次只加 1；按住 60 ms 不连跳；连按 5 次 0→1→2→3→0→1（模 4 回绕）；5 ms 短脉冲被滤除；`key_press` 共 5 次 ✓ |
| 综合/实现 | 0 error / 0 critical warning；**WNS +0.374 ns，无违例路径** |
| 资源 | LUT 5356/20800（25.8%）、FF 4269/41600（10.3%）、BRAM 5/50、DSP 1/90（三路同步链使 LUT 从 4072 增到 5356） |
| 引脚 | `key[0]=T1`、`key[1]=U1`、`key[2]=W2`、`key[3]=T3` 均已 FIXED |
| 比特流 | `bit_out/hdmi_loop_V11_MODE_key_runtime.bit`（一颗覆盖四档） |

---
## 5. 踩过的三个坑（详见 `doc/调试日志_实验2_最终版.md` §4、§11）

**① XDC 缺像素时钟约束（决定性）**
`create_clock -period 6.734 -name pixel_clk [get_nets pixel_clk]` 漏写时，高斯核路径时序不收敛
（slack −2.233 ns、311 条违例），上板表现为花屏/无信号。加上后 0 违例。

**② 像素 FIFO 深度不足 → 每帧溢出 → 画面撕裂**
高斯核每帧有一整行"**只写不读**"的补 0 行（内部 `i = 1080`），它的 **1920 个输出挤在消隐期吐出**；
而消隐期显示端不读 → 512 深的 FIFO 装不下 → **每帧溢出约 1400 个像素** → 上一帧内容混进帧首
（"两帧重写"）。修法：`video_sync` 的像素 FIFO 加深到 **4096**（≥ 一整行）。

**③ RTL 外部配对方案在帧边界必崩 → 锐化改成核内实现**
最初用 RTL 做 `sharp = 2*orig − smooth`，靠"灰度 FIFO 与高斯输出逐像素配对"。上板症状：
左边固定黑条（改延迟 2208/2218/2278/4414 位置不变）、画面逐帧下移。
根因：帧末的 1920 拍突发把对齐 FIFO 抽空 → 新帧开头 `pempty` 屏蔽约 1920 次配对 →
**每帧少 1 行配对**；4096 深的像素 FIFO 又把这个缺口吃掉，所以诊断 LED 全灭、查不出来。

> 结论：**锐化必须放进 HLS 核内算**（核本来就有窗口中心像素），
> 这样锐化流与已验证的平滑流架构完全同构，不再有任何帧边界对齐问题。

三个坑的完整证据链（仿真输出、LED 读数、失败构建对比）见
[doc/调试日志_实验2_最终版.md](doc/调试日志_实验2_最终版.md)。

---

## 6. 板级诊断

| LED | 含义 |
|:--:|---|
| `led[0]` | 高斯核上一帧有出数（常亮 = gauss 有输出） |
| `led[1]` | 灰度核上一帧有出数（常亮 = gray 有输出） |
| `led[2]` | **本帧出现过欠载**（DE 读到空 FIFO → 左黑条 → 延迟给小了） |
| `led[3]` | **本帧出现过溢出**（FIFO 满丢像素 → 撕裂 → 深度不够） |

另有 ILA（`dbg_ila`）挂在 `hdmi_loop.v` 的 `video_dbg` 上，可用于抓
`gray_valid/gauss_valid/de_proc/hs_proc/vs_proc/gauss_w/sharp_w`。

烧写脚本：`sim_check/program_hw.tcl`（bit + probes 一起下，先清残留探针避免 `27-3412` 不匹配）。

> 本机注意：**TCP 3121 落在 Windows 保留端口段（2944–3146），`hw_server` 起不来**
> （Vivado 报 `[Labtools 27-2220] Unable to launch local hw_server`）。
> 解决：先跑 `sim_check/start_hw_server.bat`（监听 **3270**），再在 Tcl 里
> `connect_hw_server -url localhost:3270`。

---

## 7. 仿真与 testbench

仿真脚本：`sim_check/prep_sim_dir.bat <目录>`（一键准备 RTL + `.dat` + tb）、`run_compile.bat`、`run_sim.bat`。
**必须用独立目录/独立库名**跑，否则默认 `work` 库会被旧快照污染（`xvlog` 卡死或 `xelab` 命中旧 tb）。

> **仿真里前几行是红色（X）的两个原因**（都已修）：
> 1. **HLS 行缓存 BRAM 的 `.dat` 不在仿真目录** → `xsim` 报
>    `WARNING: File ./gauss3x3_wlb_lb_vbkb_ram.dat ... cannot be opened`，核输出前两行是 X。
>    用 `prep_sim_dir.bat` 准备目录即可（它会拷 `*.dat`）。
> 2. 我们自己 RTL 的 FIFO/SRL 没有上电初值 → 已在 `video_sync.v` / `video_core.v` 里加
>    `` `ifndef SYNTHESIS `` 的 `initial` 清零块（**综合被排除，不影响 BRAM/SRL 推断**）。
>    `tb_xcheck.v` 用来回归这一点。

| testbench | 验证内容 | 结果 |
|---|---|---|
| `tb_video_sync.v` | hs/vs 延迟、DE 跟随、像素直通（真值比对） | PASS |
| `tb_vsync2.v` | `video_sync` 模块级真值链 | PASS |
| `tb_graylat.v` | `rgb2gray` 延迟、规范 AXIS 源 | PASS |
| `tb_offset.v` | 高斯流相对输入 DE 的相位（LAT 扫描）+ 在途像素 | LAT=2215/2218 偏移 0 |
| `tb_sharp_full.v` | **整帧 1080 行**：gray/gauss/sharp 各 2,073,600 拍、FIFO 0 溢出 0 欠载 | PASS |
| `tb_unsharp_num.v` | 锐化核数值（台阶过冲 / 平坦区恒等） | 公式逐点吻合 |
| `tb_xcheck.v` | **上电初期是否出现 X**（gauss/sharp/rgb_out/de-hs-vs） | PASS：4 类信号 X 计数全 0 |
| `tb_core_chain.v` | 双核级联通路（灰度→高斯） | PASS |
| `tb_sharp.v` | 早期 RTL 配对版逐点比对（已由 HLS 方案取代，留作历史记录） | err=0 |
| `tb_gauss_demo.v` / `tb_shift_demo.v` / `tb_probe.v` | 演示与 ILA 探针 | — |

---

## 8. 比特流与重建

`bit_out/` 未入库（35 MB 二进制）。用 `sim_check/build_bar.tcl` 重新生成：

```bash
cd lab2_hdmi_loop/sim_check
vivado -mode batch -source build_bar.tcl      # 综合+实现+bitstream
```

已生成的档位（改 `hdmi_loop.v` 的 `MODE` 后各跑一次）：

| 文件 | 内容 | `SYNC_LATENCY` |
|---|---|--:|
| `hdmi_loop_V8_MODE2_smooth.bit` | 高斯平滑（上板验证正常） | 2211 |
| `hdmi_loop_V8_MODE3_sharp.bit` | 非锐化掩模 k=1（结构验证用，效果细微） | 2212 |
| `hdmi_loop_V9_MODE3_sharp_k2.bit` | 非锐化掩模 k=2（对照） | 2212 |
| `hdmi_loop_V10_MODE3_laplace.bit` | **拉普拉斯核（最终版）** | 2213 |

---

## 9. 复现步骤

1. **打开工程**：`vivado_prj/hdmi_loop/hdmi_loop.xpr`（Vivado 2018.3，器件 `xc7a35tfgg484-2`）。
   若不入库 `.xpr`，新建工程后导入 `hdmi_loop.srcs/`（`sources_1`、`constrs_1`）。
2. **重建 HLS 核（可选，仓库已含生成 RTL）**

   ```bash
   cd hls_prj/unsharp3x3 && vivado_hls -f run_hls.tcl     # 或 gauss3x3 / rgb2gray
   ```

   把 `solution1/syn/verilog/*.v` 和 `*_ram.dat` 拷到
   `hdmi_loop.srcs/sources_1/imports/hls/unsharp3x3/`。
3. **选模式**：改 `hdmi_loop.v` 的 `MODE`。
4. **出比特流**：`vivado -mode batch -source sim_check/build_bar.tcl`。
5. **上板**：`start_hw_server.bat` → `connect_hw_server -url localhost:3270` →
   `source sim_check/program_hw.tcl`。

---

## 10. 目录结构

```
lab2_hdmi_loop/
├── vivado_prj/hdmi_loop/                    # Vivado 工程
│   ├── hdmi_loop.xpr
│   └── hdmi_loop.srcs/
│       ├── sources_1/new/                   # video_core.v / video_sync.v（手写）
│       ├── sources_1/imports/53_hdmi_loop/  # 厂家 hdmi_loop 骨架 + hdmi_loop.v（顶层，改模式表）
│       ├── sources_1/imports/hls/           # HLS 生成 RTL（rgb2gray / gauss3x3 / unsharp3x3）
│       └── constrs_1/new/hdmi_loop.xdc      # 像素时钟约束 + 引脚
├── hls_prj/                                 # HLS 源码（cpp/h/tcl）
│   ├── rgb2gray/  gauss3x3/  unsharp3x3/
├── sim_check/                               # testbench + 仿真/构建/烧写脚本
├── doc/                                     # 调试日志、修改日志、约束、参考源码
├── bit_out/                                 # 比特流（不入库）
└── test_image/                              # 测试图案（渐变/灰阶/文字/棋盘格…，不入库）
```

---

## 11. 已知限制

* 模式切换已**运行时化**（KEY0 循环 4 档）；若要一键直达某档，可扩成 4 个按键各自选一档；
* 锐化**图像最外圈 1~2 像素会偏亮**：窗口在边界补 0，`5c − 4邻` 在边缘产生正向过冲，属算法固有；
  需要时可加"首末行/首尾列屏蔽"；
* `gauss3x3` / `unsharp3x3` 的行长是 1921（1920 读 + 1 次行末补 0），因此**每行有 1 拍反压**，
  已由 16 深弹性 FIFO 吸收；若要彻底消除可把 HLS 行长改成 1920。
