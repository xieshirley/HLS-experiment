`timescale 1ns / 1ps
//============================================================================
// video_sync.v —— 核外同步对齐（核输出比输入原始同步慢 LATENCY 拍，默认 3 拍）
//
// 【为什么不能只用一个 3 级移位寄存器】
//   rgb2gray 核是 HLS 生成的 3 级流水线（ap_ctrl_none、1 像素/拍），但它有个
//   特点：src 端没有数据时整条流水线会被 ap_block 停住。视频的行/场消隐期
//   de_in 为 0，此时核里还在途的 3 个像素会被"挂住"，等 de_in 回来才继续吐。
//   所以核的 dst_TVALID 相对 de_in 并不是恒定的 3 个时钟，在消隐/换行处会
//   多拖 1~3 拍（仿真已确认：224 拍里有 14 拍 DE 与 valid 差 1 拍）。
//   → 如果 de/hs/vs 用固定 3 级移位寄存器，换行处 DE 和像素就会错开 1 拍，
//     表现为每行行首/行尾丢 1 个像素。
//
// 【本模块的做法】
//   * DE  ：直接跟随核输出的 gray_valid（dst TVALID）。
//           核几拍出像素，DE 就几拍有效 —— 天然"慢 3 拍"，且核停顿多少拍
//           都自动跟随，永远不会和像素错开。
//   * HS/VS：纯时间域信号，消隐期也要连续正确，所以用 LATENCY 级移位寄存器
//           延迟 3 个时钟，和核的 3 拍延迟对齐。
//   * 像素：核输出已寄存过，直接送 {gray,gray,gray}，不再打拍（多打一拍就
//           会和 DE 差 1 拍）。
//
// 【时序关系】
//   周期 n   : de_in=1，核输入第 k 个像素
//   周期 n+3 : 核输出 gray_valid=1（dst valid），gray_in=第 k 个像素的灰度
//   周期 n+3 : de_out=1（=gray_valid），hs_out/vs_out=3 拍前的 hs/vs
//   像素、DE 严格同拍，整组输出相对输入延迟 3 拍。
//============================================================================
module video_sync #(
    parameter integer LATENCY = 3          // 核流水线延迟拍数（ILA/仿真标定，默认 3）
)(
    input                       clk,       // 像素时钟 pixel_clk
    input                       rst_n,     // 复位，低有效（接 ~rx_rst）
    // 核输出（rgb2gray，AXI4-Stream 的 dst 端）
    input       [7:0]           gray_in,   // dst_V_V_TDATA
    input                       gray_valid,// dst_V_V_TVALID
    // 输入原始同步（来自 hdmi_rx）
    input                       de_in,     // 数据有效
    input                       hs_in,     // 行同步
    input                       vs_in,     // 场同步
    // 对齐输出（送 dvi_transmitter_top）
    output      [23:0]          rgb_out,   // {gray,gray,gray}
    output                      de_out,    // 与核输出像素严格同拍（= 3 拍后）
    output                      hs_out,    // = hs_in 延迟 LATENCY 拍
    output                      vs_out     // = vs_in 延迟 LATENCY 拍
);

    //------------------------------------------------------------------
    // 1. 数据有效：直接取核输出 TVALID
    //    （等价于 de_in 延迟 3 拍，但核停顿/反压时也不会错拍）
    //------------------------------------------------------------------
    assign de_out = gray_valid;

    //------------------------------------------------------------------
    // 2. 行/场同步：LATENCY 级移位寄存器，纯按拍延迟
    //    HS/VS 在消隐期是有脉冲的，必须连续按拍搬移，不能按有效像素计数。
    //------------------------------------------------------------------
    reg [1:0] sync_dly [0:LATENCY-1];      // {hs, vs}
    integer   i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < LATENCY; i = i + 1)
                sync_dly[i] <= 2'b00;
        end else begin
            sync_dly[0] <= {hs_in, vs_in};
            for (i = 1; i < LATENCY; i = i + 1)
                sync_dly[i] <= sync_dly[i-1];
        end
    end

    assign {hs_out, vs_out} = sync_dly[LATENCY-1];

    //------------------------------------------------------------------
    // 3. 像素：核输出本身已寄存，这里不再打拍，保证和 DE 同拍
    //------------------------------------------------------------------
    assign rgb_out = {3{gray_in}};         // 灰度 → R=G=B

`ifndef SYNTHESIS
    //------------------------------------------------------------------
    // 仿真自检：核输出的拍数不能超过输入拍数（丢了/多吐了都说明核的
    // AXI-Stream 行为异常）。另外 LATENCY 若标定错了，这里不会报，
    // 但 DE 依旧跟像素同拍，只是 HS/VS 会差几拍。
    //------------------------------------------------------------------
    integer beat_in, beat_out;

    always @(posedge clk) begin
        if (!rst_n) begin
            beat_in  <= 0;
            beat_out <= 0;
        end else begin
            if (de_in)      beat_in  <= beat_in  + 1;
            if (gray_valid) beat_out <= beat_out + 1;
        end
    end

    always @(posedge clk) begin
        if (rst_n && (beat_out > beat_in))
            $display("[%0t] ERROR: 核输出拍数(%0d) > 输入拍数(%0d)，核 AXI-Stream 行为异常",
                     $time, beat_out, beat_in);
    end
`endif

endmodule
