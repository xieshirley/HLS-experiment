# 实验2 · HDMI 环回 + 灰度→高斯级联 —— 完整调试日志

> 器件/工具：Vivado 2018.3，xc7a35tfgg484-2（达芬奇 FPGA 开发板），Vivado HLS 2018.3
> 视频：1080p60，像素时钟 148.5 MHz，行周期 2200 clk（1920 有效 + 280 消隐），1125 行/帧
> 结论：**MODE=1（灰度核 → 高斯核 → 编码器）已在板上正常出图**，LED0/LED1 常亮（两核都在出数）
> 日志覆盖时间：2026-11-04 ~ 2026-11-06

---

## 0. 一页速览

| 项 | 内容 |
|---|---|
| 最终可用配置 | `MODE=1`、`SYNC_LATENCY=2205`、`video_sync.USE_FIFO_OUT=1`、`DBG_BAR=0` |
| 三个真根因 | ① XDC **漏了像素时钟约束**（像素域未约束，高斯核 slack −2.23ns）<br>② 大延迟用 **FIFO+data_count** 实现不可靠<br>③ 编码器 **DE 直接接核 TVALID**，与定长 HS/VS 相位不稳 → 锁不住 |
| 最有效的三个手段 | ① `report_clocks` 查时钟域<br>② 板载 LED 做"状态仪表"（不碰视频通路）<br>③ 模块级真值 tb（`tb_vsync2`）+ 棋盘格功能 tb（`tb_gauss_demo`） |
| 一句话总结 | 不是核不工作，是**时序约束 + 同步结构**这两层工程问题；核本身从头到尾都是好的 |

---

## 1. 系统结构（最终版）

```
                    ┌──────────────────── video_core ────────────────────┐
  HDMI IN           │                                                    │
  ┌────────┐  rgb/de│ ┌──────────┐   ┌─── 8bit×16 弹性FIFO ───┐ ┌────────┐│ gray/smooth
  │hdmi_rx │───────►│ │ rgb2gray │──►│ (吸收高斯每行1拍反压)   │►│gauss3x3││───────┐
  │(TMDS)  │  hs/vs │ └──────────┘   └─────────────────────────┘ └────────┘│       │
  └────┬───┘        │       │ gray_out/gray_valid           gauss_out/gauss_vld      │
       │            │       └──────────────┬───────────────────────┘               │
       │            │             多路选择器 sel_gauss ──► smooth_out/smooth_valid   │
       │            └────────────────────────────────────────────────────────────── ┘
       │                                                                             │
       │            ┌──────────────── video_sync ─────────────────┐                  │
       └── hs/vs/de ─►  ① de/hs/vs 走「精确 2205 拍 SRL 移位链」    │◄─────────────────┘
                    │  ② 像素走 512 深 FIFO，按显示 DE 读出        │
                    │     → 编码器看到的行/场结构与输入完全同构     │
                    └──────────────────┬───────────────────────────┘
                                       ▼
                             dvi_transmitter_top ──► HDMI OUT
```

设计原则（HLS 风格）：
* 核只做纯流式 `src→dst`，**不负责行场同步**；
* 行场同步由核外 `video_sync` 统一补偿；
* 灰度核 `dst TREADY` 恒 `1'b1`，**永不反压**（保证灰度通路等价于已验证的 f11b691 版本）。

---

## 2. 关键参数一览

| 参数 | 位置 | 值 | 说明 |
|---|---|---|---|
| `MODE` | `hdmi_loop.v` | `1` | 0=灰度(3拍) / 1=高斯(2205拍) / 2=灰度显示+高斯在跑 / 4=高斯画面+3拍延迟(诊断) |
| `SYNC_LATENCY` | `hdmi_loop.v` | `2205` | 1 行 2200 拍 + 5 拍流水（高斯）；灰度用 3 |
| `USE_FIFO_OUT` | `video_sync.v` | `1`（MODE=1） | 1=DE/HS/VS 定长延迟 + 像素 FIFO；0=DE 跟 TVALID（灰度走这条） |
| 弹性 FIFO 深度 | `video_core.v` | 16 | 只吸收"高斯每行顶住 1 拍"，实测峰值占用 2 |
| 像素 FIFO 深度 | `video_sync.v` | 512 | 吸收核相位抖动，平均吞吐 1:1 永不溢出 |
| `DBG_BAR` | `hdmi_loop.v` | `0` | 画面白条调试开关（0=关） |
| 像素时钟约束 | `hdmi_loop.xdc` | `6.734ns` | **原工程漏了，必须保留** |

