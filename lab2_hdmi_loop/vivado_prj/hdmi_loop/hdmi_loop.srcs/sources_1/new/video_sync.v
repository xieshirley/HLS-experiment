`timescale 1ns / 1ps
//============================================================
// video_sync.v —— 核外同步补偿（两种输出方式，用参数选，不用 generate）
//------------------------------------------------------------
// USE_FIFO_OUT = 0（灰度模式用，已验证）：
//   de_out  = 核输出 TVALID
//   rgb_out = {3{gray_in}}
//   → 像素和 DE 同源，最简单、延迟最小
//
// USE_FIFO_OUT = 1（高斯模式用）：
//   de_out/hs_out/vs_out = de_in/hs_in/vs_in 精确延迟 LATENCY 拍
//   rgb_out = 从像素 FIFO 里按显示 DE 读出的数据
//   → 编码器看到的行/场结构与输入完全一致，**核再怎么停顿、抖动都不会破坏画面锁定**；
//     核的像素只是被 FIFO 吸收后按显示节拍吐出（抖动只影响个别像素位置，不影响锁相）
//
// HS/VS/DE 的延迟实现：packed 移位链（不是 FIFO、不是 for 循环）
//   * 每拍移 3 位，综合成 SRL32E 链，延迟严格等于 LATENCY 拍
//   * 不加复位（加了会退化成触发器阵列且清掉延迟内容），上电初值 0 安全
//
// 用法：
//   灰度模式 LATENCY = 3     （灰度核 3~4 拍流水），USE_FIFO_OUT = 0
//   高斯模式 LATENCY = 2205  （1 行 2200 拍 + 5 拍流水），USE_FIFO_OUT = 1
//============================================================
module video_sync #(
    parameter integer LATENCY      = 3,
    parameter integer USE_FIFO_OUT = 0
)(
    input             clk,          // 像素时钟
    input             rst_n,        // 复位（低有效，只用于像素 FIFO）
    input      [7:0]  gray_in,      // 核输出像素
    input             gray_valid,   // 核输出 TVALID
    input             de_in,        // 输入数据有效（规整的 1920 拍/行）
    input             hs_in,        // 输入行同步
    input             vs_in,        // 输入场同步
    output     [23:0] rgb_out,      // 送 DVI 编码器
    output            de_out,
    output            hs_out,
    output            vs_out,
    output            und_evt,     // 1 = 本拍 DE 有效但 FIFO 为空（欠载 -> 黑像素）
    output            ovf_evt      // 1 = 本拍有像素因 FIFO 满被丢弃（溢出 -> 撕裂/错位）
);

    //------------------------------------------------------------
    // 1. DE/HS/VS 精确延迟 LATENCY 拍（packed 移位链，无 for、无复位）
    //    每拍移 3 位（de/hs/vs 各一位）→ 要求 3*LATENCY >= 4，
    //    所以内部下限取 2 拍（LATENCY=1 时按 2 拍实现，误差 1 拍，
    //    只影响"校准实验"里 2204/2203 拍的读数，不影响错位现象）
    //------------------------------------------------------------
    localparam integer LAT = (LATENCY < 2) ? 2 : LATENCY;

    reg  [3*LAT-1:0] sr;

    always @(posedge clk) begin
        sr <= {sr[3*LAT-4:0], de_in, hs_in, vs_in};
    end

    wire de_del = sr[3*LAT-1];   // 每 3 位一组：de 在最高、hs 居中、vs 在最低
    wire hs_del = sr[3*LAT-2];
    wire vs_del = sr[3*LAT-3];

    //------------------------------------------------------------
    // 2. 像素 FIFO：核输出写入（带抖动），按显示 DE 读出
    //    深度 512：核平均吞吐与显示 1:1，只需吸收抖动，永不溢出
    //------------------------------------------------------------
    // 深度 4096：帧末那一行只写不读的补 0 行会在消隐期一次性吐出约 1920 个像素，
    // FIFO 必须 >= 一整行才装得下（原来 512 深 -> 每帧溢出约 1400 个像素）。
    localparam integer FW = 12;
    localparam integer FD = (1 << FW);

    reg  [7:0]  mem [0:FD-1];
    reg  [FW:0] wp, rp;

`ifndef SYNTHESIS
    //------------------------------------------------------------
    // 仿真专用：给 SRL 移位链和像素 FIFO 一个确定的初值。
    //   不加这两句时，上电后前 LATENCY 拍 de/hs/vs 是 X、FIFO 未写过的
    //   单元读出来也是 X —— 波形里就是"开头一片红色"。
    //   综合时本段被 `ifndef SYNTHESIS 排除，BRAM/SRL 推断完全不变。
    //------------------------------------------------------------
    integer init_i;
    initial begin
        sr = {3*LAT{1'b0}};
        for (init_i = 0; init_i < FD; init_i = init_i + 1)
            mem[init_i] = 8'd0;
    end
`endif

    wire [FW:0] cnt  = wp - rp;
    wire        full = cnt[FW];
    wire        we   = gray_valid & ~full;         // 核有数据就写
    wire        re   = de_del & (cnt != 0);        // 显示窗口内、且非空才读

    always @(posedge clk) begin
        if (!rst_n) begin
            wp <= 0;
            rp <= 0;
        end else begin
            if (we) begin
                mem[wp[FW-1:0]] <= gray_in;
                wp <= wp + 1'b1;
            end
            if (re) begin
                rp <= rp + 1'b1;
            end
        end
    end

    wire [7:0] pix_fifo = (cnt != 0) ? mem[rp[FW-1:0]] : 8'd0;

    // 欠载指示：DE 有效但 FIFO 为空 —— 说明 DE 比数据早到（延迟给小了）
    assign und_evt = USE_FIFO_OUT ? (de_del & (cnt == 0)) : 1'b0;

    // 溢出指示：有数据但 FIFO 满写不进去 —— 说明深度不够（帧边界突发装不下）
    assign ovf_evt = USE_FIFO_OUT ? (gray_valid & full) : 1'b0;

    //------------------------------------------------------------
    // 3. 输出选择（参数常量化，综合时直接折叠，不用 generate）
    //------------------------------------------------------------
    assign de_out  = USE_FIFO_OUT ? de_del : gray_valid;
    assign hs_out  = hs_del;
    assign vs_out  = vs_del;
    assign rgb_out = {3{(USE_FIFO_OUT ? pix_fifo : gray_in)}};

endmodule
