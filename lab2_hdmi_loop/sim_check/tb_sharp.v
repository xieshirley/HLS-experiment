`timescale 1ns / 1ps
//=============================================================================
// tb_sharp.v —— 验证锐化通路（模式3）
//   校验点：
//     1) 每个 sharp 像素 == clamp(2*gray_pair ? gauss)，其中 gray_pair 是
//        tb 里"gauss 出一个就弹一个"的灰度队列，与 DUT 的配对规则一致
//     2) sharp 比 gauss 晚 3 拍（FIFO同步读1 + 算术1 + 限幅1），且 valid 与数据同拍
//     3) 三路计数一致：灰度 = 高斯 = 锐化（像素数）
//   图案（PATTERN 可选）：
//     0 = 逐像素斜坡（每个像素值都不同 → 配对若错位，等式必不成立）
//     1 = 台阶（看边缘是否被锐化）
//     2 = 竖条纹棋盘格（最高频）
//=============================================================================
module tb_sharp;

    localparam integer PATTERN  = 0;      // 0=斜坡 1=台阶 2=棋盘格

    localparam integer H_ACTIVE = 1920;   // 必须 1920：高斯核行长写死
    localparam integer H_BLANK  = 280;
    localparam integer V_ACTIVE = 6;
    localparam integer V_BLANK  = 4;
    localparam integer H_TOTAL  = H_ACTIVE + H_BLANK;
    localparam integer V_TOTAL  = V_ACTIVE + V_BLANK;

    reg clk = 0;
    always #3.3665 clk = ~clk;            // 148.5MHz
    reg rst_n = 0;

    //-------------------------------------------------------------
    // 激励
    //-------------------------------------------------------------
    reg  [23:0] rgb_in;
    reg         de_in, hs_in, vs_in;
    integer     hcnt = 0, vcnt = 0;

    wire [7:0] pat = (PATTERN == 0) ? (hcnt[7:0]) :
                     (PATTERN == 1) ? ((hcnt < H_ACTIVE/2) ? 8'd0 : 8'd255) :
                                      ((hcnt[0]) ? 8'd255 : 8'd0);

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
            // 用 B 通道给图案（灰度 = 25*B/256，逐像素不同）
            rgb_in <= ((hcnt < H_ACTIVE) && (vcnt < V_ACTIVE))
                      ? {8'h00, 8'h00, pat} : 24'h000000;
        end
    end

    //-------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------
    wire [7:0] gray_w, gauss_w, sharp_w;
    wire       gray_v, gauss_v, sharp_v, src_ready;

    video_core u_core (
        .clk          (clk),
        .rst_n        (rst_n),
        .rgb_in       (rgb_in),
        .de_in        (de_in),
        .src_ready    (src_ready),
        .gray_out     (gray_w),
        .gray_valid   (gray_v),
        .gauss_out    (gauss_w),
        .gauss_valid  (gauss_v),
        .gauss_ready  (1'b1),
        .sharp_out    (sharp_w),
        .sharp_valid  (sharp_v)
    );

    //-------------------------------------------------------------
    // 参考模型：灰度队列 + 3 级期望值流水
    //-------------------------------------------------------------
    localparam integer QW = 13;                    // 8192 深
    reg  [7:0]  qmem [0:(1<<QW)-1];
    reg  [QW:0] qwp, qrp;

    wire q_we = gray_v;
    wire q_rd = gauss_v && (qwp != qrp);
    wire [7:0] gray_pop = qmem[qrp[QW-1:0]];

    always @(posedge clk) begin
        if (!rst_n) begin
            qwp <= 0;
            qrp <= 0;
        end else begin
            if (q_we) begin
                qmem[qwp[QW-1:0]] <= gray_w;
                qwp <= qwp + 1'b1;
            end
            if (q_rd) qrp <= qrp + 1'b1;
        end
    end

    integer    t_sum;
    reg [7:0]  exp_q0, exp_q1, exp_q2;
    reg        exp_v0, exp_v1, exp_v2;

    always @(posedge clk) begin
        if (!rst_n) begin
            exp_q0 <= 8'd0; exp_q1 <= 8'd0; exp_q2 <= 8'd0;
            exp_v0 <= 1'b0; exp_v1 <= 1'b0; exp_v2 <= 1'b0;
        end else begin
            // 第 0 级：gauss 出一个像素的那一拍，算出期望的 clamp(2*gray ? smooth)
            exp_v0 <= q_rd;
            if (q_rd) begin
                t_sum = 2 * gray_pop - gauss_w;
                exp_q0 <= (t_sum < 0) ? 8'd0 : (t_sum > 255) ? 8'd255 : t_sum[7:0];
            end
            // 第 1/2 级：与 DUT 的两级流水同步移位
            exp_v1 <= exp_v0; exp_q1 <= exp_q0;
            exp_v2 <= exp_v1; exp_q2 <= exp_q1;
        end
    end

    //-------------------------------------------------------------
    // 统计与检查
    //-------------------------------------------------------------
    integer n_gray = 0, n_gauss = 0, n_sharp = 0, n_pair = 0, n_chk = 0, err = 0;
    integer t_first_gauss = -1, t_first_sharp = -1;
    integer cyc = 0;

    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (rst_n) begin
            if (gray_v)  n_gray  = n_gray  + 1;
            if (gauss_v) begin
                n_gauss = n_gauss + 1;
                if (t_first_gauss < 0) t_first_gauss = cyc;
            end
            if (q_rd) n_pair = n_pair + 1;
            if (sharp_v) begin
                n_sharp = n_sharp + 1;
                if (t_first_sharp < 0) t_first_sharp = cyc;
                n_chk = n_chk + 1;
                if (!exp_v2 || (sharp_w !== exp_q2)) begin
                    err = err + 1;
                    if (err <= 6)
                        $display("[%0t] ERR sharp=%0d 期望=%0d (exp_v=%b)",
                                 $time, sharp_w, exp_q2, exp_v2);
                end
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2 * V_TOTAL * H_TOTAL) @(posedge clk);

        $display("");
        $display("============== 锐化通路检查（PATTERN=%0d）==============", PATTERN);
        $display(" 灰度像素 = %0d", n_gray);
        $display(" 高斯像素 = %0d", n_gauss);
        $display(" 配对次数 = %0d", n_pair);
        $display(" 锐化像素 = %0d（校验 %0d 个）", n_sharp, n_chk);
        $display(" 首像素：gauss@%0d  sharp@%0d  → 锐化比高斯晚 %0d 拍",
                 t_first_gauss, t_first_sharp, t_first_sharp - t_first_gauss);
        $display(" 对齐 FIFO 峰值占用 = %0d / 4096", u_core.p_max);
        $display(" 16 深 FIFO 峰值占用 = %0d / 16", u_core.max_occ);
        // 注意：仿真在任意时刻停下时，灰度流总比高斯流多约"一条流水滞后"的像素
        // （n_gray - n_gauss ≈ FIFO 占用 ≈ 1924），所以判据不能要求两者相等
        if ((n_gauss == n_sharp) && (err == 0) && (u_core.p_max < 4096)
            && ((n_gray - n_gauss) < 4096)
            && ((t_first_sharp - t_first_gauss) == 3))
            $display(" >>> PASS：sharp == clamp(2*gray-smooth)，条目数与延迟(3拍)全部正确");
        else
            $display(" >>> FAIL：err=%0d  gray=%0d gauss=%0d sharp=%0d 延迟=%0d",
                     err, n_gray, n_gauss, n_sharp, t_first_sharp - t_first_gauss);
        $display("======================================================");
        $finish;
    end

endmodule