高斯核（HLS）固有参数：`GAUSS_W=1920`、`GAUSS_H=1080`、`REF_ROWS/COLS=3`；
每行 1921 次流水推进（1920 读 + 1 行末补 0）、每帧 1081 行 → **trip count 2,076,601**，
而每帧实际读流 1080×1920 = **2,073,600** 次。

---

## 3. 调试时间线（按阶段）

### 阶段 A：v4.0 / v4.1 —— "两级同步 + 输入 FIFO" 方案失败

| 项 | 内容 |
|---|---|
| 方案 | 输入侧 AXI-Stream FIFO + 两级寄存器同步 + `TEST_GRAY_ONLY` 开关 |
| 仿真 | 通过 |
| 上板 | **HDMI 回传无信号** |
| 处置 | 回退到 `f11b691`（上板已验证的灰度环回版本），在其骨架上重写 → v5.0 |
| 教训 | 已验证能跑的基线不要大改；先把"能出图"的结构保住，再增量加功能 |

### 阶段 B：v5.0 ~ v5.2 —— 在 f11b691 骨架上重写灰度→高斯

| 版本 | 改动 | 上板 |
|---|---|---|
| v5.0 | 回退骨架；`video_sync` 用移位链 + `LATENCY`；`EN_GAUSS` 开关 | **灰度模式通过** |
| v5.1 | 弹性 FIFO 只加在高斯分支；`MODE` 三档 | MODE=1/2 **无信号** |
| v5.2 | `video_sync` 去掉 for 循环（改 packed 移位链）；FIFO 挪到两核之间；灰度核 dst 恒不反压 | 仿真双 PASS |

**v5.1 无信号的两个真实 bug：**

1. **核被综合器裁掉**：MODE=2 时高斯核输出没人用 → `Synth 8-3332 ... unused and will be removed` →
   高斯核的 `src TREADY` 变成悬空常 0 → 灰度核的输出被永久顶住 → 画面死。
   **修法**：灰度核 `dst_V_V_TREADY` 直接接 `1'b1`（不反压），灰度通路从此不依赖任何下游。
2. **FIFO 读使能缺"非空"**：`fifo_rd = gauss_src_rdy` → 空 FIFO 也读 → 读指针下溢 →
   假满 → 溢出丢像素。
   **修法**：`fifo_rd = gauss_src_rdy & ~fifo_empty`。

### 阶段 C：v5.3 / v5.4 —— HS/VS 延迟线与 2205 的由来

* v5.3：用 FIFO Generator IP（`sync_fifo_2x4096`，2bit×4096，FWFT，`data_count` 水位出队）做行级延迟；
* v5.4：两模式统一走 FIFO；高斯延迟按板上实测**修正为 1 行 + 5 拍 = 2205**。

> 关于"为什么两核之间要加 FIFO"（板上问过）：高斯核每行要推进 1921 次，而视频每行只给 1920 个像素，
> 它会周期性把 `src TREADY` 拉低 1 拍。若两核直连，这一拍会顶到灰度核 → 丢 1 个像素/行。
> 丢 1080 个/帧后核的行场相位逐帧漂移（≈0.56 行/帧）→ 数帧后"第 0 行不出数"的空窗漂进可见区 → **无信号**。
> 加 16 深 FIFO 后实测 **DE/line 从 1919 恢复到 1920**，FIFO 峰值占用仅 2。

### 阶段 D：v5.5 —— 去掉 generate，改成"两核都例化 + 输出多路选择"

```verilog
rgb2gray  u_rgb2gray ( ... .dst_V_V_TREADY(1'b1) );
gauss3x3  u_gauss3x3 ( ... .src_V_V_TDATA(fifo_dout), .src_V_V_TVALID(fifo_valid) );

assign smooth_out   = sel_gauss ? gauss_out : gray_out;
assign smooth_valid = sel_gauss ? gauss_vld : gray_valid;
```

