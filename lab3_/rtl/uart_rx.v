// uart_rx.v —— 8N1 UART 接收（50MHz，1x 中点采样）
module uart_rx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD     = 115200
)(
    input  clk,
    input  rst_n,
    input  rxd,
    output reg [7:0] data,
    output reg       valid
);
    localparam DIV = CLK_FREQ / BAUD;
    localparam HALF = DIV / 2;

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg rxd_r0, rxd_r1;          // 2 级同步
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rxd_r0 <= 1'b1; rxd_r1 <= 1'b1; end
        else        begin rxd_r0 <= rxd;  rxd_r1 <= rxd_r0; end
    end

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [3:0]  bit_idx;
    reg [7:0]  shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; cnt <= 0; bit_idx <= 0; shift <= 0;
            data <= 0; valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)
                IDLE: begin
                    if (rxd_r1 == 1'b1 && rxd_r0 == 1'b0) begin
                        state <= START;
                        cnt <= HALF;               // 到起始位中点
                    end
                end
                START: begin
                    if (cnt == 0) begin
                        if (rxd_r1 == 1'b0) begin
                            state <= DATA; cnt <= DIV - 1; bit_idx <= 0;
                        end else begin
                            state <= IDLE;         // 毛刺
                        end
                    end else cnt <= cnt - 1;
                end
                DATA: begin
                    if (cnt == 0) begin
                        shift[bit_idx] <= rxd_r1;  // LSB first
                        if (bit_idx == 4'd7) begin
                            state <= STOP; cnt <= DIV - 1;
                        end else begin
                            bit_idx <= bit_idx + 1; cnt <= DIV - 1;
                        end
                    end else cnt <= cnt - 1;
                end
                STOP: begin
                    if (cnt == 0) begin
                        if (rxd_r1 == 1'b1) begin
                            data  <= shift;
                            valid <= 1'b1;
                        end
                        state <= IDLE;
                    end else cnt <= cnt - 1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
