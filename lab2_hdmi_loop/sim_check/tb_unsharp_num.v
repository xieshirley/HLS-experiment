`timescale 1ns / 1ps
//=============================================================================
// tb_unsharp_num.v —— 用"软边"图案验证 unsharp3x3 的数值行为
//   输入：B 通道 0 →（6 像素线性过渡）→ 255，再看几行
//   打印每一拍的 gray / gauss / sharp，检查 sharp 是否比 gray 更陡
//=============================================================================
module tb_unsharp_num;

    localparam integer H_ACTIVE = 1920;
    localparam integer H_BLANK  = 280;
    localparam integer V_ACTIVE = 6;
    localparam integer V_BLANK  = 4;
    localparam integer H_TOTAL  = H_ACTIVE + H_BLANK;
    localparam integer V_TOTAL  = V_ACTIVE + V_BLANK;

    reg clk = 0;
    always #3.3665 clk = ~clk;
    reg rst_n = 0;

    reg  [23:0] rgb_in;
    reg         de_in;
    integer     hcnt = 0, vcnt = 0;

    // 软边：x=300..305 线性 0→255，其余 0 或 255
    wire step = (hcnt < 300) ? 1'b0 : 1'b1;   // 满幅台阶边缘


    always @(posedge clk) begin
        if (!rst_n) begin
            hcnt <= 0; vcnt <= 0; de_in <= 0; rgb_in <= 0;
        end else begin
            if (hcnt == H_TOTAL-1) begin
                hcnt <= 0;
                if (vcnt == V_TOTAL-1) vcnt <= 0; else vcnt <= vcnt + 1;
            end else hcnt <= hcnt + 1;
            de_in  <= (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
            rgb_in <= ((hcnt < H_ACTIVE) && (vcnt < V_ACTIVE)) ? (step ? 24'hFFFFFF : 24'h000000) : 24'h0;
        end
    end

    wire [7:0] gray_w, gauss_w, sharp_w;
    wire       gray_v, gauss_v, sharp_v, src_ready;

    video_core u_core (
        .clk(clk), .rst_n(rst_n),
        .rgb_in(rgb_in), .de_in(de_in), .src_ready(src_ready),
        .gray_out(gray_w), .gray_valid(gray_v),
        .gauss_out(gauss_w), .gauss_valid(gauss_v), .gauss_ready(1'b1),
        .sharp_out(sharp_w), .sharp_valid(sharp_v), .sharp_ready(1'b1)
    );

    // 采样：抓第 3 行（2*1920..3*1920-1）每列的值，三路各一份，最后打印软边附近
    reg [7:0] ag [0:1919];
    reg [7:0] rg [0:1919];
    reg [7:0] sh [0:1919];
    integer n_gray = 0, n_gauss = 0, n_sharp = 0;
    integer i;

    always @(posedge clk) begin
        if (rst_n) begin
            if (gray_v) begin
                if ((n_gray >= 2*1920) && (n_gray < 3*1920)) ag[n_gray - 2*1920] = gray_w;
                n_gray = n_gray + 1;
            end
            if (gauss_v) begin
                if ((n_gauss >= 2*1920) && (n_gauss < 3*1920)) rg[n_gauss - 2*1920] = gauss_w;
                n_gauss = n_gauss + 1;
            end
            if (sharp_v) begin
                if ((n_sharp >= 2*1920) && (n_sharp < 3*1920)) sh[n_sharp - 2*1920] = sharp_w;
                n_sharp = n_sharp + 1;
            end
        end
    end
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (4 * V_TOTAL * H_TOTAL) @(posedge clk);
        $display("=== 总计 gray=%0d gauss=%0d sharp=%0d ===", n_gray, n_gauss, n_sharp);
        $display("  x  | gray | gauss | sharp   （软边在 x=300..305）");
        for (i = 296; i <= 310; i = i + 1)
            $display("  %0d |  %0d  |  %0d   |  %0d", i, ag[i], rg[i], sh[i]);
        $finish;
    end

endmodule
