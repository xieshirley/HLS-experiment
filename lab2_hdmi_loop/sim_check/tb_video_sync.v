`timescale 1ns / 1ps
//====================================================================
// tb_video_sync.v —— video_sync 自检（f11b691 写法 + LATENCY 参数）
//   CH0: LATENCY = 3     → 灰度核单跑（= f11b691 上板通过版）
//   CH1: LATENCY = 2205  → 灰度+高斯（1 行 2200 + 5 拍）
// 检查三件事（逐拍全比对）：
//   1) hs_out/vs_out == hs_in/vs_in 延迟 LATENCY 拍
//   2) de_out 同拍 == gray_valid
//   3) rgb_out 同拍 == {3{gray_in}}
// 参考延迟用整拍历史数组实现，与被测移位链完全不同源。
//====================================================================
module tb_video_sync;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    wire done_a, done_b;
    wire [31:0] err_a, err_b, cyc_a, cyc_b;

    ch_chk #(.LATENCY(3)) u_a (
        .clk(clk), .rst_n(rst_n), .err(err_a), .cyc(cyc_a), .done(done_a)
    );

    ch_chk #(.LATENCY(2205)) u_b (
        .clk(clk), .rst_n(rst_n), .err(err_b), .cyc(cyc_b), .done(done_b)
    );

    initial begin
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        wait (done_a && done_b);

        $display("");
        $display("=============== video_sync self-check ===============");
        $display(" CH0 LATENCY=3    : cyc=%0d err=%0d", cyc_a, err_a);
        $display(" CH1 LATENCY=2205 : cyc=%0d err=%0d", cyc_b, err_b);
        if ((err_a == 0) && (err_b == 0))
            $display(" >>> PASS: HS/VS delay / DE follow / pixel pass-through OK");
        else
            $display(" >>> FAIL");
        $display("=====================================================");
        $finish;
    end

endmodule


//====================================================================
// ch_chk.v —— 单通道：假视频时序 + video_sync + 逐拍比对
//====================================================================
module ch_chk #(
    parameter integer LATENCY  = 3,
    parameter integer H_ACTIVE = 1920,
    parameter integer H_TOTAL  = 2200,
    parameter integer V_ACTIVE = 4,
    parameter integer V_BLANK  = 2,
    parameter integer LINES    = 3,
    parameter integer TAG      = 0
)(
    input             clk,
    input             rst_n,
    output reg        done,
    output integer    err,
    output integer    cyc
);

    localparam integer NCYC = LINES * H_TOTAL + LATENCY + 50;

    // ---- 假视频时序（de/hs/vs） ----
    reg         de_in  = 1'b0;
    reg         hs_in  = 1'b0;
    reg         vs_in  = 1'b0;
    reg  [7:0]  pix    = 8'd0;
    reg         pix_v  = 1'b0;
    reg  [3:0]  vld_sr = 4'd0;
    integer     hcnt, vcnt, fcnt;

    always @(negedge clk) begin
        if (!rst_n) begin
            hcnt <= 0; vcnt <= 0;
            de_in <= 1'b0; hs_in <= 1'b0; vs_in <= 1'b0;
            pix <= 8'd0; pix_v <= 1'b0; vld_sr <= 4'd0;
        end else begin
            if (hcnt == H_TOTAL-1) begin
                hcnt <= 0;
                vcnt <= (vcnt == V_ACTIVE-1+V_BLANK-1) ? 0 : vcnt + 1;
            end else begin
                hcnt <= hcnt + 1;
            end
            de_in <= (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
            hs_in <= (hcnt >= H_ACTIVE);
            vs_in <= (vcnt >= V_ACTIVE);
            // 假核输出：valid 比 de 晚 2 拍（模拟核流水），像素值自增
            vld_sr <= {vld_sr[2:0], de_in};
            pix_v  <= vld_sr[3];
            if (vld_sr[3]) pix <= pix + 8'd3;
        end
    end

    // ---- DUT ----
    wire [23:0] rgb_out;
    wire        de_out, hs_out, vs_out;

    video_sync #(.LATENCY(LATENCY)) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .gray_in    (pix),
        .gray_valid (pix_v),
        .hs_in      (hs_in),
        .vs_in      (vs_in),
        .rgb_out    (rgb_out),
        .de_out     (de_out),
        .hs_out     (hs_out),
        .vs_out     (vs_out)
    );

    // ---- 逐拍比对 ----
    reg [1:0] hist [0:32767];
    integer   n, e_sync, e_de, e_pix, n_edges;
    reg       hs_out_d;

    always @(posedge clk) begin
        if (rst_n) begin
            hist[n] = {hs_in, vs_in};

            if (n >= LATENCY) begin
                if ({hs_out, vs_out} !== hist[n-LATENCY]) begin
                    e_sync = e_sync + 1;
                    if (e_sync <= 3)
                        $display("[CH%0d] HS/VS delay err at cyc=%0d exp=%b got=%b",
                                 TAG, n, hist[n-LATENCY], {hs_out, vs_out});
                end
            end
            if (de_out !== pix_v) begin
                e_de = e_de + 1;
                if (e_de <= 3) $display("[CH%0d] DE not same-cycle as valid", TAG);
            end
            if (rgb_out !== {3{pix}}) begin
                e_pix = e_pix + 1;
                if (e_pix <= 3) $display("[CH%0d] pixel pass-through err", TAG);
            end
            if (hs_out && !hs_out_d) n_edges = n_edges + 1;
            hs_out_d = hs_out;

            n = n + 1;
            if (n == NCYC) begin
                err  = e_sync + e_de + e_pix;
                cyc  = n;
                done = 1'b1;
                if (err != 0)
                    $display("[CH%0d] FAIL: sync=%0d de=%0d pix=%0d (hs edges=%0d)",
                             TAG, e_sync, e_de, e_pix, n_edges);
            end
        end
    end
    initial begin
        n = 0; e_sync = 0; e_de = 0; e_pix = 0; n_edges = 0;
        hs_out_d = 1'b0; done = 1'b0; err = 0; cyc = 0;
    end

endmodule
