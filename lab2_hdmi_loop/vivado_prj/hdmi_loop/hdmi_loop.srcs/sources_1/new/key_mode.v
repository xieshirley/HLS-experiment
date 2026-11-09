`timescale 1ns / 1ps
//============================================================
// key_mode.v —— 按键消抖 + 边沿检测 + 模式号计数（格雷码）
//------------------------------------------------------------
// 任务四：每按一次键，模式 +1（模 4）
//
//   key_raw ──> 2 级同步 ──> 计数消抖(15ms) ──> 下降/上升沿 ──> 模式计数(mod 4, 格雷码)
//
// 设计要点：
//   1. **计数消抖**：按键电平必须"稳定保持" DEB_CNT 个时钟才被承认，
//      抖动期间计数器反复清零，所以短于 15ms 的毛刺直接被吃掉。
//      15ms @ 50MHz = 750,000 拍（20 位计数器）。
//   2. **边沿检测**：只在"按下"的跳变沿（消抖后）产生 1 拍脉冲，长按不会连跳。
//   3. **格雷码输出**：步进序列 00 → 01 → 11 → 10 → 00，每次只变 1 位，
//      这样跨到 pixel_clk 域时用普通 2 级同步器就是安全的（不会有译码毛刺）。
//   4. 复位后模式 = 0（直通），与任务书"上电从头开始"一致。
//
// 按键电平：达芬奇板 key 按下为低电平，用 KEY_ACTIVE_LOW 选择；
// 若板子相反（按下为高），把 KEY_ACTIVE_LOW 改成 0 即可。
//============================================================
module key_mode #(
    parameter integer CLK_FREQ        = 50_000_000,  // 消抖时钟频率(Hz)
    parameter integer DEB_MS          = 15,          // 消抖时间(ms)，建议 10~20
    parameter integer KEY_ACTIVE_LOW  = 1            // 1 = 按下为低电平
)(
    input             clk,        // 消抖时钟（sys_clk，50MHz，与 HDMI 无关，始终在跑）
    input             rst_n,      // 复位，低有效
    input             key_raw,    // 按键原始输入
    output reg [1:0]  mode_gray,  // 模式号的格雷码（每步只变 1 位）
    output reg [1:0]  mode_bin,   // 模式号的二进制（0~3，本地用/看 LED）
    output            key_press   // 消抖后的"按下"脉冲（1 拍，调试可用）
);

    //------------------------------------------------------------
    // 消抖阈值：DEB_MS 毫秒对应的时钟数
    //------------------------------------------------------------
    localparam integer DEB_CNT = (CLK_FREQ / 1000) * DEB_MS;

    //------------------------------------------------------------
    // 1. 异步输入 2 级同步 + 极性归一（pressed = 1 表示按下）
    //------------------------------------------------------------
    reg  [1:0] key_sync;
    wire       pressed  = KEY_ACTIVE_LOW ? ~key_sync[1] : key_sync[1];

    always @(posedge clk) begin
        if (!rst_n) key_sync <= 2'b11;                     // 低有效按键：复位当作"未按"
        else        key_sync <= {key_sync[0], key_raw};
    end

    //------------------------------------------------------------
    // 2. 计数消抖：电平必须稳定 DEB_CNT 拍才承认
    //------------------------------------------------------------
    reg              key_stable;       // 消抖后的电平（1 = 按下）
    reg  [20:0]      deb_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            key_stable <= 1'b0;
            deb_cnt    <= 21'd0;
        end else if (pressed != key_stable) begin
            // 输入与当前稳定值不同：攒够 DEB_CNT 拍才翻转
            if (deb_cnt >= DEB_CNT - 1) begin
                key_stable <= pressed;
                deb_cnt    <= 21'd0;
            end else begin
                deb_cnt    <= deb_cnt + 1'b1;
            end
        end else begin
            // 电平与稳定值一致：清零计数器（抖动被吃掉）
            deb_cnt    <= 21'd0;
        end
    end

    //------------------------------------------------------------
    // 3. 边沿检测：只在"从未按 → 按下"的跳变产生 1 拍脉冲
    //------------------------------------------------------------
    reg key_stable_d;

    always @(posedge clk) begin
        if (!rst_n) key_stable_d <= 1'b0;
        else        key_stable_d <= key_stable;
    end

    assign key_press = key_stable & ~key_stable_d;

    //------------------------------------------------------------
    // 4. 模式计数（模 4，格雷码步进 00→01→11→10→00）
    //------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            mode_gray <= 2'b00;
        end else if (key_press) begin
            case (mode_gray)
                2'b00:   mode_gray <= 2'b01;
                2'b01:   mode_gray <= 2'b11;
                2'b11:   mode_gray <= 2'b10;
                default: mode_gray <= 2'b00;
            endcase
        end
    end

    // 本地二进制形式（给 LED 用，同域组合译码即可）
    always @(*) begin
        case (mode_gray)
            2'b00:   mode_bin = 2'd0;
            2'b01:   mode_bin = 2'd1;
            2'b11:   mode_bin = 2'd2;
            default: mode_bin = 2'd3;
        endcase
    end

endmodule
