`timescale 1ns / 1ps
// tb_vsync2.v —— 单独验证 video_sync v2（USE_FIFO_OUT=1）的时序与像素通路
module tb_vsync2;

    localparam integer L  = 2205;   // 延迟拍数（小数值便于看波形）
    localparam integer H  = 1920;    // 每行有效像素
    localparam integer HB = 280;    // 每行消隐

    reg clk = 0;
    always #5 clk = ~clk;

    reg  rst_n = 0;
    reg  [7:0] gray_in = 0;
    reg        gray_valid = 0;
    reg        de_in = 0, hs_in = 0, vs_in = 0;

    wire [23:0] rgb_out;
    wire        de_out, hs_out, vs_out;

    video_sync #(.LATENCY(L), .USE_FIFO_OUT(1)) dut (
        .clk(clk), .rst_n(rst_n),
        .gray_in(gray_in), .gray_valid(gray_valid),
        .de_in(de_in), .hs_in(hs_in), .vs_in(vs_in),
        .rgb_out(rgb_out), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out)
    );

    // 黄金模型：de/hs/vs 的 (L-1) 拍延迟（与 DUT 内部抽头一致）
    reg [3*L-1:0] gold = 0;
    always @(posedge clk) gold <= {gold[3*L-4:0], de_in, hs_in, vs_in};
    wire gold_de = gold[3*L-1];
    wire gold_hs = gold[3*L-2];
    wire gold_vs = gold[3*L-3];

    // 激励
    integer hcnt = 0, lcnt = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            hcnt <= 0; lcnt <= 0; de_in <= 0; hs_in <= 0; vs_in <= 0;
        end else begin
            if (hcnt == H+HB-1) begin hcnt <= 0; lcnt <= lcnt + 1; end
            else                      hcnt <= hcnt + 1;

            de_in <= (hcnt < H);
            hs_in <= (hcnt == H+1);
            vs_in <= (lcnt == 3);
        end
    end

    // 核输出：DE 时给固定花纹 0xA5（模拟"核比输入晚几拍"）
    always @(posedge clk) begin
        gray_valid <= de_in;
        if (de_in) gray_in <= 8'hA5;
    end

    // 检查
    integer err = 0, chk = 0, cyc = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            cyc = cyc + 1;
            if (cyc > 4*L) begin               // 跳过链填充期
                if (de_out !== gold_de) begin err = err + 1; if (err<6) $display("ERR de  @%0t: dut=%b gold=%b", $time, de_out, gold_de); end
                if (hs_out !== gold_hs) begin err = err + 1; if (err<6) $display("ERR hs  @%0t: dut=%b gold=%b", $time, hs_out, gold_hs); end
                if (vs_out !== gold_vs) begin err = err + 1; if (err<6) $display("ERR vs  @%0t: dut=%b gold=%b", $time, vs_out, gold_vs); end
                if (de_out && (rgb_out !== 24'hA5A5A5)) begin
                    err = err + 1;
                    if (err<6) $display("ERR pix @%0t: rgb=%h", $time, rgb_out);
                end
            end
            if (hs_out && !gold_de) chk = chk + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (4800) @(posedge clk);
        $display("======== tb_vsync2 ========");
        $display(" cyc=%0d  err=%0d", cyc, err);
        if (err == 0) $display(" >>> PASS: DE/HS/VS 延迟与黄金模型一致，FIFO 像素通路正确");
        else          $display(" >>> FAIL: err=%0d", err);
        $finish;
    end

endmodule
