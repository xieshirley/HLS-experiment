`timescale 1ns / 1ps
//=============================================================================
// tb_offset.v —— 观察"高斯核 DE 与 HS/VS 的相位偏移"
//-----------------------------------------------------------------------------
// 用途：
//   1) 在波形里直接看：hs_in / de_in（输入）vs hs_out / de_out（送编码器）
//   2) Tcl 控制台会自动打印一张"偏移表"，一眼看出核真实延迟是多少拍
//
//  五组同步实例并联，同一次仿真就能对比：
//      u_l2    LAT=2       DE 跟核 TVALID   → 偏移应 ≈ 2203 拍（1 行 + 3 拍）
//      u_l1100 LAT=1100    DE 跟核 TVALID   → 偏移应 ≈ 1105 拍（半行）
//      （可选）LAT=2200 的相位偏移应 ≈ 5 拍，需要时自己加一组
//      u_l2205 LAT=2205    DE 跟核 TVALID   → 偏移应 ≈ 0 拍  ← 说明 2205 就是真实延迟
//      u_fifo  LAT=2205    USE_FIFO_OUT=1   → 偏移恒 0（DE 由定长延迟产生，交付版）
//
// 在 Vivado GUI 里跑：
//   Flow Navigator → Add Sources → Add or create simulation sources → 选本文件
//   → 右键本文件 Set as Top（在 sim_1 下）→ Run Simulation → Run Behavioral Simulation
//   控制台会在最后打印汇总；波形里建议加：hs_in/vs_in/de_in、hs_out/de_out（各组）
//=============================================================================
module tb_offset;

    // ===== 视频时序（H_ACTIVE 必须是 1920：高斯核的行长写死 1920）=====
    localparam integer H_ACTIVE = 1920;
    localparam integer H_BLANK  = 280;
    localparam integer V_ACTIVE = 6;
    localparam integer V_BLANK  = 4;
    localparam integer H_TOTAL  = H_ACTIVE + H_BLANK;
    localparam integer V_TOTAL  = V_ACTIVE + V_BLANK;

    reg clk = 0;
    always #3.3665 clk = ~clk;            // 148.5MHz
    reg rst_n = 0;

    //-------------------------------------------------------------
    // 激励：时序 + 可辨认的渐变像素
    //-------------------------------------------------------------
    reg [23:0] rgb_in;
    reg        de_in, hs_in, vs_in;
    integer    hcnt = 0, vcnt = 0;

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
                      ? {hcnt[7:0], hcnt[15:8], 8'h40} : 24'h000000;
        end
    end

    //-------------------------------------------------------------
    // 被测链：灰度核 → 高斯核 → 同步
    //-------------------------------------------------------------
    wire [7:0]  gray_w, smooth_w, sh_w;
    wire        gray_v, smooth_v, src_ready, sh_v;

    video_core u_core (
        .clk(clk), .rst_n(rst_n),
        .rgb_in(rgb_in), .de_in(de_in), .src_ready(src_ready),
        .gray_out(gray_w), .gray_valid(gray_v),
        .gauss_out(smooth_w), .gauss_valid(smooth_v),
        .gauss_ready(1'b1),
        .sharp_out(sh_w), .sharp_valid(sh_v)
    );

    wire [23:0] rgb_l2, rgb_l1100, rgb_l2205, rgb_fifo;
    wire de_l2, hs_l2, vs_l2;
    wire de_l1100, hs_l1100, vs_l1100;
    wire de_l2205, hs_l2205, vs_l2205;
    wire de_fifo, hs_fifo, vs_fifo;

    video_sync #(.LATENCY(2),    .USE_FIFO_OUT(0)) u_l2 (
        .clk(clk), .rst_n(rst_n),
        .gray_in(smooth_w), .gray_valid(smooth_v), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_l2), .de_out(de_l2), .hs_out(hs_l2), .vs_out(vs_l2));

    video_sync #(.LATENCY(1100), .USE_FIFO_OUT(0)) u_l1100 (
        .clk(clk), .rst_n(rst_n),
        .gray_in(smooth_w), .gray_valid(smooth_v), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_l1100), .de_out(de_l1100), .hs_out(hs_l1100), .vs_out(vs_l1100));


    video_sync #(.LATENCY(2205), .USE_FIFO_OUT(0)) u_l2205 (
        .clk(clk), .rst_n(rst_n),
        .gray_in(smooth_w), .gray_valid(smooth_v), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_l2205), .de_out(de_l2205), .hs_out(hs_l2205), .vs_out(vs_l2205));

    video_sync #(.LATENCY(2205), .USE_FIFO_OUT(1)) u_fifo (
        .clk(clk), .rst_n(rst_n),
        .gray_in(smooth_w), .gray_valid(smooth_v), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_fifo), .de_out(de_fifo), .hs_out(hs_fifo), .vs_out(vs_fifo));
    // ---- 新增：用实测延迟值各接一路，验证"偏移≈0" ----
    wire [23:0] rgb_2215, rgb_2218;
    wire de_2215, hs_2215, vs_2215;
    wire de_2218, hs_2218, vs_2218;

    video_sync #(.LATENCY(2215), .USE_FIFO_OUT(1)) u_s2215 (      // gauss: 2211 实测 + 4 余量
        .clk(clk), .rst_n(rst_n),
        .gray_in(smooth_w), .gray_valid(smooth_v), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_2215), .de_out(de_2215), .hs_out(hs_2215), .vs_out(vs_2215));

    video_sync #(.LATENCY(2218), .USE_FIFO_OUT(1)) u_s2218 (      // sharp: 2214 实测 + 4 余量
        .clk(clk), .rst_n(rst_n),
        .gray_in(sh_w), .gray_valid(sh_v), .de_in(de_in),
        .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_2218), .de_out(de_2218), .hs_out(hs_2218), .vs_out(vs_2218));

    //-------------------------------------------------------------
    // 相位测量：hs 上升沿清零，DE 上升沿锁存 → "hs 到 DE 的拍数"
    //-------------------------------------------------------------
    wire [15:0] ph_in;
    wire [15:0] ph_l2, ph_l1100, ph_l2205, ph_fifo, ph_2215, ph_2218;

    phase_meas m_in   (.clk(clk), .hs(hs_in),   .de(de_in),   .phase(ph_in));
    phase_meas m_l2   (.clk(clk), .hs(hs_l2),   .de(de_l2),   .phase(ph_l2));
    phase_meas m_l1100(.clk(clk), .hs(hs_l1100),.de(de_l1100),.phase(ph_l1100));
    phase_meas m_l2205(.clk(clk), .hs(hs_l2205),.de(de_l2205),.phase(ph_l2205));
    phase_meas m_fifo (.clk(clk), .hs(hs_fifo), .de(de_fifo), .phase(ph_fifo));
    phase_meas m_2215 (.clk(clk), .hs(hs_2215), .de(de_2215), .phase(ph_2215));
    phase_meas m_2218 (.clk(clk), .hs(hs_2218), .de(de_2218), .phase(ph_2218));

    // 在途像素数（= 核的整条流水延迟，单位：拍，因为吞吐 1 像素/拍）
    integer cnt_in = 0, cnt_out = 0;
    reg de_in_d = 0, smooth_v_d = 0;
    always @(posedge clk) if (rst_n) begin
        de_in_d    <= de_in;
        smooth_v_d <= smooth_v;
        if (de_in)    cnt_in  <= cnt_in  + 1;   // 输入像素数（1 像素/拍）
        if (smooth_v) cnt_out <= cnt_out + 1;   // 核输出像素数
    end

    //-------------------------------------------------------------
    // 打印 + 结束
    //-------------------------------------------------------------
    integer ph_in_ref = 0;

    task show_row(input [8*16-1:0] name, input [15:0] ph);
        integer d;
        begin
            d = ph - ph_in_ref;
            $display("  %0s | 相位=%0d 拍 | 偏移=%0d 拍 = %0d 行 + %0d 像素",
                     name, ph, d, d / H_TOTAL, d % H_TOTAL);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;

        // 先跑满 3 帧，让相位测量稳定
        repeat (3 * V_TOTAL * H_TOTAL) @(posedge clk);

        ph_in_ref = ph_in;

        $display("");
        $display("================= 偏移测量结果 =================");
        $display(" 输入时序: 1 行 = %0d 拍 (%0d 有效 + %0d 消隐)", H_TOTAL, H_ACTIVE, H_BLANK);
        $display(" 基准: 输入 hs→de_in 相位 = %0d 拍（下面各组的相位都以各自的 hs 为基准）", ph_in);
        $display(" 在途像素 = %0d（= 核整条流水延迟，单位拍）", cnt_in - cnt_out);
        $display("------------------------------------------------");
        show_row("LAT=2    DE=TVALID", ph_l2);
        show_row("LAT=1100 DE=TVALID", ph_l1100);
        show_row("LAT=2205 DE=TVALID", ph_l2205);
        show_row("LAT=2205 PIXEL-FIFO", ph_fifo);
        show_row("gauss LAT2215", ph_2215);
        show_row("sharp LAT2218", ph_2218);
        $finish;
    end

endmodule

//=============================================================================
// phase_meas —— 测 "hs 上升沿 → de 上升沿" 的拍数
//=============================================================================
module phase_meas(
    input             clk,
    input             hs,
    input             de,
    output reg [15:0] phase
);
    reg        hs_d, de_d;
    reg [15:0] cnt;

    always @(posedge clk) begin
        hs_d <= hs;
        de_d <= de;
        if (hs && !hs_d) cnt <= 16'd0;
        else             cnt <= cnt + 16'd1;
        if (de && !de_d) phase <= cnt;
    end
endmodule
