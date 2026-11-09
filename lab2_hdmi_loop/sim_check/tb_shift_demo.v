`timescale 1ns / 1ps
//====================================================================
// tb_shift_demo.v  —— “同步只打 1 拍”错位复现（报告“错位复现-理论对照”）
//--------------------------------------------------------------------
// 目的：证明窗口核（延迟 D = 1 行 + 5 拍）若同步信号只打 1 拍
//       （HS/VS/DE 只延迟 1 拍），画面出现【固定 1 行 + 4 列】偏移，
//       与 1080p 实板一致（D=2205 → 错位 = D-1 = 2204 = 2200 + 4）。
//
// 缩小同构参数（比例与 1080p 完全一致，跑得快）：
//   1080p: H_TOTAL=2200, D=2205, 错位 = D-1 = 2204 = 2200 + 4 → 1 行 4 列
//   本 tb : H_TOTAL=40,   D=45,   错位 = D-1 = 44   = 40   + 4 → 1 行 4 列
//
// 两通道都按 video_sync(USE_FIFO_OUT=1) 的等价结构：
//   CHA: LATENCY = 1  ——“同步只打 1 拍”（错误配置）
//   CHB: LATENCY = 45 ——等延迟匹配（正确配置）
//
// 像素编码：pix = {row[2:0], col[4:0]}（row 0..6, col 0..31），
// 输出端解出“内容坐标”，与“同步给出的显示序号”相减 → Δ 行/Δ 列。
// pix_vld = FIFO 非空，用来区分“空读黑边”和真实像素。
//====================================================================
module tb_shift_demo;

    localparam integer H_ACTIVE = 32;
    localparam integer H_TOTAL  = 40;    // 行周期（含消隐）
    localparam integer V_ACTIVE = 7;
    localparam integer V_BLANK  = 3;
    localparam integer D_KERNEL = H_TOTAL + 5;    // 45 = 1 行 + 5 拍（核延迟）

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    //------------------------------------------------------------
    // 1. 假视频时序（1080p60 结构的缩小版）
    //------------------------------------------------------------
    reg  [7:0] pix_in = 8'd0;
    reg        de_in = 1'b0, hs_in = 1'b0, vs_in = 1'b0;
    integer    hcnt = 0, vcnt = 0;

    always @(negedge clk) begin
        if (!rst_n) begin
            hcnt <= 0; vcnt <= 0;
            de_in <= 1'b0; hs_in <= 1'b0; vs_in <= 1'b0; pix_in <= 8'd0;
        end else begin
            if (hcnt == H_TOTAL-1) begin
                hcnt <= 0;
                vcnt <= (vcnt == V_ACTIVE+V_BLANK-1) ? 0 : vcnt + 1;
            end else begin
                hcnt <= hcnt + 1;
            end
            de_in <= (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
            hs_in <= (hcnt >= H_ACTIVE);
            vs_in <= (vcnt >= V_ACTIVE);
            if ((hcnt < H_ACTIVE) && (vcnt < V_ACTIVE))
                pix_in <= {vcnt[2:0], hcnt[4:0]};    // {行 0..6, 列 0..31}
        end
    end

    //------------------------------------------------------------
    // 2. 核延迟模型：D 拍纯延迟（1 行 + 5 拍，valid 与像素同步延迟）
    //------------------------------------------------------------
    reg  [7:0] kp [0:D_KERNEL-1];
    reg        kv [0:D_KERNEL-1];
    integer    i;
    initial begin
        for (i = 0; i < D_KERNEL; i = i + 1) begin
            kp[i] = 8'd0;
            kv[i] = 1'b0;
        end
    end
    always @(posedge clk) begin
        if (rst_n) begin
            for (i = D_KERNEL-1; i > 0; i = i - 1) begin
                kp[i] <= kp[i-1];
                kv[i] <= kv[i-1];
            end
            kp[0] <= pix_in;
            kv[0] <= de_in;
        end
    end
    wire [7:0] kern_pix = kp[D_KERNEL-1];
    wire       kern_vld = kv[D_KERNEL-1];

    //------------------------------------------------------------
    // 3. 两种同步配置
    //------------------------------------------------------------
    wire [7:0] pix_a, pix_b;
    wire       pv_a, pv_b;
    wire       de_a, hs_a, vs_a, de_b, hs_b, vs_b;

    sync_fifo_model #(.LATENCY(1))        u_cha (
        .clk(clk), .rst_n(rst_n),
        .gray_in(kern_pix), .gray_valid(kern_vld),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .pix_out(pix_a), .pix_vld(pv_a),
        .de_out(de_a), .hs_out(hs_a), .vs_out(vs_a)
    );

    sync_fifo_model #(.LATENCY(D_KERNEL)) u_chb (
        .clk(clk), .rst_n(rst_n),
        .gray_in(kern_pix), .gray_valid(kern_vld),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .pix_out(pix_b), .pix_vld(pv_b),
        .de_out(de_b), .hs_out(hs_b), .vs_out(vs_b)
    );

    //------------------------------------------------------------
    // 4. 测量：显示序号 vs 内容坐标
    //------------------------------------------------------------
    shift_meter #(.LATENCY(1),        .TAG(0)) m_a (
        .clk(clk), .rst_n(rst_n),
        .de(de_a), .vs(vs_a), .pix(pix_a), .pix_vld(pv_a)
    );

    shift_meter #(.LATENCY(D_KERNEL), .TAG(1)) m_b (
        .clk(clk), .rst_n(rst_n),
        .de(de_b), .vs(vs_b), .pix(pix_b), .pix_vld(pv_b)
    );

    //------------------------------------------------------------
    // 5. 控制与打印
    //------------------------------------------------------------
    integer cyc;

    initial begin
        cyc = 0;
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // 跑 3 帧（1 帧 = (V_ACTIVE+V_BLANK)*H_TOTAL = 400 拍）
        repeat ((V_ACTIVE+V_BLANK)*H_TOTAL*3 + 100) @(posedge clk);

        $display("");
        $display("==================================================================");
        $display("  SHIFT DEMO : sync with only 1-cycle delay (compact, isomorphic)");
        $display("  H_ACTIVE=%0d H_TOTAL=%0d V_ACTIVE=%0d V_BLANK=%0d  D_kernel=%0d (=1 line + 5)",
                 H_ACTIVE, H_TOTAL, V_ACTIVE, V_BLANK, D_KERNEL);
        $display("------------------------------------------------------------------");
        m_a.report;
        $display("------------------------------------------------------------------");
        m_b.report;
        $display("==================================================================");
        $display("  Theory (pixel domain): offset = ACTIVE pixels inside the kernel-latency window");
        $display("    CHA: D=%0d taps -> %0d + %0d = %0d taps = 1 line + %0d col  (MATCHES sim)",
                 D_KERNEL, H_ACTIVE, D_KERNEL-H_TOTAL, H_ACTIVE+(D_KERNEL-H_TOTAL), D_KERNEL-H_TOTAL);
        $display("    CHB: sync = D  -> aligned; residual 1 tap = FIFO comb-read view (1 col)");
        $display("  1080p scaling: D=2205 -> 1920 + 5 = 1925 taps = 1 line + 5 col");
        $display("  => 'sync only 1 tap' produces a FIXED 1-line + 5-column shift on screen");
        $display("==================================================================");
        $finish;
    end

endmodule


//====================================================================
// sync_fifo_model —— 与 video_sync(USE_FIFO_OUT=1) 等价的同步+FIFO 模型
//   LATENCY : HS/VS/DE 精确延迟拍数（1 = “只打 1 拍”）
//   像素：核输出写入，按显示 DE 读出（组合读，写当拍不可见，故有 1 拍视图偏差）
//====================================================================
module sync_fifo_model #(
    parameter integer LATENCY = 45,
    parameter integer FW      = 9
)(
    input             clk,
    input             rst_n,
    input      [7:0]  gray_in,
    input             gray_valid,
    input             de_in,
    input             hs_in,
    input             vs_in,
    output     [7:0]  pix_out,
    output            pix_vld,
    output            de_out,
    output            hs_out,
    output            vs_out
);

    reg [3*LATENCY-1:0] sr;

    generate
        if (LATENCY == 1) begin : g_one
            always @(posedge clk)
                sr <= {de_in, hs_in, vs_in};
        end else begin : g_many
            always @(posedge clk)
                sr <= {sr[3*LATENCY-4:0], de_in, hs_in, vs_in};
        end
    endgenerate

    wire de_del = sr[3*LATENCY-1];
    wire hs_del = sr[3*LATENCY-2];
    wire vs_del = sr[3*LATENCY-3];

    reg  [7:0]  mem [0:(1<<FW)-1];
    reg  [FW:0] wp, rp;
    wire [FW:0] cnt  = wp - rp;
    wire        full = cnt[FW];
    wire        we   = gray_valid & ~full;
    wire        re   = de_del & (cnt != 0);

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

    assign pix_out = (cnt != 0) ? mem[rp[FW-1:0]] : 8'd0;
    assign pix_vld = (cnt != 0);
    assign de_out  = de_del;
    assign hs_out  = hs_del;
    assign vs_out  = vs_del;

endmodule


//====================================================================
// shift_meter —— 测量“显示序号”与“内容坐标”的差
//   so    : 本帧 DE 有效拍计数（显示序号，vs 期间复位）
//   coso  : 像素内容全局序号 = pix（0..V_ACTIVE*H_ACTIVE-1）
//   Δ     = (so - coso) mod FRAME_PIX  = 内容落后多少拍
//            → Δr = Δ/H_ACTIVE 行，Δc = Δ%H_ACTIVE 列
//   只在第 2 帧起统计（第 1 帧含 FIFO 建立期，不是稳态）
//====================================================================
module shift_meter #(
    parameter integer H_ACTIVE = 32,
    parameter integer V_ACTIVE = 7,
    parameter integer LATENCY  = 1,
    parameter integer TAG      = 0
)(
    input             clk,
    input             rst_n,
    input             de,
    input             vs,
    input      [7:0]  pix,
    input             pix_vld
);

    localparam integer FRAME_PIX = H_ACTIVE * V_ACTIVE;

    integer so;
    integer frm;
    integer n_null;
    integer n_samp;
    integer dsum;
    integer dmin, dmax, dlast;
    integer d, coso;
    reg     vs_d;

    initial begin
        so = 0; frm = 0; n_null = 0; n_samp = 0;
        dsum = 0; dmin = 999999; dmax = -99999; dlast = 0;
        vs_d = 1'b0;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            vs_d <= vs;
            if (vs) begin
                so <= 0;
            end else if (de) begin
                if (!pix_vld) begin
                    n_null <= n_null + 1;
                end else if (frm >= 1) begin
                    coso = pix;
                    d    = so - coso;
                    if (d < 0) d = d + FRAME_PIX;
                    dsum  <= dsum + d;
                    n_samp <= n_samp + 1;
                    if (d < dmin) dmin <= d;
                    if (d > dmax) dmax <= d;
                    dlast <= d;
                end
                so <= so + 1;
            end
            if (vs && !vs_d) frm <= frm + 1;
        end
    end

    task report;
        begin
            $display("  CH%0d  sync delay = %0d tap(s)", TAG, LATENCY);
            $display("        null reads (black border) = %0d", n_null);
            if (n_samp > 0) begin
                $display("        steady samples = %0d   offset(delta) min=%0d max=%0d last=%0d",
                         n_samp, dmin, dmax, dlast);
                if (dmin == dmax) begin
                    if (dmin == 0)
                        $display("        >>> RESULT: 0 tap offset (no misalignment)");
                    else
                        $display("        >>> RESULT: fixed offset = %0d taps = %0d line(s) + %0d col(s)  (MISALIGNED)",
                                 dmin, dmin / H_ACTIVE, dmin % H_ACTIVE);
                end else
                    $display("        >>> offset varies (frame boundary / setup phase)");
            end else
                $display("        no steady sample collected");
        end
    endtask

endmodule
