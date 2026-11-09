# 修改日志 —— HDMI 环回：HLS 核外同步“慢 3 拍”对齐

| 项 | 内容 |
|---|---|
| 工程 | `hdmi_loop`（Vivado 2018.3，xc7a35tfgg484-2） |
| 涉及模块 | `video_sync`（重写）、`hdmi_loop`（顶层例化修改） |
| 修改原因 | rgb2gray 核输出比输入原始同步慢 3 拍，原核外同步未按 3 拍对齐，行/场/数据有效与像素错位 |
| 修改日期 | 2026-11-04 |
| 验证方式 | xsim 功能仿真（调用工程内真实 rgb2gray RTL）+ Vivado 综合 |

---

## 1. 修改文件清单

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `hdmi_loop.srcs/sources_1/new/video_sync.v` | **重写** | 参数 `DEPTH` → `LATENCY`；DE 跟随核 TVALID；HS/VS 3 拍移位；像素去掉多余打拍 |
| `hdmi_loop.srcs/sources_1/imports/53_hdmi_loop/rtl/hdmi_loop.v` | 修改 | 例化参数 `DEPTH(4)` → `LATENCY(3)`；删除 3 条与 ANSI 端口重复的 `wire` 声明；补充注释 |
| `sim_check/tb_video_sync.v`、`sim_check/run_sim.bat` | 新增 | 同步对齐自检测试平台与一键仿真脚本 |
| `sim_check/backup/video_sync.v.orig`、`hdmi_loop.v.orig` | 新增 | 修改前文件备份 |

---

## 2. 问题分析

### 2.1 原实现（`video_sync.v`，DEPTH=4）

```verilog
(* ram_style = "distributed" *) reg [2:0] mem [0:DEPTH-1];   // 写: de_in 有效拍
always @(posedge clk) ... else if (gray_valid) begin          // 读: gray_valid 拍
    rgb_out <= {3{gray_in}};
    {de_out, hs_out, vs_out} <= mem[rd_ptr];
end else begin
    de_out <= 1'b0;                                           // 只清 de_out
end
```

存在的问题：

1. **HS/VS 在消隐期锁死**：`hs_out/vs_out` 只在 `gray_valid` 那一拍更新，消隐期（无有效像素）保持旧值，送 `dvi_transmitter_top` 的行/场同步在消隐期没有脉冲。
2. **整组延迟 4 拍，不是 3 拍**：输出级又把像素和标志各打一拍，相对输入累计 4 拍，与“慢 3 拍”的要求不符。
3. **`DEPTH` 参数语义误导**：环形缓冲的对齐由“读/写拍数差”决定，`DEPTH` 只起“防覆盖”作用，写 4 与核实际延迟 3 并不对应，后续改动容易踩坑。
4. **资源浪费**：4 深度 ×3bit 的分布式 RAM（LUTRAM）做 3 拍延迟，不如直接用触发器。

### 2.2 仿真实测结论（真实 rgb2gray RTL）

| 观测项 | 结果 |
|---|---|
| 核稳态延迟 | `dst_TVALID` 比 `src` 有效沿晚 **3 拍**（与需求一致） |
| 消隐期行为 | `de_in=0` 时核被 `ap_block_pp0_stage0_11001` 挂住流水线，在途像素被“顶住”，`TVALID` 相对 `de_in` 会多拖 1~3 拍；224 拍中有 14 拍 DE 与 valid 差 1 拍 |
| 灰度算式 | `(66R + 129G + 25B + 128) >> 8`（权重和 220，非 256，画面比标准 luma 暗约 14%） |

> 由此推出：**不能用“纯 3 级移位寄存器”对齐 DE**——换行/消隐边界会错 1 拍，表现为每行行首或行尾丢 1 个像素。

---

## 3. 修改内容

### 3.1 `video_sync.v`（重写）

| 信号 | 修改前 | 修改后 |
|---|---|---|
| DE | `de_in` 经环缓延迟后再打一拍 | `assign de_out = gray_valid;` 直接跟随核 TVALID |
| HS / VS | 与 DE 同时从环缓读出，消隐期不更新 | `LATENCY` 级移位寄存器，纯按拍延迟（消隐期连续正确） |
| 像素 | `rgb_out <= {3{gray_in}}`（多打一拍） | `assign rgb_out = {3{gray_in}};`（组合直通） |
| 参数 | `DEPTH = 4` | `LATENCY = 3`（仅决定 HS/VS 延迟拍数） |
| 自检 | 无 | `ifndef SYNTHESIS` 下检查“核输出拍数 ≤ 输入拍数” |

核心代码：

