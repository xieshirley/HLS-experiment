`timescale 1ns / 1ps
//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：http://www.openedv.com/forum.php
//淘宝店铺：https://zhengdianyuanzi.tmall.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2023-2033
//All rights reserved                                  
//----------------------------------------------------------------------------------------
// File name:           hdmi_loop
// Created by:          正点原子
// Created date:        2023年2月3日14:17:02
// Version:             V1.0
// Descriptions:        HDMI环回实验
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//
module hdmi_loop(
    input               sys_clk,               //50M系统时钟
    input               rst_n,                 //系统复位，低有效
    //hdmi in
    input               hdmi_ddc_scl_io,       //IIC时钟
    inout               hdmi_ddc_sda_io,       //IIC数据
    output              hdmi_in_hpd,           //热插拔信号
    output [0:0]        hdmi_in_oen,           //输入输出切换信号 
    input               clk_hdmi_in_n,         //输入差分时钟
    input               clk_hdmi_in_p,         //输入差分时钟
    input  [2:0]        data_hdmi_in_n,        //输入差分数据
    input  [2:0]        data_hdmi_in_p,        //输入差分数据
    //hdmi out
    output [0:0]        hdmi_out_oen,          //输入输出切换信号 
    output              clk_hdmi_out_n,        //输出差分时钟
    output              clk_hdmi_out_p,        //输出差分时钟
    output [2:0]        data_hdmi_out_n,       //输出差分数据
    output [2:0]        data_hdmi_out_p,       //输出差分数据
    //debug led
    output [3:0]        led                    //调试指示灯（驱动逻辑见文件末尾）
);

//wire define
wire        clk_10m;           //10m时钟
wire        clk_200m;          //200m时钟
wire        rx_rst;            //复位信号，高有效
wire        pixel_clk;         //像素时钟
wire        pixel_clk_5x;      //5倍像素时钟
wire        video_hs;          //行信号
wire        video_vs;          //场信号
wire        video_de;          //数据有效使能
wire [23:0] video_rgb;         //像素数据
wire [7:0]  gray_w;            //灰度核输出像素
wire        gray_v;            //灰度核输出有效
wire [7:0]  gauss_w;           //高斯平滑输出像素
wire        gauss_v;           //高斯平滑输出有效
wire        pix_und;           //像素 FIFO 欠载事件（1 拍脉冲）
wire        pix_ovf;           //像素 FIFO 溢出事件（1 拍脉冲）
wire [7:0]  sharp_w;           //锐化输出像素（比 gauss 晚 3 拍）
wire        sharp_v;           //锐化输出有效
wire [23:0] rgb_proc;
wire        de_proc, hs_proc, vs_proc;

//*****************************************************
//**                    main code
//*****************************************************      
//时钟模块
mmcm u_mmcm(
.clk_out1           (clk_10m),  // output clk_out1
.clk_out2           (clk_200m),  // output clk_out1
.locked             (       ),  // output locked
.clk_in1            (sys_clk)   // input clk_in1
);      
    
//读edid模块    
i2c_edid u_i2c_edid (
	.clk(clk_10m),
	.rst(~rst_n),
	.scl(hdmi_ddc_scl_io),
	.sda(hdmi_ddc_sda_io)
);    
    
//hdmi解码模块    
hdmi_rx u_hdmi_rx(
    .clk_10m       (clk_10m),
    .clk_200m      (clk_200m),
    //input
    .tmdsclk_p     (clk_hdmi_in_p),     
    .tmdsclk_n     (clk_hdmi_in_n),      
    .blue_p        (data_hdmi_in_p[0]), 
    .green_p       (data_hdmi_in_p[1]),  
    .red_p         (data_hdmi_in_p[2]),  
    .blue_n        (data_hdmi_in_n[0]),  
    .green_n       (data_hdmi_in_n[1]), 
    .red_n         (data_hdmi_in_n[2]), 
    .rst_n         (rst_n),              
    //output       
    .reset         (rx_rst),             
    .pclk          (pixel_clk),         
    .pclkx5        (pixel_clk_5x),       
    .hsync         (video_hs),          
    .vsync         (video_vs),          
    .de            (video_de),          
    .rgb_data      (video_rgb),         
    .hdmi_in_en    (hdmi_in_oen),    
    .hdmi_in_hpd   (hdmi_in_hpd)  
  );      
   
 // HDMI解码封装层模块      

//*****************************************************
//**        视频处理：灰度核 + 高斯核 + 锐化 + 核外同步对齐
//*****************************************************
// 模式开关（只改这一行）：
//   MODE = 0 → 直入直出：RGB 直接送编码器（不打拍，等同厂家原始环回）
//   MODE = 1 → 灰度输出：rgb2gray（HS/VS 延迟 3 拍，DE 跟核 TVALID）
//   MODE = 2 → 平滑输出：rgb2gray → gauss3x3（HS/VS 延迟 2205 拍 + 像素 FIFO）
//   MODE = 3 → 锐化输出：sharp = 2*orig ? smooth（两级流水，
//              同步延迟 2205 + 3 = 2208 拍；3 = FIFO同步读1 + 算术1 + 限幅1）
localparam integer MODE         = 3;

// 锐化流相对 gauss 流多出的拍数：FIFO 同步读 1 + 第1级算术 1 + 第2级限幅 1
localparam integer SHARP_PIPE   = 2;
localparam integer SYNC_BASE    = 2211;   // 实测：gauss 流比输入 DE 晚 2211 拍
localparam integer SYNC_MARGIN  = 0;      // 0 = 直接用实测值（留余量只会把黑条从左边缘挪到右边缘）
localparam integer USE_FIFO_OUT_M = (MODE == 2) || (MODE == 3);
localparam integer SYNC_LATENCY   = (MODE == 2) ? SYNC_BASE + SYNC_MARGIN :
                                    (MODE == 3) ? SYNC_BASE + SYNC_MARGIN + SHARP_PIPE : 3;

// 核处理层：一次例化出三路流（灰度 / 平滑 / 锐化），由 MODE 在下面选一路
video_core u_video_core(
    .clk          (pixel_clk),      // 像素时钟
    .rst_n        (~rx_rst),        // 复位，低有效
    .rgb_in       (video_rgb),      // 输入 RGB
    .de_in        (video_de),       // 输入数据有效 -> src TVALID
    .src_ready    (),               // src TREADY（调试时可接 ILA 观察）
    .gray_out     (gray_w),         // 灰度像素
    .gray_valid   (gray_v),
    .gauss_out    (gauss_w),        // 高斯平滑像素
    .gauss_valid  (gauss_v),
    .gauss_ready  (1'b1),           // 下游不反压
    .sharp_out    (sharp_w),        // 锐化像素（核内算，比 gauss 多 1 级流水）
    .sharp_valid  (sharp_v),
    .sharp_ready  (1'b1)
);

//-------------------------------------------------------------
// 按 MODE 选一路像素流送同步模块（MODE 是常量，综合会折叠）
//-------------------------------------------------------------
wire [7:0] core_pix = (MODE == 1) ? gray_w  :
                      (MODE == 2) ? gauss_w :
                                    sharp_w;
wire       core_vld = (MODE == 1) ? gray_v  :
                      (MODE == 2) ? gauss_v :
                                    sharp_v;

// 同步只补 DE/HS/VS 的相位，像素永远从核/TVALID 取：
//   USE_FIFO_OUT=0（MODE=1 灰度）→ de_out = 核 TVALID，像素直通
//   USE_FIFO_OUT=1（MODE=2/3）   → de_out = 输入 DE 延迟 LATENCY 拍，像素走 FIFO
video_sync #(
    .LATENCY      (SYNC_LATENCY),     // 灰度 3 / 平滑 2205 / 锐化 2208 拍
    .USE_FIFO_OUT (USE_FIFO_OUT_M)
) u_video_sync(
    .clk        (pixel_clk),
    .rst_n      (~rx_rst),
    .gray_in    (core_pix),
    .gray_valid (core_vld),
    .de_in      (video_de),
    .hs_in      (video_hs),
    .vs_in      (video_vs),
    .rgb_out    (rgb_proc),         // 送 dvi_transmitter_top
    .de_out     (de_proc),
    .hs_out     (hs_proc),
    .vs_out     (vs_proc),
    .und_evt    (pix_und),
    .ovf_evt    (pix_ovf)
);

//*****************************************************
//**   调试：每帧拍数统计 + ILA（pixel_clk 域，5 个 probe）
//*****************************************************
// probe0 = video_de                     （输入数据有效）
// probe1 = {vs_proc, hs_proc, de_proc, gauss_v, gray_v, video_vs, video_hs}
// probe2 = {gauss_w[7:0], sharp_w[7:0]}
// probe3 = 上一帧灰度核输出拍数（应 ≈ 1920×1080 = 2073600）
// probe4 = 上一帧高斯核输出拍数（应 ≈ 2073600；为 0 说明高斯核没出数据）
wire [23:0] dbg_gray_beats;
wire [23:0] dbg_gauss_beats;

video_dbg u_video_dbg (
    .clk           (pixel_clk),
    .rst_n         (~rx_rst),
    .vs_in         (video_vs),
    .gray_valid    (gray_v),
    .smooth_valid  (gauss_v),
    .gray_beats    (dbg_gray_beats),
    .gauss_beats   (dbg_gauss_beats)
);

dbg_ila u_dbg_ila (
    .clk    (pixel_clk),
    .probe0 (video_de),
    .probe1 ({vs_proc, hs_proc, de_proc, gauss_v, gray_v, video_vs, video_hs}),
    .probe2 ({gauss_w, sharp_w}),
    .probe3 (dbg_gray_beats),
    .probe4 (dbg_gauss_beats)
);

//*****************************************************
//**   调试：把"每帧拍数"画成画面顶部的白条（不依赖 JTAG/ILA）
//*****************************************************
// 第 0 个有效行白条长度 = 灰度核上一帧拍数 / 8192（满格 ≈ 252 像素 ≈ 2,073,600 拍）
// 第 1 个有效行白条长度 = 高斯核上一帧拍数 / 8192（长度 0 → 高斯核完全没出数）
// 第 2 个有效行是固定 64 像素的橙色"心跳条"，用来确认叠加逻辑在跑
// 本版与 hs/vs 极性无关，且条长封顶 400（统计值饱和也不会涂满整行）
localparam integer DBG_BAR = 0;   // 0 = 关闭画面白条（改看 LED）

reg  [11:0] dbg_col;                 // 行内 DE 计数
reg  [11:0] dbg_row;                 // 有效行计数
reg         de_d, vs_d;
reg         de_seen;                 // 本帧是否已经出现过 de

wire de_fall = de_d & ~de_proc;      // 每行一次
wire vs_edge = vs_proc ^ vs_d;       // 任意极性都能识别

wire [11:0] bar_gray  = (dbg_gray_beats[23:13]  > 12'd400) ? 12'd400 : dbg_gray_beats[23:13];
wire [11:0] bar_gauss = (dbg_gauss_beats[23:13] > 12'd400) ? 12'd400 : dbg_gauss_beats[23:13];
wire [11:0] bar_fixed = 12'd64;

always @(posedge pixel_clk) begin
    de_d <= de_proc;
    vs_d <= vs_proc;

    if (~rx_rst) begin
        dbg_col <= 12'd0;
        dbg_row <= 12'd0;
        de_seen <= 1'b0;
    end else begin
        // 列：DE 期间自增，消隐期清零（与 hs 无关）
        if (de_proc) dbg_col <= dbg_col + 12'd1;
        else         dbg_col <= 12'd0;

        // 行：vs 任意边沿重新起帧；每个 DE 结束算一行
        if (vs_edge) begin
            dbg_row <= 12'd0;
            de_seen <= 1'b0;
        end else if (de_proc) begin
            de_seen <= 1'b1;
        end else if (de_fall && de_seen) begin
            dbg_row <= dbg_row + 12'd1;
        end
    end
end

wire [23:0] rgb_enc = (!DBG_BAR)                                     ? rgb_proc :
                      ((dbg_row == 12'd0) && (dbg_col < bar_gray ))  ? 24'hFFFFFF :
                      ((dbg_row == 12'd1) && (dbg_col < bar_gauss))  ? 24'hFFFFFF :
                      ((dbg_row == 12'd2) && (dbg_col < bar_fixed))  ? 24'hFF8000 :
                                                                       rgb_proc;

//-------------------------------------------------------------
// 编码器输入：
//   MODE == 0 → 直入直出：hdmi_rx 输出直接进编码器（不打拍，
//               就是厂家原始环回那根线；此模式下核处理链被综合裁掉）
//   其它模式  → 走核处理 + 同步补偿后的 rgb_proc/de_proc/hs_proc/vs_proc
//-------------------------------------------------------------
wire [23:0] enc_din = (MODE == 0) ? video_rgb : rgb_enc;
wire        enc_de  = (MODE == 0) ? video_de  : de_proc;
wire        enc_hs  = (MODE == 0) ? video_hs  : hs_proc;
wire        enc_vs  = (MODE == 0) ? video_vs  : vs_proc;


dvi_transmitter_top u_rgb2dvi_0(
    .pclk           (pixel_clk),
    .pclk_x5        (pixel_clk_5x),
    .reset_n        (~rx_rst),
                
    .video_din      (enc_din),
    .video_hsync    (enc_hs),
    .video_vsync    (enc_vs),
    .video_de       (enc_de),
                
    .tmds_clk_p     (clk_hdmi_out_p),
    .tmds_clk_n     (clk_hdmi_out_n),
    .tmds_data_p    (data_hdmi_out_p),
    .tmds_data_n    (data_hdmi_out_n), 
    .tmds_oen       (hdmi_out_oen)
    );  

//*****************************************************
//**   调试 LED（完全不碰视频通路，pixel_clk 域）
//*****************************************************
// led[0] = 高斯核上一帧有出数        → 常亮 = gauss 有输出
// led[1] = 灰度核上一帧有出数        → 常亮 = gray  有输出
// led[2] = 本帧像素 FIFO 出现过欠载（DE 比数据早 → 左黑条）
// led[3] = 本帧像素 FIFO 出现过溢出（深度不够 → 撕裂/错位）
//          两灯都灭 = 像素 FIFO 读写完全健康
// 注意：板子 LED 若是低有效，亮灭含义整体反过来即可。
assign led[0] = (dbg_gauss_beats != 24'd0);
assign led[1] = (dbg_gray_beats  != 24'd0);

reg und_seen, ovf_seen;
reg vs_proc_d;
always @(posedge pixel_clk) begin
    vs_proc_d <= vs_proc;
    if (~rx_rst) begin
        und_seen <= 1'b0; ovf_seen <= 1'b0;
    end else if (vs_proc && !vs_proc_d) begin
        und_seen <= 1'b0; ovf_seen <= 1'b0;      // 每帧清零
    end else begin
        if (pix_und) und_seen <= 1'b1;
        if (pix_ovf) ovf_seen <= 1'b1;
    end
end
assign led[2] = und_seen;
assign led[3] = ovf_seen;

endmodule