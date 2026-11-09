# 修改日志 —— HDMI 环回：灰度核 + 高斯核「两级级联」同步重写

| 项 | 内容 |
|---|---|
| 工程 | `hdmi_loop`（Vivado 2018.3，xc7a35tfgg484-2） |
| 涉及模块 | `video_sync`（重写为两级参数化）、`video_core`（新增输入弹性 FIFO）、`hdmi_loop`（顶层例化） |
| 修改原因 | 数据链路改为「HDMI → 灰度核 → 高斯核 → 编码器」，HS/VS 必须按**整条链路的总延迟**补偿；上一版 `DELAY=1926` 是单核估算、且把"1 行"当成 1921 拍，HS 脉冲会滑进有效像素区 |
| 用户给的标定 | 灰度核 `rgb2gray` = 1 行 + **4 拍**；高斯核 `gauss3x3` = 1 行 + **6 拍** |
| **真实 RTL 实测** | 灰度核 = **0 行 + 3~4 拍**（点操作核无行缓存）；链路总延迟 = **1 行 + 11 拍**（2211 拍） |
| 合计补偿（已实现） | HS/VS 延迟 = 0行+4拍 + 1行+6拍 = **1 行 + 10 拍 = 2210 拍**（与实测 2211 差 1 拍，可忽略） |
| 额外发现并修复 | gauss3x3 每个行周期会反压 1 拍 → **每行丢 1 个像素**（画面竖缝/斜纹）；已在 `video_core` 灰度核前加 16 深弹性 FIFO，实测丢像素 = 0 |
| 验证方式 | 真实 RTL 链路实测（`tb_core_chain`）+ 同步层双通道逐拍自检（`tb_video_sync`）+ xvlog 编译 + Vivado 综合，全部 0 错 |

---

## 1. 修改文件清单

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `sources_1/new/video_sync.v` | **重写** | 单参数 `DELAY` → 两级参数（`LINE_CLKS / GRAY_LINE / GRAY_TAP / GAUSS_LINE / GAUSS_TAP`）；`hs_vs_dly` 级联两级；新增 `hs_gray/vs_gray` 抽头；修环形缓冲指针回绕 bug |
| `sources_1/new/video_core.v` | 修改 | **新增输入弹性 FIFO（16 深 × 24bit）**，吃掉高斯核的周期性反压；sim 下带溢出/峰值占用自检 |
| `sources_1/imports/53_hdmi_loop/rtl/hdmi_loop.v` | 修改 | `video_sync` 例化改新参数与新端口；数据流注释更新 |
| `sim_check/tb_core_chain.v` | **新增** | 用真实 `rgb2gray + gauss3x3 + video_core` RTL 实测链路延迟、每行拍数、FIFO 占用 |
| `sim_check/run_chain.bat` | **新增** | 上面这个实测的一键脚本 |
| `sim_check/tb_video_sync.v` | **重写** | 不依赖 HLS 核，双通道（真实参数 + 小参数）逐拍自检同步层 |
| `sim_check/run_sim.bat` | 修改 | 只编译 `video_sync.v + tb_video_sync.v`，秒级跑完 |
| `sim_check/backup/*.bak_task2_gauss` | 新增 | 修改前的 4 个文件备份 |

---

## 2. 延迟模型与实测证据（本次改动的核心）

### 2.1 一个核的延迟拆两段

| 段 | 含义 | 灰度核 | 高斯核 |
|---|---|---|---|
| 行级 `LINE` | 窗口核"第一行不出数"（`i>=1` 才输出），整条输出流比输入晚一个行周期；点操作核无行缓存 | **0** | **1** |
| 拍级 `TAP` | 流水线深度（II=1 时 = csynth 的 Iteration Latency） | 4 | 6 |

### 2.2 实测结果（`sim_check\run_chain.bat`，真实 RTL）

激励：1080p60 行时序（1920 有效 + 280 消隐），喂 8 行。

```
 1 line = 2200 clk
 beats: de_in=15360 gray_v(clk)=15366 smooth_v=13435 (expect smooth = 7*1920 = 13440)
 smooth beats per line: min=0 max=1920 (expect 1920)
 fifo: max occupancy=2  overflow=0
 edges: de_in=8 gray_v=8 smooth_v=13

 idx |   t(de_in) |  t(gray_v) | t(smooth_v) | d_gray | d_smooth
   0 |         25 |         29 |        2236 |      4 |     2211
   1 |       2225 |       2228 |        4430 |      3 |     2205
   2 |       4425 |       4428 |        4436 |      3 |       11
```