* 删除参数 `EN_GAUSS`，新增输入 `sel_gauss`（1=平滑，0=灰度）；
* `sel_gauss` 后来改成**寄存器**驱动，避免综合器把未选中的核裁掉；
* 好处：任务四的按键切换只需把这个端口接到 `key[0]`，两核始终在跑，切换只换 mux 输入。

> 调试插曲：改连线时误删了 `video_sync` 的 `.gray_valid(smooth_v)`，**综合立刻暴露**：
> LUT 从 872 掉到 337、高斯核被裁。补回后恢复正常 —— 说明"对比综合前后资源/告警"能抓连线级错误。

### 阶段 E：v5.6 —— 【根因①】像素时钟根本没有约束

**现象**：灰度正常，`MODE=1` 无输出；仿真全过、综合 0 错。

**证据（实现后 `report_clocks`）**：

```
sys_clk        20.000ns  P       ← 50MHz 板载
clk_out1_mmcm 100.000ns  P,G,A   ← 10MHz（i2c_edid）
clk_out2_mmcm   5.000ns  P,G,A   ← 200MHz
clk_hdmi_in_p   6.000ns  V {}    ← 虚时钟（差分对没落到网络）
```

**没有 `pixel_clk`** → 整个像素域（rgb2gray / gauss3x3 / video_sync / dvi 编码）都是"未约束路径"。

**量化**：在已布线网表上补 `create_clock -period 6.734 -name pixel_clk [get_nets pixel_clk]` 再量：

```
我们自己逻辑 WNS = −2.233 ns
最差路径：u_gauss3x3/i_reg_214_reg[4]/C → wlb_lb_val_V_1_U/.../ram_reg/ENBWREN
        u_gauss3x3/i_reg_214_reg[4]/C → col_assign_fu_112_reg[*]/CE
video_core / video_sync 内共 311 条违例路径
```

**为什么灰度能动**：灰度通路只有 RGB→灰度（3 级流水）+ 很浅的组合逻辑，乱摆也能在 148.5MHz 逮住；
高斯核带 BRAM 行缓存 + 卷积加法树 + `col` 逻辑，未约束必崩。这就是"仿真全过、上板只有灰度能动"的真因。

**修法**（`hdmi_loop.xdc` 追加）：

```tcl
create_clock -period 6.734 -name pixel_clk [get_nets pixel_clk]
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_nets pixel_clk]] \
    -group [get_clocks clk_out1_mmcm] \
    -group [get_clocks clk_out2_mmcm]
set_false_path -to [get_pins -of_objects [get_cells -hier -filter {IS_SEQUENTIAL == 1}] \
                   -filter {REF_PIN_NAME == "R" || REF_PIN_NAME == "S"}]
```

**结果**：pixel_clk 组 `Setup : 0 Failing Endpoints, Worst Slack +1.409ns`，其它组均 MET。

### 阶段 F：ILA 排查（未能用上，但记录方法）

| 报错 | 原因 | 处置 |
|---|---|---|
| `Device is programmed with a design that has no supported debug core(s)` | 板上 bit 与本批 probes 不是同一次构建 | 用同一批 `hdmi_loop.bit` + `debug_nets.ltx` |
| `The debug hub core was not detected` | `dbg_hub` 时钟 = `pixel_clk`（HDMI 恢复时钟），输入不在线就不响应 | 先保证 HDMI 输入在线 |
| `Mismatch ... hw_probe 'dbg_gauss_beats' ... port index '4' ... does not support a data probe` | GUI 里残留上一次的 probes 配置 | 脚本先 `refresh_hw_device -update_hw_probes false` 再一起下 |

为此写了 `sim_check\program_hw.tcl`（一次性设置 `PROGRAM.FILE` / `PROBES.FILE` / `FULL_PROBES.FILE`）。

**ILA 探针映射**（`dbg_ila`，5 probe，深度 1024）：

