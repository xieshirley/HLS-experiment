// uart_tx.v —— 8N1 UART 发送
module uart_tx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD     = 115200
)(
    input  clk,
    input  rst_n,
    input  start,
    input  [7:0] tx_data,
    output reg txd,
    output reg busy
);
    localparam DIV = CLK_FREQ / BAUD;
    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [3:0]  bit_idx;
    reg [7:0]  shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; cnt <= 0; bit_idx <= 0; shift <= 0;
            txd <= 1'b1; busy <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    txd <= 1'b1; busy <= 1'b0;
                    if (start) begin
                        shift <= tx_data; state <= START;
                        cnt <= DIV - 1; txd <= 1'b0; busy <= 1'b1;
                    end
                end
                START: begin
                    if (cnt == 0) begin
                        state <= DATA; bit_idx <= 0; cnt <= DIV - 1;
                        txd <= shift[0];           // LSB first
                    end else cnt <= cnt - 1;
                end
                DATA: begin
                    if (cnt == 0) begin
                        if (bit_idx == 4'd7) begin
                            state <= STOP; cnt <= DIV - 1; txd <= 1'b1;
                        end else begin
                            bit_idx <= bit_idx + 1; cnt <= DIV - 1;
                            txd <= shift[bit_idx + 1];
                        end
                    end else cnt <= cnt - 1;
                end
                STOP: begin
                    if (cnt == 0) begin
                        state <= IDLE; txd <= 1'b1;
                    end else cnt <= cnt - 1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