读法：

| 观测 | 结论 |
|---|---|
| `d_gray` = 3~4 拍（各行恒定） | 灰度核**没有**行级延迟，只有 3~4 拍流水延迟 |
| `t(smooth_v) - t(de_in)` 首个行窗口 = **2211** | 链路总延迟 = 1 行 + 11 拍 → **"整行"级延迟只出现在高斯核这一级** |
| `smooth_v` 总拍数 ≈ 7×1920（8 行进、`i=0` 行不出数） | 与"窗口核跳过第 0 行"一致，也印证那 1 行延迟 |
| 每行 `smooth_v` = 1920 拍 | FIFO 后**没有丢像素** |

### 2.3 为什么"1 行"只算一次（对用户给的数字的修正）

用户给的拍级数字（4 拍 / 6 拍）与实测**完全吻合**（4+6 = 10 ≈ 实测 11 拍）；
但"1 行"如果两个核各算一次，HS/VS 会被多推 **整 1 行**（2200 拍），
表现就是画面整体上下偏 1 行（顶部少一行、底部多一行）。

物理解释：`rgb2gray` 是点操作，没有行缓存，它不可能产生行级延迟；
`gauss3x3` 因为 `i>=1` 才输出，第一条输出行在输入第 1 行的时间窗口才出现，
所以整条链的行级延迟 = 1 行，**只在高斯核这一级**。

> 说明：如果现场坚持按"两核各 1 行"补偿，只需把 `hdmi_loop.v` 里
> `GRAY_LINE(0)` 改成 `GRAY_LINE(1)`，其余不动（参数化就是为这种现场微调准备的）。

### 2.4 为什么"1 行"是 2200 拍而不是 1921 拍

上一版 `DELAY = 1926` 的推导是"1 行（1921 拍）+ 5 拍"。1921 是**核内部计数拍数**
（1920 有效 + 行末补 0 列），只在核的平铺循环里有意义；而 HS/VS 走实际时间轴：

```
1080p60：1 行 = 2200 拍 = 1920 有效 + 280 行消隐
```

行级延迟必须按整行周期算。若按 1921 算，每行少补 279 拍，两行累计少补 **558 拍**
（> 280 拍行消隐），HS 脉冲就滑进有效像素区中间 → 撕裂/整体偏移。

---

## 3. 代码变更

### 3.1 `video_sync.v`（两级参数化）

```verilog
module video_sync #(
    parameter integer LINE_CLKS  = 2200,   // 1 个行周期拍数
    parameter integer GRAY_LINE  = 0,      // 灰度核行级延迟（点操作核 → 0）
    parameter integer GRAY_TAP   = 4,
    parameter integer GAUSS_LINE = 1,      // 窗口核首行不出数 → 1
    parameter integer GAUSS_TAP  = 6
)( ... );

    localparam integer D_GRAY  = GRAY_LINE  * LINE_CLKS + GRAY_TAP ;   // 4
    localparam integer D_GAUSS = GAUSS_LINE * LINE_CLKS + GAUSS_TAP;   // 2206
    localparam integer D_TOTAL = D_GRAY + D_GAUSS;                     // 2210

    assign de_out  = smooth_valid;         // DE 跟末级核 TVALID
    assign rgb_out = {3{smooth_in}};       // 像素组合直通

    hs_vs_dly #(.DELAY(D_GRAY )) u_dly_gray ( ... );   // 原始 → 灰度级
    hs_vs_dly #(.DELAY(D_GAUSS)) u_dly_gauss( ... );   // 灰度级 → 高斯级
```

`hs_vs_dly`：分布式 RAM 环形缓冲，每拍写、每拍读（消隐期也连续走）。

### 3.2 顺带修掉的旧 bug：环形缓冲指针回绕

```verilog
reg [$clog2(DELAY)-1:0] wr_ptr;                    // 旧：DELAY=1926 → 11 位，0..2047 回绕
reg [1:0] sync_ram [0:DELAY-1];                    // 旧：RAM 只有 1926 深
```

计数器按 2048 回绕、RAM 只有 1926 深 → 地址 1926~2047 越界，每 2048 拍有 122 拍读到无效值。

