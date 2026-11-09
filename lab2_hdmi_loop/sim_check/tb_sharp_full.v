`timescale 1ns / 1ps
//=============================================================================
// tb_sharp_full.v —— 整帧（1080 行）验证锐化通路
//   目的：跨过高斯核的 1080 行帧边界，检查
//     1) 每帧 gray / gauss / sharp 的拍数是否都等于 1920*1080 = 2,073,600
//     2) 对齐 FIFO（gray 配对）是否溢出/欠载
//     3) video_sync 像素 FIFO 是否欠载（und_evt），以及错位拍数
//   与 tb_sharp 的区别：行数按真实 1080 行、并按 vs 分帧统计
//=============================================================================
module tb_sharp_full;

    localparam integer H_ACTIVE = 1920;
    localparam integer H_BLANK  = 280;
    localparam integer V_ACTIVE = 1080;
    localparam integer V_BLANK  = 4;          // 真实是 45，这里压到 4 以缩短仿真
    localparam integer H_TOTAL  = H_ACTIVE + H_BLANK;
    localparam integer V_TOTAL  = V_ACTIVE + V_BLANK;

    localparam integer SYNC_LAT = 2218;       // 与上板 SCAN_m278 之外的一档，仅用于测欠载

    reg clk = 0;
    always #3.3665 clk = ~clk;                // 148.5MHz
    reg rst_n = 0;

    //-------------------------------------------------------------
    // 激励
    //-------------------------------------------------------------
    reg  [23:0] rgb_in;
    reg         de_in, hs_in, vs_in;
    integer     hcnt = 0, vcnt = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            hcnt <= 0; vcnt <= 0;
            de_in <= 0; hs_in <= 0; vs_in <= 0; rgb_in <= 0;
        end else begin
            if (hcnt == H_TOTAL-1) begin
                hcnt <= 0;
                if (vcnt == V_TOTAL-1) vcnt <= 0; else vcnt <= vcnt + 1;
            end else begin
                hcnt <= hcnt + 1;
            end
            de_in <= (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
            hs_in <= (hcnt == H_ACTIVE + 2);
            vs_in <= (vcnt == V_ACTIVE + 2);
            rgb_in <= ((hcnt < H_ACTIVE) && (vcnt < V_ACTIVE))
                      ? {8'h00, 8'h00, hcnt[7:0]} : 24'h000000;
        end
    end

    //-------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------
    wire [7:0] gray_w, gauss_w, sharp_w;
    wire       gray_v, gauss_v, sharp_v, src_ready;

    video_core u_core (
        .clk(clk), .rst_n(rst_n),
        .rgb_in(rgb_in), .de_in(de_in), .src_ready(src_ready),
        .gray_out(gray_w), .gray_valid(gray_v),
        .gauss_out(gauss_w), .gauss_valid(gauss_v), .gauss_ready(1'b1),
        .sharp_out(sharp_w), .sharp_valid(sharp_v)
    );

    // video_sync（像素 FIFO 模式），用来测欠载与错位
    wire [23:0] rgb_s;
    wire de_s, hs_s, vs_s, und_evt;
    video_sync #(.LATENCY(SYNC_LAT), .USE_FIFO_OUT(1)) u_sync (
        .clk(clk), .rst_n(rst_n),
        .gray_in(sharp_w), .gray_valid(sharp_v), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_s), .de_out(de_s), .hs_out(hs_s), .vs_out(vs_s),
        .und_evt(und_evt)
    );

    //-------------------------------------------------------------
    // 按 vs 分帧统计
    //-------------------------------------------------------------
    integer n_gray = 0, n_gauss = 0, n_sharp = 0, n_und = 0, n_de = 0;

    // 逐行（按 hs_in 分线）统计 gauss / sharp 的拍数，找出帧边界突发
    integer l_gauss = 0, l_sharp = 0, l_de = 0;
    integer l_max_g = 0, l_max_s = 0, l_max_de = 0, l_bad = 0, l_idx = 0;
    reg     hs_in_d = 0;
    integer f_gray = -1, f_gauss = -1, f_sharp = -1, f_und = -1, f_de = -1;
    integer nframe = 0;
    reg     vs_d = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (gray_v)  n_gray  = n_gray  + 1;
            if (gauss_v) n_gauss = n_gauss + 1;
            if (sharp_v) n_sharp = n_sharp + 1;
            if (de_s)    n_de    = n_de    + 1;
            if (und_evt) n_und   = n_und   + 1;

            // vs 上升沿 = 一帧结束
            if (vs_in && !vs_d && (nframe >= 1)) begin
                if (f_gray < 0) begin
                    f_gray  = n_gray;  f_gauss = n_gauss; f_sharp = n_sharp;
                    f_de    = n_de;    f_und   = n_und;
                    $display("第 %0d 帧统计（按 vs 分帧）：", nframe);
                    $display("  gray  = %0d  (期望 2073600)", f_gray);
                    $display("  gauss = %0d  (期望 2073600)", f_gauss);
                    $display("  sharp = %0d  (期望 2073600)", f_sharp);
                    $display("  DE    = %0d  (期望 2073600)", f_de);
                    $display("  欠载次数 = %0d", f_und);
                    $display("  对齐FIFO 峰值=%0d 溢出=%0d 欠载=%0d",
                             u_core.p_max, u_core.p_ovf, u_core.p_und);
                    $finish;
                end
            end

            // ---- 逐行统计：hs 上升沿 = 一行结束 ----
            if (hs_in && !hs_in_d) begin
                if (l_gauss > l_max_g) l_max_g = l_gauss;
                if (l_sharp > l_max_s) l_max_s = l_sharp;
                if (l_de    > l_max_de) l_max_de = l_de;
                if (l_gauss != 1920) begin
                    l_bad = l_bad + 1;
                    if (l_bad <= 8)
                        $display("  [行 %0d] gauss=%0d sharp=%0d de=%0d  ← 不等于 1920",
                                 l_idx, l_gauss, l_sharp, l_de);
                end
                l_idx = l_idx + 1;
                l_gauss = 0; l_sharp = 0; l_de = 0;
            end
            if (gauss_v) l_gauss = l_gauss + 1;
            if (sharp_v) l_sharp = l_sharp + 1;
            if (de_s)    l_de    = l_de    + 1;
            hs_in_d <= hs_in;

            if (vs_in && !vs_d) begin
                nframe = nframe + 1;
                n_gray = 0; n_gauss = 0; n_sharp = 0; n_de = 0; n_und = 0;
            end
            vs_d <= vs_in;
        end
    end

    initial begin
        $display("整帧仿真启动：%0d 行/帧，SYNC_LAT=%0d", V_TOTAL, SYNC_LAT);
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3 * V_TOTAL * H_TOTAL) @(posedge clk);
        $display("超时退出（没抓到整帧统计）");
        $finish;
    end

endmodule
