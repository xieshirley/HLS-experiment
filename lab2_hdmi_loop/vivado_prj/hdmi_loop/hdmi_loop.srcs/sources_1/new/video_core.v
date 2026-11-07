`timescale 1ns / 1ps
//============================================================
// video_core.v —— 核处理层：灰度核 + 高斯核（两个核都例化，输出用多路选择器）
// 架构：HLS式 —— 核只做纯流式处理，行/场/数据有效同步由核外 video_sync 统一补偿
//============================================================
// 结构（不用 generate 分支选模式，两个核永远都在）：
//
//   rgb_in/de_in ──> rgb2gray ──[8bit 16 深弹性 FIFO]──> gauss3x3
//                        │                                  │
//                        │ gray_out/gray_valid              │ gauss_out/gauss_vld
//                        └──────────┬───────────────────────┘
//                                   ▼
//                          多路选择器 sel_gauss ──> smooth_out/smooth_valid
//
// 说明：
//   * 灰度核 dst TREADY 恒 1'b1（不反压）→ 灰度通路永远干净，等价 f11b691 的输出时序
//   * 两个核之间加 16 深弹性 FIFO：高斯核每个行周期会顶住 1 拍
//     （它每行需要 1921 次流水推进、只拿到 1920 个像素），由 FIFO 吃掉，不丢像素
//   * sel_gauss 选哪一路输出给 video_sync：1 = 高斯平滑结果，0 = 灰度
//     （想改成按键/VIO 实时切换，只要把这个端口接到按键或寄存器即可，
//       两个核始终在跑，切换只是换个多路选择器的输入）
//============================================================
module video_core(
    input             clk,          // 像素时钟 pixel_clk
    input             rst_n,        // 复位，低有效（接 ~rx_rst）
    input      [23:0] rgb_in,       // 输入 RGB（来自 hdmi_rx）
    input             de_in,        // 输入数据有效（video_de）
    output            src_ready,    // 灰度核 src TREADY（调试用，可悬空）
    // 灰度流（rgb2gray 输出，始终有效，可单独引出做灰度模式）
    output      [7:0] gray_out,
    output            gray_valid,
    // 送同步模块的像素流（由 sel_gauss 选择灰度 / 高斯）
    output      [7:0] smooth_out,
    output            smooth_valid,
    input             smooth_ready, // 下游可接收（顶层恒给 1'b1）
    // 输出选择：1 = 高斯平滑结果，0 = 灰度
    input             sel_gauss
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
    // 2. 灰度 → 高斯 之间的 8bit × 16 深弹性 FIFO
    //------------------------------------------------------------
    localparam integer FW = 4;                       // 地址位宽 → 16 深
    localparam integer FD = (1 << FW);

    reg  [7:0]    fifo_mem [0:FD-1];
    reg  [FW:0]   fifo_wptr;
    reg  [FW:0]   fifo_rptr;
    reg  [FW-1:0] fifo_raddr;

    wire [FW:0]   fifo_cnt   = fifo_wptr - fifo_rptr;
    wire          fifo_empty = (fifo_cnt == 0);
    wire          fifo_full  = fifo_cnt[FW];

    wire          gauss_src_rdy;                      // 高斯核 src TREADY
    wire          fifo_we = gray_valid & ~fifo_full;
    wire          fifo_rd = gauss_src_rdy & ~fifo_empty;   // 必须带"非空"

    always @(posedge clk) begin
        if (!rst_n) begin
            fifo_wptr  <= 0;
            fifo_rptr  <= 0;
            fifo_raddr <= 0;
        end else begin
            if (fifo_we) begin
                fifo_mem[fifo_wptr[FW-1:0]] <= gray_out;
                fifo_wptr <= fifo_wptr + 1'b1;
            end
            if (fifo_rd) begin
                fifo_rptr  <= fifo_rptr  + 1'b1;
                fifo_raddr <= fifo_raddr + 1'b1;
            end
        end
    end

    wire [7:0] fifo_dout  = fifo_mem[fifo_raddr];
    wire       fifo_valid = ~fifo_empty;

    //------------------------------------------------------------
    // 3. 高斯核（一直例化）
    //------------------------------------------------------------
    wire [7:0] gauss_out;
    wire       gauss_vld;

    gauss3x3 u_gauss3x3(
        .ap_clk          (clk),
        .ap_rst_n        (rst_n),
        .src_V_V_TDATA   (fifo_dout),
        .src_V_V_TVALID  (fifo_valid),
        .src_V_V_TREADY  (gauss_src_rdy),
        .dst_V_V_TDATA   (gauss_out),
        .dst_V_V_TVALID  (gauss_vld),
        .dst_V_V_TREADY  (smooth_ready)
    );

    //------------------------------------------------------------
    // 4. 输出多路选择器（不用 generate，纯组合选择）
    //------------------------------------------------------------
    assign smooth_out   =sel_gauss ? gauss_out : gray_out;
    assign smooth_valid =sel_gauss ? gauss_vld : gray_valid;

`ifndef SYNTHESIS
    //------------------------------------------------------------
    // 仿真自检：FIFO 溢出（高斯核吃不动就会报）+ 峰值占用
    //------------------------------------------------------------
    integer ovf_cnt;
    integer max_occ;
    initial begin ovf_cnt = 0; max_occ = 0; end
    always @(posedge clk) begin
        if (rst_n) begin
            if (fifo_cnt > max_occ) max_occ = fifo_cnt;
            if (gray_valid && fifo_full) begin
                ovf_cnt = ovf_cnt + 1;
                if (ovf_cnt <= 5)
                    $display("[%0t] ERROR: 灰度→高斯 FIFO 溢出（高斯核没在吃数据）ovf=%0d",
                             $time, ovf_cnt);
            end
        end
    end
`endif

endmodule