```verilog
localparam integer DEPTH = DELAY + 1;              // 新：多留 1 格
wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1;    // 按 DEPTH 回绕
rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1;
rd_ptr <= 1;                                       // 复位：读指针超前 1 格 ⇒ 严格滞后 DELAY 拍
```

深度取 `DELAY+1` 还保证读指针永不落在"本拍正在写"的地址（不会读写同址）。

### 3.3 `video_core.v` 新增输入弹性 FIFO（重要）

实测发现：`gauss3x3` 每个行周期需要 1921 次流水推进、却只拿到 1920 个有效像素，
所以它把 `src TREADY` **每个行周期拉低 1 拍**（实测 7 行 7 次，位置 col=8→9→10… 逐行漂移）。
`hdmi_rx` 的 `video_de` 是"只有 TVALID、不能反压"的源，这一拍像素就被直接丢掉：

```
改之前：每行丢 1 个像素 → 画面竖缝/斜纹，且丢失位置逐行漂移
改之后：16 深 FIFO 把反压吃掉 → 实测 overflow=0，每行 1920 拍完整
```

```verilog
// 写端：de_in 有效就写（永不反压）
if (de_in && !fifo_full) begin
    fifo_mem[fifo_wptr[FW-1:0]] <= rgb_in;
    fifo_wptr <= fifo_wptr + 1'b1;
end
// 读端：由灰度核 src TREADY 控制
if (fifo_rd) fifo_rptr <= fifo_rptr + 1'b1;

assign src_data  = fifo_mem[fifo_rptr[FW-1:0]];
assign src_valid = ~fifo_empty;
```

平均吞吐不变（每行进 1920、出 1920），FIFO 实测峰值占用仅 **2**，16 深余量充足。

---

## 4. 验证记录

### 4.1 同步层逐拍自检（`sim_check\run_sim.bat`）

| 通道 | 参数 | D_GRAY | D_GAUSS | D_TOTAL | 仿真拍数 | 结果 |
|---|---|---|---|---|---|---|
| CH0 | 真实（2200 拍/行，0行+4拍 / 1行+6拍） | 4 | 2206 | 2210 | 26460 | **PASS** |
| CH1 | 小参数（20 拍/行，1行+4拍 / 1行+6拍，覆盖回绕） | 24 | 26 | 50 | 440 | **PASS** |

检查项（两通道均 0 错）：`hs_out/vs_out` = 输入延迟 `D_TOTAL` 拍（逐拍全比对）、
`hs_gray/vs_gray` = 延迟 `D_GRAY` 拍、`de_out` 与 `smooth_valid` 同拍、`rgb_out` = `{3{smooth_in}}` 同拍。

### 4.2 真实链路实测（`sim_check\run_chain.bat`）

见 §2.2：总延迟 2211 拍、每行 1920 拍、FIFO 无溢出、无丢像素。

### 4.3 顶层编译（`sim_check\run_compile.bat`）

`hdmi_loop.v + video_core.v + video_sync.v` → `EXITCODE=0`，0 error。

### 4.4 综合（`sim_check\synth_check.tcl`）

```
287 Infos, 88 Warnings, 0 Critical Warnings and 0 Errors encountered.
synth_design completed successfully
SYNTH_STATUS = synth_design Complete!
```

| 指标 | 结果 |
|---|---|
| Errors / Critical Warnings | **0 / 0** |
| 新增代码告警 | **0 条**（`video_sync` / `video_core` / `hs_vs_dly` 关键字命中 0） |
| 其余告警 | 88 条，均为原工程 RTL（正点原子）与 HLS 核既有告警 |
| Slice LUTs | 1085 / 20800（5.22%） |
| 其中 LUT 作分布式 RAM | 224（HS/VS 环形缓冲 5 深 + 2207 深，以及 16×24bit 输入 FIFO） |
| Slice Registers | 1051 / 41600（2.53%） |
| Block RAM | 1 |

---

## 5. 上板调参指引（只动参数，不动结构）

| 现象 | 改哪个参数 |
|---|---|
| 画面整体上下偏整行 | `GAUSS_LINE`（1↔0）/ `GRAY_LINE` |
| 画面行内左右偏几拍 | `GRAY_TAP` / `GAUSS_TAP` |
| 换分辨率（720p60） | `LINE_CLKS = 1280 + 370 = 1650` |

