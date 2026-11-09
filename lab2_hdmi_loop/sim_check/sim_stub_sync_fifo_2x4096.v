`timescale 1ns / 1ps
//====================================================================
// sim_stub_sync_fifo_2x4096.v —— FIFO IP（sync_fifo_2x4096）的行为级仿真替身
//--------------------------------------------------------------------
// 为什么需要它：
//   工程里用的是 Vivado FIFO Generator IP（xilinx.com:ip:fifo_generator:13.2，
//   Native / Common Clock / Block RAM / First Word Fall Through / 带 data_count）。
//   IP 的仿真需要 Vivado 的 IP 仿真库，用 xvlog/xelab 单独跑不动；
//   所以在 sim_check 的脚本里编译本文件（模块名、端口与 IP 完全一致）代替 IP 网络表。
//
// 与真 IP 的差异：只是 FWFT 输出可能差 1 拍、复位细节不同，对 √"延迟是否等于水位"
//   这一功能验证无影响（HS/VS 差 1~2 拍在行消隐 280 拍里无所谓）。
// 真上板 / 工程综合用的是 IP 本体，不是这个文件。
//====================================================================
module sync_fifo_2x4096 (
    input             clk,
    input             srst,
    input      [1:0]  din,
    input             wr_en,
    input             rd_en,
    output     [1:0]  dout,
    output            full,
    output            empty,
    output     [12:0] data_count
);

    localparam integer DEPTH = 4096;

    reg  [1:0]  mem [0:DEPTH-1];
    reg  [11:0] wr_ptr;
    reg  [11:0] rd_ptr;
    reg  [12:0] cnt;

    assign full       = (cnt == DEPTH);
    assign empty      = (cnt == 0);
    assign data_count = cnt;
    assign dout       = mem[rd_ptr];      // FWFT：表头一直可见

    always @(posedge clk) begin
        if (srst) begin
            wr_ptr <= 12'd0;
            rd_ptr <= 12'd0;
            cnt    <= 13'd0;
        end else begin
            if (wr_en && (cnt != DEPTH)) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= wr_ptr + 12'd1;
            end
            if (rd_en && (cnt != 0))
                rd_ptr <= rd_ptr + 12'd1;

            case ({wr_en && (cnt != DEPTH), rd_en && (cnt != 0)})
                2'b10:   cnt <= cnt + 13'd1;
                2'b01:   cnt <= cnt - 13'd1;
                default: cnt <= cnt;
            endcase
        end
    end

endmodule
