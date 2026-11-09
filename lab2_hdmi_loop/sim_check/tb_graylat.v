`timescale 1ns / 1ps
// tb_graylat.v —— 规范 AXI-Stream 源 + 计数，测 rgb2gray 的输入→输出延迟
// 关键点：de_in=1 且 src_ready=0 时，rgb_in 保持不变（符合 AXIS 规范），
//         这样"送进去的像素数"与"出来的像素数"才能真正对得上。
module tb_graylat;

    localparam integer N_PIX = 12;      // 送几个像素

    reg clk = 0;
    always #3.3665 clk = ~clk;          // 148.5MHz
    reg rst_n = 0;

    reg  [23:0] rgb_in = 0;
    reg         de_in  = 0;
    wire        src_ready;
    wire [7:0]  gray_out;
    wire        gray_valid;
    wire        dst_ready = 1'b1;

    rgb2gray u_dut (
        .ap_clk          (clk),
        .ap_rst_n        (rst_n),
        .src_V_V_TDATA   (rgb_in),
        .src_V_V_TVALID  (de_in),
        .src_V_V_TREADY  (src_ready),
        .dst_V_V_TDATA   (gray_out),
        .dst_V_V_TVALID  (gray_valid),
        .dst_V_V_TREADY  (dst_ready)
    );

    //-------------------------------------------------------------
    // 规范 AXIS 源：只有"valid=0 或上一次握手成功"时才更新数据
    //-------------------------------------------------------------
    integer idx = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            de_in  <= 1'b0;
            rgb_in <= 24'd0;
            idx    <= 0;
        end else begin
            de_in <= (idx < N_PIX);
            if ((de_in == 1'b0) || (src_ready == 1'b1)) begin
                if (idx < N_PIX) begin
                    rgb_in <= {8'h00, 8'h00, (8'd64 + idx[7:0])};   // B=64..75
                    idx    <= idx + 1;
                end
            end
        end
    end

    //-------------------------------------------------------------
    // 统计
    //-------------------------------------------------------------
    integer c = 0;
    integer n_in = 0, n_out = 0;
    integer t_first_in = -1, t_last_in = -1, t_first_out = -1, t_last_out = -1;

    always @(posedge clk) begin
        c <= c + 1;
        if (rst_n) begin
            if (de_in && src_ready) begin
                n_in = n_in + 1;
                if (t_first_in < 0) t_first_in = c;
                t_last_in = c;
            end
            if (gray_valid && dst_ready) begin
                n_out = n_out + 1;
                if (t_first_out < 0) t_first_out = c;
                t_last_out = c;
                $display("  out#%0d  c=%0d  gray_out=%0d", n_out, c, gray_out);
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (40) @(posedge clk);
        $display("=================================================");
        $display(" 送进去(握手成功) = %0d 像素   首 %0d / 末 %0d", n_in,  t_first_in,  t_last_in);
        $display(" 出来(valid&ready) = %0d 像素   首 %0d / 末 %0d", n_out, t_first_out, t_last_out);
        $display(" 首像素延迟 = %0d 拍", t_first_out - t_first_in);
        $display(" 末像素延迟 = %0d 拍", t_last_out  - t_last_in);
        if ((t_first_out - t_first_in) == (t_last_out - t_last_in) && (n_in == n_out))
            $display(" >>> 延迟固定、进出拍数相等（规范 AXIS 源下成立）");
        else
            $display(" >>> 有不一致，需要再看");
        $display("=================================================");
        $finish;
    end

endmodule