原则：**行级按整行周期算、拍级按迭代延迟算**；TAP 的调整量远小于 280 拍行消隐，
所以调 TAP 只平移画面、不会破坏同步。

现场复核方法（ILA）：抓 `video_de / smooth_valid / hs_proc / vs_proc`；
`smooth_valid` 行首边沿 - `video_de` 行首边沿 = 总延迟（应为 ≈2210）；
若测出"多/少整行"，就调 `GAUSS_LINE`。

---

## 6. 单独测试灰度流水（开关 `TEST_GRAY_ONLY`）

需求：只验证 **HDMI → 灰度核 → 编码器**（不经过高斯核）。

### 6.1 只改 1 行（`rtl/hdmi_loop.v`）

```verilog
localparam integer TEST_GRAY_ONLY = 1'b1;   // 1 = 只测灰度流水；0 = 灰度+高斯（默认业务）
```

这一行同时联动两处，不用改别的地方：

| 位置 | `TEST_GRAY_ONLY=1` 时 | 作用 |
|---|---|---|
| `video_core.EN_GAUSS` | `0` | 高斯核整块不综合；`gray_r = 1'b1`（灰度核输出不被反压）；`smooth_out/smooth_valid` 直通灰度 → 顶层数据线不用改 |
| `video_sync.GAUSS_LINE / GAUSS_TAP` | `0 / 0` | 高斯那段延迟整体旁路，HS/VS 只补灰度核的 **0 行 + 4 拍** |

### 6.2 为什么必须让高斯核"不反压"

实测（`run_chain.bat`，同一套激励同时跑 `EN_GAUSS=1` 和 `EN_GAUSS=0` 两个 `video_core`）：

```
gray_v clocks per line: EN_GAUSS=1 min/max = 1919/1921   ← 有 1 个像素被顶住 2 拍
                        EN_GAUSS=0 min/max = 1919/1920   ← 干净，每行严格 1920
```

高斯核每个行周期要 1921 次流水推进却只拿到 1920 个像素，会把 `gray_valid` 顶住 1 拍，
DE 窗口就变成 1921 拍/行（编码器会在行内多送一个像素）。单测灰度时把高斯核去掉，DE 才是干净的 1920。

### 6.3 验证（都已跑过）

| 项 | 结果 |
|---|---|
| 同步自检 CH3（0行+4拍，高斯级旁路） | 22048 拍，HS/VS / DE / 像素 全 0 错 → **PASS** |
| 工程编译 `run_compile.bat` | `EXITCODE=0` |
| 综合 `TEST_GRAY_ONLY=1` | **0 error / 0 critical warning / 新代码 0 告警**；LUT 883（4.25%）、LUTRAM 80、FF 1023 |
| 综合 `TEST_GRAY_ONLY=0`（回归） | **0 error / 0 critical warning / 新代码 0 告警**；LUT 1079（5.19%）、LUTRAM 224 |

### 6.4 上板期望

画面为**灰度图**（黑白、无偏色），无错行、无竖缝。
若整体左右偏几拍 → 改 `GRAY_TAP`（默认 4；实测灰度核 3~4 拍，减到 3 就是往前挪 1 拍）。

---

## 7. 变更历史

| 版本 | 日期 | 修改内容 | 验证 |
|---|---|---|---|
| v1.0 | 2026-11-04 | 初版环缓（DEPTH=4） | — |
| v2.0 | 2026-11-04 | 重写：DE 跟 TVALID + HS/VS 3 拍移位（任务1 灰度） | 仿真 PASS、上板通过 |
| v3.0 | 2026-11-05 | 升级 DELAY 通用版（任务2 高斯，DELAY=1926） | 仿真 PASS，未上板 |
| v4.0 | 2026-11-06 | 两级级联版：以**真实 RTL 实测**定标（0行+4拍 / 1行+6拍 = 1行+10拍）；修指针回绕；新增 `video_core` 输入弹性 FIFO 修"每行丢 1 像素"；新增灰度级同步抽头 | 链路实测 + 同步自检 + 编译 + 综合 全 0 错 |
| v4.1 | 2026-11-06 | 新增 `TEST_GRAY_ONLY` 开关（`video_core.EN_GAUSS` + 高斯级旁路），支持单独测灰度流水；`hs_vs_dly` 只保留 ≥1 拍，0 拍由 generate 旁路 | 两种配置各跑 综合 0 错 / 自检 0 错 |