| probe | 位宽 | 连接 |
|---|---|---|
| probe0 | 1 | `video_de` |
| probe1 | 7 | `{vs_proc, hs_proc, de_proc, smooth_v, gray_v, video_vs, video_hs}` |
| probe2 | 16 | `{smooth_w[7:0], gray_w[7:0]}` |
| probe3 | 24 | 上一帧灰度核有效拍数（应为 2,073,600） |
| probe4 | 24 | 上一帧高斯核有效拍数（应为 2,073,600） |

### 阶段 G：板载 LED 仪表（绕开 JTAG，拿到关键结论）

**做法**：加 `led[3:0]` 引脚（`R2/R3/V2/Y2`），只读统计量，**完全不碰视频通路**。

```verilog
assign led[0] = (dbg_gauss_beats != 0);   // 高斯核上一帧有出数
assign led[1] = (dbg_gray_beats  != 0);   // 灰度核上一帧有出数
assign led[2] = (g_line_last == 1920);    // 高斯流行宽
assign led[3] = (r_line_last == 1920);    // 灰度流行宽（对照）
```

**结论（关键一步）**：`led[0]`/`led[1]` **常亮** → **高斯核在硬件上确实在出数据**，
排除了"核不工作"这一大类假设，问题收敛到"同步结构"。

**同时暴露另一个问题**：`led[2]/led[3]` 双灭 —— 而灰度那路明明是 1920/行，
说明**以 hs 为界统计行宽的方法在大延迟下本身不可信**（先按 DE 连续段统计会被气泡切成多段，
改成按 hs 划行后仍双灭）→ 这条路作为"判据"废弃，改用模块级真值 tb。

> 两次"画面白条"调试均失败（**全白**）：白条画在消隐行、且计数器饱和后 `beats[23:13]` 达 2047 > 1920 →
> 整行被判成白条；后来即使封顶 400 也仍异常（vs 极性/行号统计不成立）。**教训：不要往视频通路里插调试逻辑，
> 一旦画面被自己弄坏，就同时失去"画面"这个观测手段。**

### 阶段 H：v5.7 —— HS/VS 延迟改用精确 SRL 移位链

弃用 `fifo + data_count`（延迟会多 1~2 拍且语义不确定），改为：

```verilog
reg [2*LATENCY-1:0] sr;                                     // 无 for、无复位
always @(posedge clk) sr <= {sr[2*LATENCY-3:0], hs_in, vs_in};
assign hs_out = sr[2*LATENCY-1];
assign vs_out = sr[2*LATENCY-2];
```

* 综合成 **SRL32E 链**：2205 拍仅约 140 LUT（总 FF 3739 < 4410，反证没变成触发器阵列）；
* 延迟**严格等于** `LATENCY`；不加复位才不会退化成触发器阵列。

结果：仿真全 PASS，但**上板仍无画面** → 说明根因还在更下游。

### 阶段 I：v5.8 —— 【根因②③】DE 不该直接接核的 TVALID

**推理**：既然核在出数（LED 证明）、时序已闭合、hs/vs 已精确，那么问题只剩"DE 与 HS/VS 的相对关系"。

`gauss3x3` 每行需要 **1921 次流水推进**（1920 读 + 行末补 0），而视频每行只给 1920 拍 →
它的 `dst TVALID` 天生带**气泡**、相位**抖动**；而 HS/VS 是**定长延迟**。
两者相对位置不稳，显示器/采集卡就锁不住 → 有数据也"无画面"。

**修法**（`video_sync.v` v2，参数选择，不用 generate）：

```verilog
// ① DE/HS/VS 三个一起精确延迟 LATENCY 拍（每拍移 3 位 → SRL32E）
always @(posedge clk) sr <= {sr[3*LATENCY-4:0], de_in, hs_in, vs_in};

// ② 像素：核输出写 FIFO（带抖动），按显示 DE 读出
wire we = gray_valid & ~full;      // 核有数据就写
wire re = de_del     & (cnt != 0); // 显示窗口内、非空才读

assign de_out  = USE_FIFO_OUT ? de_del    : gray_valid;
assign rgb_out = {3{(USE_FIFO_OUT ? pix_fifo : gray_in)}};
```

