`timescale 1ns / 1ps
//=============================================================================
// tb_xcheck.v —— 检查"上电初期输出是否还有 X（波形红色）"
//
// 背景：
//   仿真时若出现 X，通常是两个原因：
//     1) 我们自己的 RTL：video_sync 的 SRL 移位链(sr) / 像素 FIFO(mem)、
//        video_core 的两个 16 深弹性 FIFO 没有上电初值 -> 前几十拍到前两行都是 X
//     2) HLS 核的行缓存 BRAM 有"上电初始化"(*_ram.dat)，若 .dat 不在仿真目录里，
//        VCS/xsim 读不到初值 -> 高斯/拉普拉斯核的前两行输出是 X
//
//   本 tb 统计三路输出的 X 拍数：
//       gauss_w / sharp_w（核输出） 与 rgb_out（video_sync FIFO 读出）
//   判据：全部为 0 才算 PASS（允许"没有数据"时输出 0，但不允许 X）
//
//   跑之前确认 .dat 已拷到当前目录：
//       copy ..\..\vivado_prj\hdmi_loop\hdmi_loop.srcs\sources_1\imports\hls\gauss3x3\*.dat .
//       copy ..\..\vivado_prj\hdmi_loop\hdmi_loop.srcs\sources_1\imports\hls\unsharp3x3\*.dat .
//=============================================================================
module tb_xcheck;

    localparam integer H_ACTIVE = 1920;
    localparam integer H_BLANK  = 280;
    localparam integer V_ACTIVE = 6;
    localparam integer V_BLANK  = 4;
    localparam integer H_TOTAL  = H_ACTIVE + H_BLANK;
    localparam integer V_TOTAL  = V_ACTIVE + V_BLANK;
    localparam integer SYNC_LAT = 2211;

    reg clk = 0;
    always #3.3665 clk = ~clk;
    reg rst_n = 0;

    reg  [23:0] rgb_in;
    reg         de_in, hs_in, vs_in;
    integer     hcnt = 0, vcnt = 0;

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
            rgb_in <= ((hcnt < H_ACTIVE) && (vcnt < V_ACTIVE))
                      ? {hcnt[7:0], hcnt[7:0], hcnt[7:0]} : 24'h0;
        end
    end

    //-------------------------------------------------------------
    // DUT：处理核 + 一路 FIFO 模式的同步（模拟高斯档）
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

    wire [23:0] rgb_out;
    wire        de_out, hs_out, vs_out, und_evt, ovf_evt;

    video_sync #(.LATENCY(SYNC_LAT), .USE_FIFO_OUT(1)) u_sync (
        .clk(clk), .rst_n(rst_n),
        .gray_in(gauss_w), .gray_valid(gauss_v), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out),
        .und_evt(und_evt), .ovf_evt(ovf_evt)
    );

    //-------------------------------------------------------------
    // X 统计（用 !== 做四值比较，X/Z 都能抓到）
    //-------------------------------------------------------------
    integer x_gauss = 0, x_sharp = 0, x_rgb = 0, x_sync = 0;
    integer n_gauss = 0, n_sharp = 0, n_rgb = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            // 核输出
            if (gauss_v) begin
                n_gauss = n_gauss + 1;
                if (^{gauss_w} === 1'bx) x_gauss = x_gauss + 1;
            end
            if (sharp_v) begin
                n_sharp = n_sharp + 1;
                if (^{sharp_w} === 1'bx) x_sharp = x_sharp + 1;
            end
            // 同步输出（DE 有效时才有意义）
            if (de_out) begin
                n_rgb = n_rgb + 1;
                if (^rgb_out === 1'bx) x_rgb = x_rgb + 1;
                if (^{de_out, hs_out, vs_out} === 1'bx) x_sync = x_sync + 1;
            end
        end
    end

    initial begin
        $display("=== tb_xcheck: 检查上电/前几行是否有 X ===");
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3 * V_TOTAL * H_TOTAL) @(posedge clk);

        $display("---------------------------------------------------");
        $display(" gauss 输出: %0d 拍，其中 X = %0d", n_gauss, x_gauss);
        $display(" sharp 输出: %0d 拍，其中 X = %0d", n_sharp, x_sharp);
        $display(" rgb_out   : %0d 拍，其中 X = %0d", n_rgb,   x_rgb);
        $display(" de/hs/vs  : 其中 X = %0d", x_sync);
        if (x_gauss == 0 && x_sharp == 0 && x_rgb == 0 && x_sync == 0)
            $display(" >>> PASS: 没有任何 X（前两行不再是红色）");
        else
            $display(" >>> FAIL: 仍有 X —— 检查 *.dat 是否在当前目录");
        $finish;
    end

endmodule