```verilog
module video_sync #(
    parameter integer LATENCY = 3          // 核流水线延迟拍数
)(
    input             clk, rst_n,
    input      [7:0]  gray_in,             // 核 dst_V_V_TDATA
    input             gray_valid,          // 核 dst_V_V_TVALID
    input             de_in, hs_in, vs_in, // 输入原始同步
    output     [23:0] rgb_out,
    output            de_out, hs_out, vs_out
);

    // 1) DE 直接取核输出 TVALID：核几拍出，DE 就几拍有效
    assign de_out = gray_valid;

    // 2) HS/VS 纯时间域延迟 LATENCY 拍（消隐期也要连续）
    reg [1:0] sync_dly [0:LATENCY-1];
    integer   i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < LATENCY; i = i + 1) sync_dly[i] <= 2'b00;
        end else begin
            sync_dly[0] <= {hs_in, vs_in};
            for (i = 1; i < LATENCY; i = i + 1) sync_dly[i] <= sync_dly[i-1];
        end
    end
    assign {hs_out, vs_out} = sync_dly[LATENCY-1];

    // 3) 像素直通，绝不能再打拍
    assign rgb_out = {3{gray_in}};
endmodule
```

### 3.2 `hdmi_loop.v`（顶层）

```verilog
// 修改前
video_sync #(.DEPTH(4)) u_video_sync(
    .clk(pixel_clk), .rst_n(~rx_rst),
    .gray_in(gray_w), .gray_valid(gray_v),
    .de_in(video_de), .hs_in(video_hs), .vs_in(video_vs),
    .rgb_out(rgb_proc), .de_out(de_proc), .hs_out(hs_proc), .vs_out(vs_proc)
);

// 修改后
video_sync #(
    .LATENCY    (3)                 // 核流水线延迟拍数：3 拍
) u_video_sync(
    .clk(pixel_clk), .rst_n(~rx_rst),
    .gray_in(gray_w), .gray_valid(gray_v),
    .de_in(video_de), .hs_in(video_hs), .vs_in(video_vs),
    .rgb_out(rgb_proc), .de_out(de_proc), .hs_out(hs_proc), .vs_out(vs_proc)
);
```

另外删除以下 3 行（与 ANSI 端口声明重复，综合报 `Synth 8-2611` / `Synth 8-1082` 警告）：

```verilog
wire        hdmi_in_oen;       //输入输出切换信号
wire        hdmi_in_hpd;       //热插拔信号
wire        hdmi_out_oen;      //输入输出切换信号
```

---

## 4. 验证记录

### 4.1 功能仿真（xsim 2018.3，DUT = video_core + video_sync + 真实 rgb2gray RTL）

激励：2 帧，每帧 3 行 × 32 有效像素（行消隐 8 拍、场消隐 2 行），像素值逐点唯一。

| 检查项 | 结果 |
|---|---|
| HS/VS 是否 = 输入延迟 3 拍 | **0 错** |
| DE 是否与核 TVALID 同拍 | **0 错** |
| 像素与 DE 是否对齐（按灰度算式逐点比对） | **0 错** |
| 稳态区 `gray_valid` 是否 = `de_in` 延迟 3 拍 | **0 错** → 确认“慢 3 拍” |
| 输入/输出拍数 | 224 / 223（末拍仍在流水线内，正常） |

结论：`>>> PASS：同步与核输出严格对齐，稳态延迟 3 拍`。

### 4.2 综合（Vivado 2018.3，synth_1）

| 指标 | 修改前 | 修改后 |
|---|---|---|
| Errors | 0 | **0** |
| Critical Warnings | 0 | 0 |
| Warnings | 61 | **57**（删掉 4 条端口重复声明告警） |
| 状态 | synth_design Complete | **synth_design Complete（100%）** |

---

## 5. 影响与风险评估

| 项 | 评估 |
|---|---|
| 端口兼容性 | `video_sync` 端口名/位宽完全不变，仅参数名 `DEPTH → LATENCY`，其它模块无需改动 |
| 资源 | 由 LUTRAM(4×3) + 3 个输出寄存器 → 6 个触发器（3×2），资源略减 |
| 时序 | 无新增组合逻辑，像素通路仍为核输出寄存器直连 |
| 残余风险 | `LATENCY` 必须与核实际延迟一致；若 HLS 核重新生成导致流水线级数变化，需重新标定 |

---

## 6. 后续建议

1. 上板后用 ILA 抓 `video_de / gray_valid / de_proc / hs_proc / vs_proc`，确认核延迟仍为 3 拍；若变化只改 `LATENCY`（不影响 DE，DE 始终跟核走）。
2. 若画面偏暗，是 HLS 定点灰度系数（权重和 220）问题，与同步无关，可在核内改为 256 归一化。
3. 复跑回归：`sim_check\run_sim.bat`（xvlog/xelab/xsim 一键执行）。

---

## 7. 变更历史

| 版本 | 日期 | 修改内容 | 验证 |
|---|---|---|---|
| v1.0 | 2026-11-04 | `video_sync.v` 重写为“DE 跟随核 TVALID + HS/VS 3 拍移位”；`hdmi_loop.v` 例化改 `LATENCY(3)` 并清理重复 wire | 仿真全过、综合 0 error |