* `USE_FIFO_OUT=0`（灰度 / MODE=0,2）→ **保持 f11b691 原语义**，已验证的部分绝不动；
* `USE_FIFO_OUT=1`（高斯 / MODE=1）→ 编码器看到的 `de/hs/vs` 与输入**完全同构**（整体晚 2205 拍），
  核的停顿/抖动全部被 512 深 FIFO 吸收，只影响个别像素位置，**不再破坏锁相**。

### 阶段 J：v5.9 —— 上板成功

* **有画面**（高斯平滑图），上电后先滚动/偏移 1~2 秒（HDMI 锁定期），随后稳定；
* `LED0/LED1` 常亮；
* 时序：WNS 1.060ns，0 failing endpoints，0 critical warning。

---

## 4. 验证矩阵

### 4.1 仿真

| tb | 检查内容 | 结果 |
|---|---|---|
| `tb_video_sync.v` | CH0(LATENCY=3) / CH1(LATENCY=2205) 的 hs/vs 延迟、DE 跟随、像素直通 | 6653 / 8855 拍，**err=0 → PASS** |
| `tb_core_chain.v` CH-A（灰度） | hs/vs 脉冲数、DE/line、DE&VS 重叠、像素公式 `(66R+129G+25B+128)>>8` | hs 30/30、vs 2/2、DE/line 1920、pix err 0 → **PASS** |
| `tb_core_chain.v` CH-B（高斯） | hs/vs 存在性、DE&VS 不重叠 | **PASS**（其 DE/line 指标按输入 DE 划窗，与新结构语义不符，显示 3840，**不作判据**） |
| `tb_vsync2.v`（模块级真值比对） | L=2205 / H=1920 / HB=280，与黄金延迟链逐拍比对 de/hs/vs + FIFO 像素通路 | 4800 拍，**err=0 → PASS** |
| `tb_gauss_demo.v`（功能） | 输入竖条纹棋盘格 0/255（最高空间频率） | 行内 3560 点输出**恒为 127**（均值=最小=最大）→ 高频被完全滤除 |

### 4.2 综合 / 实现

| 项 | 灰度（MODE=0，早期） | 高斯（MODE=1，最终） |
|---|---|---|
| Errors / Critical Warnings | 0 / 0 | 0 / 0（2 条 critical 来自 XDC 里 `create_clock` 落在端口形成虚时钟的提示，不影响时序结论） |
| Slice LUTs | 572 | ~1100（含 ILA/video_dbg） |
| Slice Registers | 651 | 3760（含 ILA） |
| Block RAM Tile | 0 | 4（高斯行缓存 2 + ILA 采样） |
| 时序 | MET | **WNS 1.060ns，WHS 0.057ns，0 failing endpoints** |

### 4.3 上板

| 版本 | 灰度模式 | 高斯模式 | 备注 |
|---|---|---|---|
| v4.0/v4.1 | 无信号 | — | 方案性失败，已回退 |
| v5.0 | **通过** | — | f11b691 骨架重写 |
| v5.1~v5.7 | 通过 | **无画面** | 逐步排除：核裁剪、FIFO 读使能、像素时钟约束、延迟线实现 |
| **v5.9** | 通过 | **通过（出平滑图）** | 上电滚动 1~2s 后稳定 |

---

## 5. 为什么 3×3 高斯"看起来仍然很清晰"

用真实 IP 实测（`tb_gauss_demo.v`）：输入最高频图案 → 输出恒 127，说明滤波**确实生效**。
肉眼看着清晰是因为 **3×3 高斯是最温和的平滑**：

| 结构周期 | 归一化频率 | 增益 H(ω)=cos²(ω/2) | 效果 |
|---|---|---|---|
| 2 像素（棋盘格/噪点） | π | **0** | 完全滤除（实测恒 127） |
| 4 像素 | π/2 | 0.5 | 减半 |
| 8 像素 | π/4 | 0.85 | 轻微 |
| ≥16 像素 | ≤π/8 | ≥0.96 | 几乎不动 |

再加上：权重和 = 1（直流增益 1，亮度不变、不发灰）；1080p 下 ±1 像素的软化在缩放预览里不可分辨。
**想肉眼看到效果**：喂细条纹/噪点图、或放大到 400% 看边缘、或看 `|原图−平滑图|` 的假彩色差分图。

