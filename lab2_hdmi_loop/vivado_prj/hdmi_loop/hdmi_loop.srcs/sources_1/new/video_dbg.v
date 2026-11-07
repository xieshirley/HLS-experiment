`timescale 1ns / 1ps
//============================================================
// video_dbg.v —— ILA 调试辅助：统计"每帧"灰度核/高斯核的有效拍数
//------------------------------------------------------------
// 作用：ILA 一次只能抓 1024 拍（≈6.9us），抓不到整帧；但这两路计数在
//   每个 vs 上升沿锁存一次，抓到任何时刻都能看到"上一帧到底出了多少个像素"：
//     正常：gray_beats ≈ gauss_beats ≈ 1920×1080 = 2,073,600
//     高斯不工作：gauss_beats = 0（或远小于 2073600）
//   这样一次抓取就能判定"高斯核到底有没有输出数据"。
//============================================================
module video_dbg (
    input             clk,           // pixel_clk
    input             rst_n,         // 低有效
    input             vs_in,         // 场同步（每帧锁存一次）
    input             gray_valid,    // 灰度核输出 TVALID
    input             smooth_valid,  // 高斯核输出 TVALID
    output reg [23:0] gray_beats,    // 上一帧灰度有效拍数
    output reg [23:0] gauss_beats    // 上一帧高斯有效拍数
);

    reg [23:0] cg;                   // 本帧灰度计数
    reg [23:0] cs;                   // 本帧高斯计数
    reg        vs_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            cg          <= 24'd0;
            cs          <= 24'd0;
            gray_beats  <= 24'd0;
            gauss_beats <= 24'd0;
            vs_d        <= 1'b0;
        end else begin
            vs_d <= vs_in;

            if (gray_valid   && (cg != 24'hFFFFFF)) cg <= cg + 24'd1;
            if (smooth_valid && (cs != 24'hFFFFFF)) cs <= cs + 24'd1;

            // 帧边界：锁存上一帧结果并清零
            if (vs_in && !vs_d) begin
                gray_beats  <= cg;
                gauss_beats <= cs;
                cg          <= 24'd0;
                cs          <= 24'd0;
            end
        end
    end

endmodule
