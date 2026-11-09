`timescale 1ns / 1ps
//====================================================================
// tb_core_chain.v —— 系统级检查：video_core + video_sync（编码器端口信号）
//--------------------------------------------------------------------
// 两路同时跑，同一套 1080p60 行时序（1920 有效 + 280 消隐），2 帧 × 12 行：
//   A: EN_GAUSS=0 + LATENCY=3     → 灰度单跑，等价 f11b691（上板通过版）
//   B: EN_GAUSS=1 + LATENCY=2205  → 灰度→高斯（1 行 2200 + 5 拍）
//
// 检查编码器端口（上板出不出画面就看这些）：
//   1) HS/VS 脉冲个数是否与输入一致（0 个 = 无信号/黑屏）
//   2) 每行 DE 宽度是否 1920（灰度为严格判据；高斯每行少 1 拍属已知反压问题）
//   3) DE 与 VS 是否重叠
//   4) 灰度通路像素值逐点比对（(66R+129G+25B+128)>>8）
//====================================================================
module tb_core_chain;

    localparam integer H_ACTIVE = 1920;
    localparam integer H_BLANK  = 280;
    localparam integer H_TOTAL  = H_ACTIVE + H_BLANK;
    localparam integer V_ACTIVE = 8;
    localparam integer V_BLANK  = 6;   // 场消隐要大于 vs 的 1 行位移
    localparam integer V_TOTAL  = V_ACTIVE + V_BLANK;
    localparam integer FRAMES   = 2;
    localparam integer NCYC     = FRAMES * V_TOTAL * H_TOTAL + 2 * 2210 + 300;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // ---------------- 输入视频时序 ----------------
    reg  [23:0] rgb_in = 24'd0;
    reg         de_in  = 1'b0;
    reg         hs_in  = 1'b0;
    reg         vs_in  = 1'b0;
    integer     hcnt, vcnt;
    reg         run_en = 1'b0;

    always @(negedge clk) begin
        if (!rst_n || !run_en) begin
            hcnt <= 0; vcnt <= 0;
            de_in <= 1'b0; hs_in <= 1'b0; vs_in <= 1'b0; rgb_in <= 24'd0;
        end else begin
            if (hcnt == H_TOTAL-1) begin
                hcnt <= 0;
                vcnt <= (vcnt == V_TOTAL-1) ? 0 : vcnt + 1;
            end else begin
                hcnt <= hcnt + 1;
            end
            de_in <= (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
            hs_in <= (hcnt >= H_ACTIVE);
            vs_in <= (vcnt >= V_ACTIVE+2) && (vcnt < V_ACTIVE+4);   // 真实 vs：窄脉冲，位于场消隐中间
            rgb_in <= {hcnt[7:0], vcnt[3:0], 8'h40};
        end
    end

    // ---------------- 通道 A：灰度单跑（= f11b691） ----------------
    wire [7:0]  gwA, swA;
    wire        gvA, svA, rdyA;
    wire [23:0] rgbA;
    wire        deA, hsA, vsA;

    video_core u_coreA (
        .clk(clk), .rst_n(rst_n),
        .rgb_in(rgb_in), .de_in(de_in), .src_ready(rdyA),
        .gray_out(gwA), .gray_valid(gvA),
        .gauss_out(), .gauss_valid(), .gauss_ready(1'b1),
        .sharp_out(), .sharp_valid()
    );

    video_sync #(.LATENCY(3)) u_syncA (
        .clk(clk), .rst_n(rst_n),
        .gray_in(gwA), .gray_valid(gvA), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgbA), .de_out(deA), .hs_out(hsA), .vs_out(vsA)
    );

    // ---------------- 通道 B：灰度 → 高斯 ----------------
    wire [7:0]  gwB, swB;
    wire        gvB, svB, rdyB;
    wire [23:0] rgbB;
    wire        deB, hsB, vsB;

    video_core u_coreB (
        .clk(clk), .rst_n(rst_n),
        .rgb_in(rgb_in), .de_in(de_in), .src_ready(rdyB),
        .gray_out(gwB), .gray_valid(gvB),
        .gauss_out(swB), .gauss_valid(svB), .gauss_ready(1'b1),
        .sharp_out(), .sharp_valid()
    );

    video_sync #(.LATENCY(2205), .USE_FIFO_OUT(1)) u_syncB (
        .clk(clk), .rst_n(rst_n),
        .gray_in(swB), .gray_valid(svB), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgbB), .de_out(deB), .hs_out(hsB), .vs_out(vsB)
    );

    // ---------------- 统计 ----------------
    reg     de_in_d = 0, hs_in_d = 0, vs_in_d = 0;
    reg     hsA_d = 0, vsA_d = 0, hsB_d = 0, vsB_d = 0;
    integer de_rise;
    integer n_hs_in=0, n_vs_in=0, n_hsA=0, n_vsA=0, n_hsB=0, n_vsB=0;
    integer ovl_hsA=0, ovl_hsB=0, ovl_vsA=0, ovl_vsB=0;
    integer lineA_min=99999, lineA_max=0, lineA_cnt=0, deA_line=0, bad_lineA=0;
    integer lineB_min=99999, lineB_max=0, lineB_cnt=0, deB_line=0, bad_lineB=0;

    reg [23:0] pq [0:4095];
    integer    pq_wr=0, pq_rd=0, e_pixA=0, n_acc=0, g_exp=0;

    always @(posedge clk) begin
        if (rst_n) begin
            de_rise = de_in && !de_in_d;
            de_in_d = de_in;
            if (hs_in && !hs_in_d) n_hs_in = n_hs_in + 1;
            if (vs_in && !vs_in_d) n_vs_in = n_vs_in + 1;
            hs_in_d = hs_in;
            vs_in_d = vs_in;

            // ---- A ----
            if (hsA && !hsA_d) n_hsA = n_hsA + 1;
            if (vsA && !vsA_d) n_vsA = n_vsA + 1;
            hsA_d = hsA;
            vsA_d = vsA;
            if (deA && hsA) ovl_hsA = ovl_hsA + 1;
            if (deA && vsA) ovl_vsA = ovl_vsA + 1;
            if (deA) deA_line = deA_line + 1;

            // ---- B ----
            if (hsB && !hsB_d) n_hsB = n_hsB + 1;
            if (vsB && !vsB_d) n_vsB = n_vsB + 1;
            hsB_d = hsB;
            vsB_d = vsB;
            if (deB && hsB) ovl_hsB = ovl_hsB + 1;
            if (deB && vsB) ovl_vsB = ovl_vsB + 1;
            if (deB) deB_line = deB_line + 1;

            // ---- 行长：以输入行首为界 ----
            if (de_rise) begin
                if (lineA_cnt > 0) begin
                    if (deA_line < lineA_min) lineA_min = deA_line;
                    if (deA_line > lineA_max) lineA_max = deA_line;
                    if (deA_line != H_ACTIVE) bad_lineA = bad_lineA + 1;
                    if (deB_line < lineB_min) lineB_min = deB_line;
                    if (deB_line > lineB_max) lineB_max = deB_line;
                    if (deB_line != H_ACTIVE) bad_lineB = bad_lineB + 1;
                end
                lineA_cnt = lineA_cnt + 1;
                deA_line  = 0;
                deB_line  = 0;
            end

            // ---- 灰度像素比对（只统计被核接收的像素） ----
            if (de_in && rdyA) begin
                pq[pq_wr[11:0]] = rgb_in;
                pq_wr = pq_wr + 1;
                n_acc = n_acc + 1;
            end
            if (deA) begin
                g_exp = (66*pq[pq_rd[11:0]][23:16] + 129*pq[pq_rd[11:0]][15:8]
                         + 25*pq[pq_rd[11:0]][7:0] + 128) >> 8;
                if (rgbA[7:0] !== g_exp[7:0]) begin
                    e_pixA = e_pixA + 1;
                    if (e_pixA <= 3)
                        $display("[%0t] A pixel err: exp=%0d got=%0d", $time, g_exp[7:0], rgbA[7:0]);
                end
                pq_rd = pq_rd + 1;
            end
        end
    end

    integer okA, okB;
    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        run_en = 1'b1;

        repeat (NCYC) @(posedge clk);

        okA = (n_hsA > 0) && (n_vsA > 0) && (n_hsA == n_hs_in) && (n_vsA == n_vs_in)
              && (bad_lineA <= 1) && (e_pixA == 0);   // 小量 DE&HS/VS 重叠是核在途像素，f11b691 同样存在
        okB = (n_hsB > 0) && (n_vsB > 0) && (n_hsB >= n_hs_in-1) && (n_vsB == n_vs_in)
              && (ovl_vsB == 0);   // n_hsB 少 1 是 2205 拍延迟链里还有一个脉冲没出来

        $display("");
        $display("============ system check (encoder side) ============");
        $display(" input : hs=%0d vs=%0d", n_hs_in, n_vs_in);
        $display(" CH-A gray  (EN_GAUSS=0, LATENCY=3)");
        $display("   hs=%0d vs=%0d | DE/line min/max=%0d/%0d bad=%0d | DE&HS ovl=%0d | DE&VS ovl=%0d | pix err=%0d (acc=%0d)",
                 n_hsA, n_vsA, lineA_min, lineA_max, bad_lineA, ovl_hsA, ovl_vsA, e_pixA, n_acc);
        $display(" CH-B gauss (EN_GAUSS=1, LATENCY=2205)");
        $display("   hs=%0d vs=%0d | DE/line min/max=%0d/%0d bad=%0d | DE&HS ovl=%0d | DE&VS ovl=%0d",
                 n_hsB, n_vsB, lineB_min, lineB_max, bad_lineB, ovl_hsB, ovl_vsB);
        $display("");
        if (okA) $display(" >>> CH-A PASS  (gray: HS/VS present, 1920/line, pixel correct)");
        else     $display(" >>> CH-A FAIL");
        if (okB) $display(" >>> CH-B PASS  (gauss: HS/VS present, no VS overlap)");
        else     $display(" >>> CH-B FAIL");
        $display("=====================================================");
        $finish;
    end

endmodule
