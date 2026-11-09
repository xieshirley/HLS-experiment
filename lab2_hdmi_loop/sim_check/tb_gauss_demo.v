`timescale 1ns / 1ps
// tb_gauss_demo.v —— 用真实 gauss3x3 IP 验证"平滑是否真的生效"
// 输入：竖条纹棋盘格 0,255,0,255,...（最高空间频率）
// 预期：3x3 高斯 (1/16 归一化) 会把交替条纹拉成局部均值 ≈ 127
module tb_gauss_demo;

    reg clk = 0;
    always #3.3665 clk = ~clk;      // 148.5MHz

    reg  rst_n = 0;

    reg  [7:0] src_d = 0;
    reg        src_v = 0;
    wire       src_r;
    wire [7:0] dst_d;
    wire       dst_v;
    reg        dst_r = 1;

    gauss3x3 u_dut (
        .ap_clk         (clk),
        .ap_rst_n       (rst_n),
        .src_V_V_TDATA  (src_d),
        .src_V_V_TVALID (src_v),
        .src_V_V_TREADY (src_r),
        .dst_V_V_TDATA  (dst_d),
        .dst_V_V_TVALID (dst_v),
        .dst_V_V_TREADY (dst_r)
    );

    // 输入：每行 1920 像素，竖条纹 0/255
    integer x = 0, rows = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            src_v <= 0; x <= 0; rows <= 0;
        end else begin
            src_v <= (rows < 6);
            src_d <= ((x % 2) == 0) ? 8'd0 : 8'd255;
            if (src_v && src_r) begin
                if (x == 1919) begin x <= 0; rows <= rows + 1; end
                else                x <= x + 1;
            end
        end
    end

    // 采集输出
    integer nout = 0, printed = 0, sum = 0, nsum = 0, vmin = 999, vmax = 0;
    always @(posedge clk) begin
        if (dst_v && dst_r) begin
            if (nout >= 4000 && nout < 4016 && !printed) begin
                if (nout == 4000) $display("输出连续 8 拍: ");
                $write("%0d ", dst_d);
                if (nout == 4015) begin $display(""); printed = 1; end
            end
            if (nout >= 4000 && nout < 8000 && ((nout % 1920) >= 100) && ((nout % 1920) < 1800)) begin
                sum = sum + dst_d; nsum = nsum + 1;
                if (dst_d < vmin) vmin = dst_d;
                if (dst_d > vmax) vmax = dst_d;
            end
            nout = nout + 1;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (120000) @(posedge clk);
        $display("=====================================================");
        $display(" 输入 : 0,255,0,255,... (竖条纹棋盘格，最高空间频率)");
        $display(" 行内(不含行首尾)采样 %0d 拍: 均值=%0d  最小=%0d  最大=%0d", nsum, (nsum>0)?(sum/nsum):0, vmin, vmax);
        if (nsum > 0 && vmin > 120 && vmax < 136)
            $display(" >>> 条纹被拉平到约 127 → 3x3 高斯确实在工作（高频被滤掉）");
        else
            $display(" >>> 输出未拉平（检查输入/系数）");
        $display("=====================================================");
        $finish;
    end

endmodule
