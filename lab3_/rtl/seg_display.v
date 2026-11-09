// seg_display.v —— 6 位共阳极数码管动态扫描（结果放最右位）
// 共阳极：位选低有效，段选低有效（段码取反）
module seg_display (
    input  clk,
    input  rst_n,
    input  [3:0] digit,        // 0..9 显示在最右位，其它位熄灭
    output reg [7:0] seg_led,  // a~g,dp
    output reg [5:0] seg_sel
);
    // 共阳极段码（低有效）：bit7..0 = dp g f e d c b a
    // 数字 0..9 的段码（a..g）
    function [6:0] seg_code;
        input [3:0] d;
        begin
            case (d)
                4'd0: seg_code = 7'b0111111; // a b c d e f
                4'd1: seg_code = 7'b0000110; // b c
                4'd2: seg_code = 7'b1011011; // a b d e g
                4'd3: seg_code = 7'b1001111; // a b c d g
                4'd4: seg_code = 7'b1100110; // b c f g
                4'd5: seg_code = 7'b1101101; // a c d f g
                4'd6: seg_code = 7'b1111101; // a c d e f g
                4'd7: seg_code = 7'b0000111; // a b c
                4'd8: seg_code = 7'b1111111; // a b c d e f g
                4'd9: seg_code = 7'b1101111; // a b c d f g
                default: seg_code = 7'b0000000; // 熄灭
            endcase
        end
    endfunction

    reg [15:0] scan_cnt;
    reg [2:0]  scan_pos;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 0; scan_pos <= 0;
            seg_led <= 8'hFF; seg_sel <= 6'h3F;
        end else begin
            scan_cnt <= scan_cnt + 1;
            if (scan_cnt == 16'd50000) begin        // ~1kHz 扫描
                scan_cnt <= 0;
                scan_pos <= scan_pos + 1;
                if (scan_pos == 3'd5) scan_pos <= 3'd0;
            end
            // 位选：低有效；具体扫描位由 scan_pos 决定
            seg_sel <= ~(6'b000001 << scan_pos);
            // 段选：共阳，取反；只有最右位(scan_pos==0)显示结果
            if (scan_pos == 3'd0)
                seg_led <= ~{1'b0, seg_code(digit)};
            else
                seg_led <= 8'hFF;                    // 熄灭（全高）
        end
    end
endmodule
