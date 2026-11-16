`timescale 1ns / 1ps
//=============================================================================
// tb_de_measure.v —— 量出三路（灰度/高斯/锐化）的 DE 宽度与相位
//
// 目的：灰度档（USE_FIFO_OUT=0，DE = 核 TVALID）上板显示“彩条”（接收端不认），
//       而高斯/锐化档（DE = 输入 DE 定长延迟 + 像素 FIFO）正常。
//       这里逐行统计：
//         * 每行 DE 的拍数（标准应为 1920）
//         * 每行 DE 的上升沿位置相对 HS 上升沿的偏移
//         * DE 期间像素 R/G/B 是否相等（灰度档应为等值）
//=============================================================================
module tb_de_measure;

    localparam integer H_ACTIVE = 1920;
    localparam integer H_BLANK  = 280;
    localparam integer V_ACTIVE = 6;
    localparam integer V_BLANK  = 4;
    localparam integer H_TOTAL  = H_ACTIVE + H_BLANK;
    localparam integer V_TOTAL  = V_ACTIVE + V_BLANK;

    localparam integer LAT_GRAY  = 3;
    localparam integer LAT_GAUSS = 2211;
    localparam integer LAT_SHARP = 2213;

    reg clk = 0;
    always #3.3665 clk = ~clk;
    reg rst_n = 0;

    reg  [23:0] rgb_in;
    reg         de_in, hs_in, vs_in;
    integer     hcnt = 0, vcnt = 0;

    // 激励：与真实 1080p 一致的 DE 宽度 1920、行 2200
    always @(posedge clk) begin
        if (!rst_n) begin
            hcnt <= 0; vcnt <= 0; de_in <= 0; hs_in <= 0; vs_in <= 0; rgb_in <= 0;
        end else begin
            if (hcnt == H_TOTAL-1) begin
                hcnt <= 0;
                if (vcnt == V_TOTAL-1) vcnt <= 0; else vcnt <= vcnt + 1;
            end else hcnt <= hcnt + 1;
            de_in  <= (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
            hs_in  <= (hcnt == H_ACTIVE + 2);
            vs_in  <= (vcnt == V_ACTIVE + 2);
            // 输入：R 通道斜坡 + G/B 跟随，便于判断灰度通路是否变成等值
            rgb_in <= ((hcnt < H_ACTIVE) && (vcnt < V_ACTIVE))
                      ? {hcnt[7:0], hcnt[7:0], hcnt[7:0]} : 24'h0;
        end
    end

    //-------------------------------------------------------------
    // DUT：核 + 三路同步（与 hdmi_loop.v 里的接法完全一致）
    //-------------------------------------------------------------
    wire [7:0] gray_w, gauss_w, sharp_w;
    wire       gray_v, gauss_v, sharp_v, src_ready;

    video_core u_core (
        .clk(clk), .rst_n(rst_n),
        .rgb_in(rgb_in), .de_in(de_in), .src_ready(src_ready),
        .gray_out(gray_w), .gray_valid(gray_v),
        .gauss_out(gauss_w), .gauss_valid(gauss_v), .gauss_ready(1'b1),
        .sharp_out(sharp_w), .sharp_valid(sharp_v), .sharp_ready(1'b1)
    );

    wire [23:0] rgb_gray, rgb_gauss, rgb_sharp;
    wire de_gray, hs_gray, vs_gray;
    wire de_gauss, hs_gauss, vs_gauss;
    wire de_sharp, hs_sharp, vs_sharp;
    wire ug, og, ua, oa, us, os;

    video_sync #(.LATENCY(LAT_GRAY),  .USE_FIFO_OUT(0)) u_gray (
        .clk(clk), .rst_n(rst_n), .gray_in(gray_w), .gray_valid(gray_v),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_gray), .de_out(de_gray), .hs_out(hs_gray), .vs_out(vs_gray),
        .und_evt(ug), .ovf_evt(og));

    video_sync #(.LATENCY(LAT_GAUSS), .USE_FIFO_OUT(1)) u_gauss (
        .clk(clk), .rst_n(rst_n), .gray_in(gauss_w), .gray_valid(gauss_v),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_gauss), .de_out(de_gauss), .hs_out(hs_gauss), .vs_out(vs_gauss),
        .und_evt(ua), .ovf_evt(oa));

    video_sync #(.LATENCY(LAT_SHARP), .USE_FIFO_OUT(1)) u_sharp (
        .clk(clk), .rst_n(rst_n), .gray_in(sharp_w), .gray_valid(sharp_v),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_sharp), .de_out(de_sharp), .hs_out(hs_sharp), .vs_out(vs_sharp),
        .und_evt(us), .ovf_evt(os));

    //-------------------------------------------------------------
    // 统计：以各自的 HS 上升沿切行，量 DE 宽度和 DE 起点相位
    //-------------------------------------------------------------
    integer g_de_w = 0, a_de_w = 0, s_de_w = 0;      // 当前行 DE 宽度
    integer g_min = 9999, g_max = 0, a_min = 9999, a_max = 0, s_min = 9999, s_max = 0;
    integer g_ph = -1, a_ph = -1, s_ph = -1;         // DE 上升沿相对 HS 的相位
    integer g_ph_l = -1, a_ph_l = -1, s_ph_l = -1;
    integer ph_cnt = 0;
    integer rows = 0;
    integer g_rgb_bad = 0, a_rgb_bad = 0, s_rgb_bad = 0;

    reg g_hs_d = 0, a_hs_d = 0, s_hs_d = 0;
    reg g_de_d = 0, a_de_d = 0, s_de_d = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            // ---- 灰度路 ----
            if (de_gray) begin
                g_de_w = g_de_w + 1;
                if (rgb_gray[23:16] !== rgb_gray[15:8] || rgb_gray[15:8] !== rgb_gray[7:0])
                    g_rgb_bad = g_rgb_bad + 1;
            end
            if (de_gray && !g_de_d && g_ph < 0) g_ph = ph_cnt;
            if (hs_gray && !g_hs_d) begin
                if (g_de_w < g_min) g_min = g_de_w;
                if (g_de_w > g_max) g_max = g_de_w;
                if (g_de_w > 100) begin g_ph_l = g_ph; rows = rows + 1; end
                g_de_w = 0; g_ph = -1; ph_cnt = 0;
            end
            if (!hs_gray) ph_cnt = ph_cnt + 1;
            g_hs_d <= hs_gray; g_de_d <= de_gray;

            // ---- 高斯路 ----
            if (de_gauss) begin
                a_de_w = a_de_w + 1;
                if (rgb_gauss[23:16] !== rgb_gauss[15:8] || rgb_gauss[15:8] !== rgb_gauss[7:0])
                    a_rgb_bad = a_rgb_bad + 1;
            end
            if (de_gauss && !a_de_d && a_ph < 0) a_ph = ph_cnt;
            if (hs_gauss && !a_hs_d) begin
                if (a_de_w < a_min) a_min = a_de_w;
                if (a_de_w > a_max) a_max = a_de_w;
                a_ph_l = a_ph;
                a_de_w = 0; a_ph = -1;
            end
            a_hs_d <= hs_gauss; a_de_d <= de_gauss;

            // ---- 锐化路 ----
            if (de_sharp) begin
                s_de_w = s_de_w + 1;
                if (rgb_sharp[23:16] !== rgb_sharp[15:8] || rgb_sharp[15:8] !== rgb_sharp[7:0])
                    s_rgb_bad = s_rgb_bad + 1;
            end
            if (de_sharp && !s_de_d && s_ph < 0) s_ph = ph_cnt;
            if (hs_sharp && !s_hs_d) begin
                if (s_de_w < s_min) s_min = s_de_w;
                if (s_de_w > s_max) s_max = s_de_w;
                s_ph_l = s_ph;
                s_de_w = 0; s_ph = -1;
            end
            s_hs_d <= hs_sharp; s_de_d <= de_sharp;
        end
    end

    initial begin
        $display("=== DE measure: gray(LAT=3,FIFO=0) vs gauss(LAT=2211,FIFO=1) vs sharp(LAT=2213) ===");
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (4 * V_TOTAL * H_TOTAL) @(posedge clk);
        $display("---------------------------");
        $display(" PATH  | DE width min/max | DE phase vs HS | R!=G!=B beats | rows");
        $display(" gray  |   %0d / %0d        |   %0d            |   %0d           | %0d", g_min, g_max, g_ph_l, g_rgb_bad, rows);
        $display(" gauss |   %0d / %0d        |   %0d            |   %0d           | -",  a_min, a_max, a_ph_l, a_rgb_bad);
        $display(" sharp |   %0d / %0d        |   %0d            |   %0d           | -",  s_min, s_max, s_ph_l, s_rgb_bad);
        $display("---------------------------");
        if (g_min == 1920 && g_max == 1920) $display(" gray  DE 宽度正常 (1920)");
        else                                $display(" >>> gray  DE 宽度异常 <<<");
        $finish;
    end

endmodule
