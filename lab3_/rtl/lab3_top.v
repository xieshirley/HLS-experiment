// lab3_top.v —— 实验三上板第一里程碑：UART 回环 + 数码管/LED 显示
// 收到 1 字节 -> 原样回传 + 数码管(最右位)显示低4位 + LED 显示低4位
module lab3_top (
    input  clk,
    input  rst_n,
    input  uart_rxd,
    output uart_txd,
    output [3:0] led,
    output [7:0] seg_led,
    output [5:0] seg_sel
);
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(.CLK_FREQ(50_000_000), .BAUD(115200)) u_rx (
        .clk(clk), .rst_n(rst_n), .rxd(uart_rxd),
        .data(rx_data), .valid(rx_valid)
    );

    reg [7:0] last;
    reg       tx_start;
    reg [7:0] tx_data;
    reg       send_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last <= 8'h00; tx_start <= 1'b0; tx_data <= 8'h00; send_d <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            send_d   <= 1'b0;
            if (rx_valid) begin
                last <= rx_data;
                tx_data <= rx_data;
                send_d <= 1'b1;              // 下一拍再发，确保 tx_data 已稳定
            end
            if (send_d) tx_start <= 1'b1;
        end
    end

    uart_tx #(.CLK_FREQ(50_000_000), .BAUD(115200)) u_tx (
        .clk(clk), .rst_n(rst_n), .start(tx_start), .tx_data(tx_data),
        .txd(uart_txd), .busy()
    );

    assign led = last[3:0];

    // 数码管最右位显示 0..9；非数字熄灭
    reg [3:0] digit;
    always @(*) begin
        if (last[3:0] <= 4'd9) digit = last[3:0];
        else                   digit = 4'hF;   // 熄灭
    end

    seg_display u_seg (
        .clk(clk), .rst_n(rst_n), .digit(digit),
        .seg_led(seg_led), .seg_sel(seg_sel)
    );
endmodule