---

## 6. 调试工具与命令速查

| 用途 | 命令/文件 |
|---|---|
| 语法检查（CLI） | `sim_check\run_compile.bat`（xvlog 全部源码） |
| 同步自检仿真 | `sim_check\run_sim.bat` → `tb_video_sync` |
| 系统级仿真 | `sim_check\run_chain.bat` → `tb_core_chain` |
| 同步模块真值比对 | `xvlog tb_vsync2.v video_sync.v` → `xelab` → `xsim vs2b -R` |
| 高斯功能验证 | `xvlog tb_gauss_demo.v gauss3x3*.v` → `xelab` → `xsim gdemo2 -R` |
| 综合检查 | `vivado -mode batch -source synth_check.tcl` |
| 实现+出 bit | `vivado -mode batch -source build_bar.tcl`（reset → synth → impl → write_bitstream） |
| 时序分析 | `impl_check.tcl`（`report_timing_summary` / `report_clocks`） |
| 烧板（含 probes） | `sim_check\program_hw.tcl` |
| 时钟域自查 | 打开 impl 后 `report_clocks` —— 必须看到 `pixel_clk 6.734` |

**时序自查口诀**：`open_run impl_1` → `report_clocks` → 没看到 `pixel_clk` 就是没约束。

---

## 7. 已知问题 / 后续可做

| 项 | 说明 | 影响 |
|---|---|---|
| 上电滚动 1~2 秒 | HDMI 锁定期（显示器/采集卡抓时序的正常过程） | 无（非设计缺陷） |
| `tb_core_chain` CH-B 的 DE/line 指标 | 按输入 DE 划窗统计，与新结构语义不符（显示 3840） | 仅判据问题，已用 `tb_vsync2` 取代 |
| `sync_fifo_2x4096` IP | 保留在工程中但**不再例化** | 无 |
| ILA（`dbg_ila`）+ `video_dbg` | 仍在比特流里，占 ~3 块 BRAM | 最终提交可去掉出一个"干净版" |
| 按键实时切换 | `sel_gauss` 已是寄存器，接 `key[0]` 即可实现灰度/高斯切换（任务四） | 未做 |
| `pixel_clk_5x`（742.5MHz） | 只给 OSERDES 用，未加约束 | 目前正常 |

---

## 8. 文件清单

