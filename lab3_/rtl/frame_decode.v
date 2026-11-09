// frame_decode.v —— 帧解析：0xA5 0x5A | len(2B)=784 | seq(1B) | img(784B) | crc16(2B)
// CRC16-CCITT-FALSE（poly 0x1021, init 0xFFFF），覆盖 [len..img]
// 错帧/乱码丢弃重同步；串口空闲超时（>2ms 无字节）强制回 IDLE，防截断帧卡死
module frame_decode (
    input  clk,
    input  rst_n,
    input  [7:0] rx_data,
    input  rx_valid,
    output reg [9:0] img_waddr,
    output reg [7:0] img_wdata,
    output reg img_we,
    output reg frame_ok,
    output reg [7:0] seq_out
);
    localparam S_IDLE=4'd0, S_H1=4'd1, S_H2=4'd2, S_LLO=4'd3, S_LHI=4'd4,
               S_SEQ=4'd5, S_IMG=4'd6, S_CLO=4'd7, S_CHI=4'd8;

    reg [3:0]  st;
    reg [15:0] crc;
    reg [9:0]  cnt;
    reg [7:0]  crc_lo;
    reg [7:0]  len_lo;
    reg [16:0] idle_cnt;   // 空闲计数（50MHz，>2ms = 100000）

    function [15:0] crc16_byte;
        input [15:0] cin;
        input [7:0]  b;
        reg [15:0] c;
        integer i;
        begin
            c = cin ^ {b, 8'h00};
            for (i = 0; i < 8; i = i + 1)
                c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
            crc16_byte = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; crc <= 16'hFFFF; cnt <= 0; crc_lo <= 0; len_lo <= 0; idle_cnt <= 0;
            img_we <= 1'b0; frame_ok <= 1'b0; seq_out <= 8'h00;
            img_waddr <= 10'd0; img_wdata <= 8'h00;
        end else begin
            img_we   <= 1'b0;
            frame_ok <= 1'b0;

            // 空闲计数：有字节清零，否则递增
            if (rx_valid)      idle_cnt <= 17'd0;
            else if (idle_cnt < 17'd100000) idle_cnt <= idle_cnt + 17'd1;

            // 空闲超时（>2ms 无字节）：强制重同步回 IDLE（防截断帧卡死）
            if (idle_cnt == 17'd100000 && st != S_IDLE) begin
                st    <= S_IDLE;
                crc   <= 16'hFFFF;
                cnt   <= 10'd0;
                crc_lo <= 8'd0;
                len_lo <= 8'd0;
            end

            if (rx_valid) begin
                case (st)
                    S_IDLE: if (rx_data == 8'hA5) st <= S_H1;
                    S_H1:   st <= (rx_data == 8'h5A) ? S_LLO : (rx_data == 8'hA5 ? S_H1 : S_IDLE);
                    S_LLO: begin
                        len_lo <= rx_data;
                        crc    <= crc16_byte(16'hFFFF, rx_data);
                        st     <= S_LHI;
                    end
                    S_LHI: begin
                        crc <= crc16_byte(crc, rx_data);
                        st  <= ((rx_data == 8'h03) && (len_lo == 8'h10)) ? S_SEQ : S_IDLE;
                    end
                    S_SEQ: begin
                        crc   <= crc16_byte(crc, rx_data);
                        seq_out <= rx_data;
                        cnt   <= 10'd0;
                        st    <= S_IMG;
                    end
                    S_IMG: begin
                        img_waddr <= cnt;
                        img_wdata <= rx_data;
                        img_we    <= 1'b1;
                        crc       <= crc16_byte(crc, rx_data);
                        if (cnt == 10'd783) st <= S_CLO;
                        else                cnt <= cnt + 1'b1;
                    end
                    S_CLO: begin
                        crc_lo <= rx_data;
                        st     <= S_CHI;
                    end
                    S_CHI: begin
                        if ({rx_data, crc_lo} == crc) frame_ok <= 1'b1;
                        st <= S_IDLE;
                    end
                    default: st <= S_IDLE;
                endcase
            end
        end
    end
endmodule
