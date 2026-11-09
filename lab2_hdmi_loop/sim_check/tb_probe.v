`timescale 1ns / 1ps
// tb_probe.v —— 只探核：逐拍打印 de_in / src_ready / gray_valid / gray_in
module tb_probe;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;

    reg  [23:0] rgb_in;
    reg         de_in;
    wire [7:0]  gray_w;
    wire        gray_v;
    wire        src_ready_w;

    integer cyc = 0;
    integer i;
    reg [7:0] pv;

    video_core u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .rgb_in     (rgb_in),
        .de_in      (de_in),
        .src_ready  (src_ready_w),
        .gray_out   (gray_w),
        .gray_valid (gray_v),
        .gray_ready (1'b1)
    );

    // 每拍打印一行（negedge 采样：此时寄存器的值就是本拍稳定值）
    always @(negedge clk) begin
        cyc = cyc + 1;
        if (cyc <= 46) begin
            $display("cyc=%0d  de_in=%b ready=%b  gray_v=%b gray=%0d",
                     cyc, de_in, src_ready_w, gray_v, gray_w);
        end
    end

    initial begin
        rst_n  = 1'b0;
        de_in  = 1'b0;
        rgb_in = 24'd0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // 连续 16 拍有效像素，像素值 = 序号（在 negedge 变化，posedge 采样稳定）
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk);
            pv     = i;
            de_in  = 1'b1;
            rgb_in = {pv, pv, pv};
        end
        @(negedge clk);
        de_in  = 1'b0;
        rgb_in = 24'd0;
        repeat (12) @(posedge clk);
        $finish;
    end

endmodule