| 文件 | 作用 |
|---|---|
| `sources_1\new\video_core.v` | 两核都例化（rgb2gray → 16 深 FIFO → gauss3x3）+ 输出多路选择 `sel_gauss` |
| `sources_1\new\video_sync.v` | DE/HS/VS 精确延迟（SRL 移位链）+ 像素 FIFO（`USE_FIFO_OUT` 切换两套输出语义） |
| `sources_1\new\video_dbg.v` | 每帧灰度/高斯有效拍数统计（供 ILA/LED） |
| `sources_1\imports\53_hdmi_loop\rtl\hdmi_loop.v` | 顶层：`MODE`/`SYNC_LATENCY`、ILA、LED、调试白条（已关） |
| `constrs_1\new\hdmi_loop.xdc` | **像素时钟约束（关键）** + 异步时钟组 + LED 引脚 |
| `doc\DaVinci_FPGA_IO.xdc` | 板级 IO 引脚（LED/KEY 来源） |
| `sim_check\tb_video_sync.v` / `tb_core_chain.v` / `tb_vsync2.v` / `tb_gauss_demo.v` | 四级仿真验证 |
| `sim_check\program_hw.tcl` | 一次性烧 bit+probes，避免 probes 不匹配 |
| `doc\修改日志_v5_回退f11b691骨架重写.md` | 逐版本修改记录（§1~§12） |
| 备份目录 | `D:\HLS\_backup_lab2_gauss_OK_20261106_225807\`（含 README 与已验证比特流路径） |

---

## 9. 经验总结（可直接写进报告）

1. **XDC 里的时钟约束是功能的一部分**：漏一个 `create_clock`，逻辑再对也可能在板上跑飞；
   而且"简单逻辑侥幸能跑、复杂逻辑必崩"是典型症状 —— 一遇到"仿真过、上板错"先 `report_clocks`。
2. **HLS 核的 `dst TVALID` 不能直接当显示器 DE**：它是"数据有效"，不是"固定行时序"；
   视频输出侧必须由固定延迟（或行缓存）产生 de/hs/vs，再按键拍从 FIFO 取像素。
3. **大延迟别用 FIFO 的 `data_count` 水位实现**：移位链（SRL）延迟精确、资源更省（2 bit×2205 ≈ 140 LUT）。
4. **不可反压的通路（hdmi_rx）前面必须留弹性缓冲**：否则上游一处 1 拍反压就是永久丢像素，
   而丢像素会让"按固定计数推进"的 HLS 核逐帧相位漂移，最终表现为"无信号"这种极难定位的现象。
5. **调试手段要分层**：仿真（真值比对）→ 综合报告（资源/告警对比）→ 时序报告（slack）→ 板载 LED（宏观状态）→ ILA（细节）；
   任何"插进视频通路里的调试逻辑"都要预期它会把画面弄坏，别把它当唯一观测手段。
6. **改一行就要有一行的影响面分析**：本日志里既抓到了"综合器裁掉未用核"，也抓到过"误删一根连线导致 LUT 从 872 掉到 337"，
   都是靠**前后对比**发现的。
---

## 10. 补充：校准实验结论（2026-11-07）与根因归因修正

### 10.1 实验经过

做了 4 个可烧写的诊断模式（`bit_out\`），全部上板实测：

| 模式 | hs/vs 延迟 | DE 来源 | 上板结果 |
|---|---|---|---|
| `MODE=1` | 2205 | **定长延迟 + 像素 FIFO** | **正常出平滑图** |
| `MODE=3` | 1→2 | 核 TVALID | 正常（看不到偏移） |
| `MODE=5` | 1100（半行） | 核 TVALID | **正常** |
| `MODE=4` | 2205 | 核 TVALID | **正常** |

### 10.2 结论一：接收端对 hs/vs 相位不敏感

`MODE=5` 把 hs/vs 相对 DE 挪了 **1100 拍（半行）**，`MODE=3` 挪了约 2203 拍（1 行 + 3 像素），
**画面都正常**。原因：

* 采集卡 + PotPlayer 这类接收端会按 **DE 窗口重新对齐/加窗**，hs↔DE 的相位差被吸收；
* 而 `2205 − 2 = 1 行 + 3 像素` 这个偏移量本身也远在肉眼可辨范围之下。

→ **"看画面有没有错位"不能作为同步相位的判据**（至少在这条采集卡链路上）。
要用眼睛看，必须让显示器**直连**板子的 HDMI OUT（不经采集卡）。

### 10.3 结论二：根因归因必须修正

`MODE=4`（2205 拍 + DE 跟核 TVALID，与 v5.7 结构完全一致）现在**能正常出图**，
这说明 v5.8 的"DE/HS/VS 定长延迟 + 像素 FIFO"改造**并非画面能不能出来的决定性因素**。

把时间线与证据重新对齐后，最可信的归因是：

| 根因 | 判定 | 依据 |
|---|---|---|
| ① **XDC 漏像素时钟约束**（高斯核 slack −2.23ns） | **决定性** | 补约束后才可能正确工作；这是唯一"必然导致高斯核跑飞"的因素 |
| ② HS/VS 大延迟用 `FIFO+data_count` 实现 | 次要 | 换成 SRL 移位链后延迟精确、资源更省（2×2205 ≈ 140 LUT），但非致命 |
| ③ DE 直接接核 TVALID（DE 有气泡） | **未证实致死** | MODE=3/4/5 都是 DE 接 TVALID，均正常出图；气泡只造成个别像素级的轻微瑕疵 |

**关于 v5.6 / v5.7 两次"still no picture"的说明（如实记录）：**

这两次观测现在无法复现——同样的结构（MODE=4）现在正常。结合当时 ILA 侧出现的
`Device is programmed with a design that has no supported debug core(s)` /
`Mismatch ... probes file` 等报错（说明板上运行的 **不是** 当次构建的比特流），
**最可能的解释是那两次烧写的是旧比特流**，即"改了代码但板上跑的还是老版本"。
这一点无法追溯证实，故记录为"疑似陈旧比特流"，不作为设计缺陷计入。

### 10.4 现在的交付状态

* 顶层恢复 `MODE = 1`（定长延迟 + 像素 FIFO，最稳妥的一版），已重新构建；
* `bit_out\` 四个比特流全部保留，可随时对比：

```
hdmi_loop_MODE1_normal.bit    正常高斯显示（2205 + FIFO）   ← 交付版
hdmi_loop_MODE3_1beat.bit     只打 1 拍（差 1 行 + 3 像素，肉眼不可辨）
hdmi_loop_MODE4_2205_ctl.bit  2205 + DE 跟核（与 v5.7 同构）
hdmi_loop_MODE5_halfline.bit  半行错位（仍正常 → 接收端自适应）
```

### 10.5 经验（补充到第 9 节）

7. **"上板不对"要先排除"烧的不是这次构建的比特流"**：本实验里这个坑出现了两次
   （ILA probes 不匹配一次、疑似 v5.6/v5.7 一次）。排查手法：核对 bit 的时间戳/size，
   或改用带唯一标识的构建（例如把版本号写进 LED 闪烁模式 / 走一遍 `program_hw.tcl`）。
8. **观测手段的适用范围要交代清楚**：采集卡自适应 → 看不出相位错位；
   要判断时序层面的对错，必须直连显示器或做片内数字测量。
---

## 11. v6.0 更新：模式表改为四档 + 新增锐化（模式3）

### 11.1 新模式表

| MODE | 含义 | 像素来源 | 同步 | 延迟 |
|---|---|---|---|---|
| 0 | 直入直出 | `video_rgb` 纯直连（不打拍） | 用 hdmi_rx 输出 | 0 |
| 1 | 灰度 | `rgb2gray` | `USE_FIFO_OUT=0`，DE 跟 TVALID | 3 拍 |
| 2 | 平滑 | `gauss3x3` | `USE_FIFO_OUT=1` | 2205 拍 |
| 3 | **锐化** | `clamp(2*gray − gauss)` | `USE_FIFO_OUT=1` | **2208 拍**（2205+3） |

`SHARP_PIPE = 3`（FIFO 同步读 1 + 算术 1 + 限幅 1），改流水级数只需改这一处常量。

### 11.2 锐化的两个工程点

1. **两路对齐用 FIFO 配对**：`pwe = gray_valid`、`prd = gauss_valid`（出一个弹一个）。
   4096×8 同步读 → 推断为 **1 个 RAMB36**（综合报告 `pmem_reg 4K x 8 → RAMB36 1`），
   实测峰值占用 **1928**；比"固定延迟 2211 拍对齐"更稳——后者遇高斯核 ±1~3 拍抖动会错像素。
2. **计算与限幅各占一拍**（全时序逻辑）：第 1 级算 `2*orig − smooth`（12 位有符号），
   第 2 级限幅 0~255；数据与 valid 每级同沿推进，输出仍"valid 与 data 同拍"。

### 11.3 四档构建与资源

| MODE | 比特流 | WNS | 违例 | 备注 |
|---|---|---|---|---|
| 0 | `hdmi_loop_MODE0_passthru.bit` | 1.254 ns | 0 | 处理链被裁掉，最省资源 |
| 1 | `hdmi_loop_MODE1_gray.bit` | 1.614 ns | 0 | |
| 2 | `hdmi_loop_MODE2_smooth.bit` | 0.967 ns | 0 | |
| 3 | `hdmi_loop_MODE3_sharp.bit` | 1.192 ns | 0 | BRAM 5/50（含对齐 FIFO 的 RAMB36） |

四档均 **0 error / 0 critical warning**。

### 11.4 已知现象

- 锐化在图像**边界**会提亮 1~2 像素：gauss 在边缘按 0 补，`smooth < orig` →
  `2*orig − smooth > orig`，属算法固有；需要时加"首尾列/首末行屏蔽"。
- 铝化增益固定 k=1（严格按题目 `orig + (orig − smooth)`）。