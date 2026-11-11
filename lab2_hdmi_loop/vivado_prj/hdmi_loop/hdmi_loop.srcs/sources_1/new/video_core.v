`timescale 1ns / 1ps
//============================================================
// video_core.v —— 核处理层：灰度核 + 高斯核 + 锐化核（全部在 HLS 核内完成）
//------------------------------------------------------------
// 数据流（两个 HLS 核并联，各带一个 16 深弹性 FIFO）：
//
//   rgb_in/de_in ──> rgb2gray ──┬──[16 深 FIFO]──> gauss3x3   ──> gauss_out / gauss_valid
//                        │      │
//                        │      └──[16 深 FIFO]──> unsharp3x3 ──> sharp_out / sharp_valid
//                        │                                       （2*orig ? smooth，核内算）
//                        └─ gray_out / gray_valid
//
// 为什么锐化放进 HLS 核（不再用 RTL 做 2*orig?smooth）：
//   高斯核每帧有一整行"只写不读"的补 0 行（内部 i=1080），它的 1920 个输出
//   挤在消隐期吐出；在 RTL 里用"灰度 FIFO 配对"的方案，会在帧边界出现
//   约一整行的配对缺口 → 内容逐帧下移 1 行（上板表现为"两帧重写"）。
//   把 sharp = 2*orig ? smooth 放进核内，两个核的时序/帧边界行为完全一致，
//   不再需要任何跨核对齐。
//
// 说明：
//   * 灰度核 dst TREADY 恒 1'b1（不反压）
//   * 每个 HLS 核前面各有一个 16 深弹性 FIFO：核每行会顶住 1 拍
//     （每行 1921 次流水推进、只拿到 1920 个像素），由 FIFO 吃掉，不丢像素
//============================================================
module video_core(
    input             clk,          // 像素时钟 pixel_clk
    input             rst_n,        // 复位，低有效（接 ~rx_rst）
    input      [23:0] rgb_in,       // 输入 RGB（来自 hdmi_rx）
    input             de_in,        // 输入数据有效（video_de）
    output            src_ready,    // 灰度核 src TREADY（调试用，可悬空）

    // 灰度流
    output      [7:0] gray_out,
    output            gray_valid,

    // 高斯平滑流
    output      [7:0] gauss_out,
    output            gauss_valid,
    input             gauss_ready,  // 下游可接收（顶层恒给 1'b1）

    // 锐化流（非锐化掩模，核内计算；比 gauss 多 1 级流水）
    output      [7:0] sharp_out,
    output            sharp_valid,
    input             sharp_ready
);

    //------------------------------------------------------------
    // 1. 灰度核（一直例化，dst 不反压）
    //------------------------------------------------------------
    rgb2gray u_rgb2gray(
        .ap_clk          (clk),
        .ap_rst_n        (rst_n),
        .src_V_V_TDATA   (rgb_in),
        .src_V_V_TVALID  (de_in),
        .src_V_V_TREADY  (src_ready),
        .dst_V_V_TDATA   (gray_out  ),
        .dst_V_V_TVALID  (gray_valid),
        .dst_V_V_TREADY  (1'b1)          // 永不反压
    );

    //------------------------------------------------------------
    // 2. 两个 8bit × 16 深弹性 FIFO（各喂一个 HLS 核）
    //------------------------------------------------------------
    localparam integer FW = 4;                       // 16 深
    localparam integer FD = (1 << FW);

    // ---- 2a. 灰度 → 高斯 ----
    reg  [7:0]  g_mem [0:FD-1];
    reg  [FW:0] g_wp, g_rp;
    wire [FW:0] g_cnt   = g_wp - g_rp;
    wire        g_empty = (g_cnt == 0);
    wire        g_full  = g_cnt[FW];
    wire        gauss_src_rdy;
    wire        g_we = gray_valid & ~g_full;
    wire        g_rd = gauss_src_rdy & ~g_empty;

    always @(posedge clk) begin
        if (!rst_n) begin
            g_wp <= 0; g_rp <= 0;
        end else begin
            if (g_we) begin g_mem[g_wp[FW-1:0]] <= gray_out; g_wp <= g_wp + 1'b1; end
            if (g_rd) begin g_rp <= g_rp + 1'b1; end
        end
    end
    wire [7:0] g_dout  = g_mem[g_rp[FW-1:0]];
    wire       g_valid = ~g_empty;

    // ---- 2b. 灰度 → 锐化 ----
    reg  [7:0]  s_mem [0:FD-1];
    reg  [FW:0] s_wp, s_rp;
    wire [FW:0] s_cnt   = s_wp - s_rp;
    wire        s_empty = (s_cnt == 0);
    wire        s_full  = s_cnt[FW];
    wire        sharp_src_rdy;
    wire        s_we = gray_valid & ~s_full;
    wire        s_rd = sharp_src_rdy & ~s_empty;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_wp <= 0; s_rp <= 0;
        end else begin
            if (s_we) begin s_mem[s_wp[FW-1:0]] <= gray_out; s_wp <= s_wp + 1'b1; end
            if (s_rd) begin s_rp <= s_rp + 1'b1; end
        end
    end
    wire [7:0] s_dout  = s_mem[s_rp[FW-1:0]];
    wire       s_valid = ~s_empty;

    //------------------------------------------------------------
    // 3. 两个 HLS 核并联
    //------------------------------------------------------------
    gauss3x3 u_gauss3x3(
        .ap_clk          (clk),
        .ap_rst_n        (rst_n),
        .src_V_V_TDATA   (g_dout),
        .src_V_V_TVALID  (g_valid),
        .src_V_V_TREADY  (gauss_src_rdy),
        .dst_V_V_TDATA   (gauss_out),
        .dst_V_V_TVALID  (gauss_valid),
        .dst_V_V_TREADY  (gauss_ready)
    );

    unsharp3x3 u_unsharp3x3(
        .ap_clk          (clk),
        .ap_rst_n        (rst_n),
        .src_V_V_TDATA   (s_dout),
        .src_V_V_TVALID  (s_valid),
        .src_V_V_TREADY  (sharp_src_rdy),
        .dst_V_V_TDATA   (sharp_out),
        .dst_V_V_TVALID  (sharp_valid),
        .dst_V_V_TREADY  (sharp_ready)
    );

`ifndef SYNTHESIS
    //------------------------------------------------------------
    // 仿真自检：两个弹性 FIFO 的溢出与峰值占用
    //------------------------------------------------------------
    integer g_ovf, g_max, s_ovf, s_max;

    // 上电初值：两个 16 深弹性 FIFO 的存储体清 0，
    // 否则仿真开头读到未写过的单元会是 X（波形红色）。
    integer init_i;
    initial begin
        g_ovf = 0; g_max = 0; s_ovf = 0; s_max = 0;
        for (init_i = 0; init_i < FD; init_i = init_i + 1) begin
            g_mem[init_i] = 8'd0;
            s_mem[init_i] = 8'd0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (g_cnt > g_max) g_max = g_cnt;
            if (s_cnt > s_max) s_max = s_cnt;
            if (gray_valid && g_full) begin
                g_ovf = g_ovf + 1;
                if (g_ovf <= 5)
                    $display("[%0t] ERROR: 灰度→高斯 FIFO 溢出 ovf=%0d", $time, g_ovf);
            end
            if (gray_valid && s_full) begin
                s_ovf = s_ovf + 1;
                if (s_ovf <= 5)
                    $display("[%0t] ERROR: 灰度→锐化 FIFO 溢出 ovf=%0d", $time, s_ovf);
            end
        end
    end
`endif

endmodule
