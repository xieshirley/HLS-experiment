`timescale 1ns / 1ps
//============================================================
// video_core.v —— 核处理层：例化任务1 rgb2gray HLS 核
// 架构：HLS式 —— 核只做纯流式处理，行/场/数据有效同步
//       由核外 video_sync 统一补偿
// 扩展：任务2/3 的核后续在本文件内追加例化（axis 同拍级联）
//============================================================
module video_core(
    input             clk,          // 像素时钟 pixel_clk
    input             rst_n,        // 复位，低有效（接 ~rx_rst）
    input      [23:0] rgb_in,       // 输入 RGB（来自 hdmi_rx）
    input             de_in,        // 输入数据有效（video_de → src TVALID）
    output            src_ready,    // 核输入可接收（src TREADY，回读/调试）
    output      [7:0] gray_out,     // 灰度输出（核 dst TDATA）
    output            gray_valid,   // 灰度有效（核 dst TVALID）
    input             gray_ready    // 下游可接收（恒1：同步模块不反压）
);

    // ---- 任务1：rgb2gray HLS 核（AXI4-Stream 直连，ap_ctrl_none） ----
    rgb2gray u_rgb2gray(
        .ap_clk          (clk),
        .ap_rst_n        (rst_n),
        .src_V_V_TDATA   (rgb_in),
        .src_V_V_TVALID  (de_in),
        .src_V_V_TREADY  (src_ready),
        .dst_V_V_TDATA   (gray_out),
        .dst_V_V_TVALID  (gray_valid),
        .dst_V_V_TREADY  (gray_ready)
    );

endmodule
