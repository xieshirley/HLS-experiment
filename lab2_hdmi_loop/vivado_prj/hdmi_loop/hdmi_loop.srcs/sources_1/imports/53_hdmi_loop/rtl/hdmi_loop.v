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
// 实验二改造（任务一~任务四）：
//   * 任务一/二：rgb2gray 灰度核、gauss3x3 高斯平滑核级联输出
//   * 任务三：输出同步重建（HS/VS 走 SRL 延迟链、DE 定长延迟 + 像素 FIFO）
//   * 任务四：按键运行时切换 4 档模式 + LED[1:0] 显示当前模式
//             1) 顶层加 key[3:0] 输入端口，引脚抄自达芬奇官方 XDC（T1/U1/W2/T3）
//             2) key_mode.v 做 15ms 计数消抖 + 上升沿检测，每按一次模式 +1（模 4）
//             3) 4 选 1 mux 选通：直通 / 灰度 / 平滑 / 锐化
//             4) 当前模式号输出到 led[1:0]，led[2]/led[3] 保留 FIFO 欠载/溢出诊断
//----------------------------------------------------------------------------------------
//****************************************************************************************//
module hdmi_loop(
    input               sys_clk,               //50M系统时钟（消抖用，始终在跑）
    input               rst_n,                 //系统复位，低有效
    //按键（任务四）
    input  [3:0]        key,                   //板上按键，按下为低电平；key[0] 切模式
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
    output [3:0]        led                    //led[1:0]=模式号，led[2]=欠载，led[3]=溢出
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
wire [7:0]  sharp_w;           //锐化输出像素（比 gauss 晚 2 拍）
wire        sharp_v;           //锐化输出有效

//三路同步后的输出（灰度档 / 平滑档 / 锐化档）
wire [23:0] rgb_gray, rgb_gauss, rgb_sharp;
wire        de_gray, hs_gray, vs_gray;
wire        de_gauss, hs_gauss, vs_gauss;
wire        de_sharp, hs_sharp, vs_sharp;

//FIFO 诊断事件
wire        und_gray,  ovf_gray;
wire        und_gauss, ovf_gauss;
wire        und_sharp, ovf_sharp;

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

//*****************************************************
//**   任务四①：按键消抖 + 模式号（sys_clk 域，15ms 计数消抖）
//*****************************************************
// 引脚（抄自达芬奇官方 DaVinci_FPGA_IO.xdc）：
//   key[0]=T1  key[1]=U1  key[2]=W2  key[3]=T3   均为 LVCMOS33，按下为低
// 用 key[0] 切模式，其余三位预留。
wire [1:0] mode_gray_sys;   // 格雷码（sys_clk 域）
wire [1:0] mode_bin_sys;    // 二进制（sys_clk 域，给 LED）
wire       key_press;       // 消抖后"按下"脉冲（调试可用）

key_mode #(
    .CLK_FREQ       (50_000_000),
    .DEB_MS         (15),
    .KEY_ACTIVE_LOW (1)
) u_key_mode (
    .clk        (sys_clk),
    .rst_n      (rst_n),
    .key_raw    (key[0]),
    .mode_gray  (mode_gray_sys),
    .mode_bin   (mode_bin_sys),
    .key_press  (key_press)
);

//*****************************************************
//**   任务四②：模式号跨到 pixel_clk 域（格雷码 → 2 级同步 → 译码）
//*****************************************************
// 格雷码每次只变 1 位，逐位两级同步是安全的（不会出现非法中间码）
reg  [1:0] mode_meta;
reg  [1:0] mode_gray_pix;

always @(posedge pixel_clk) begin
    if (rx_rst) begin
        mode_meta     <= 2'b00;
        mode_gray_pix <= 2'b00;
    end else begin
        mode_meta     <= mode_gray_sys;
        mode_gray_pix <= mode_meta;
    end
end

reg [1:0] mode_pix;      // 0=直通 1=灰度 2=平滑 3=锐化
always @(*) begin
    case (mode_gray_pix)
        2'b00:   mode_pix = 2'd0;
        2'b01:   mode_pix = 2'd1;
        2'b11:   mode_pix = 2'd2;
        default: mode_pix = 2'd3;
    endcase
end

//*****************************************************
//**   视频处理：灰度核 + 高斯核 + 锐化核 + 三路同步
//*****************************************************
// 锐化流相对 gauss 流多出的拍数（核内 7 级 vs 5 级流水）
localparam integer SHARP_PIPE = 2;
// 实测：gauss 流比输入 DE 晚 2211 拍（tb_offset：LAT=2205 时相位偏移 +6）
localparam integer SYNC_BASE  = 2211;

// 核处理层：一次例化出三路流（灰度 / 平滑 / 锐化）
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
    .sharp_out    (sharp_w),        // 锐化像素（核内算，比 gauss 多 2 级流水）
    .sharp_valid  (sharp_v),
    .sharp_ready  (1'b1)
);

//-------------------------------------------------------------
// 任务四③：三路各自做同步重建（参数是编译期常量，所以用三个例化，
//          而不是一个可运行时改延迟的模块 —— 后者要 RAM 延迟线，改动大且风险高）
//   灰度档：LATENCY=3、DE 跟核 TVALID（USE_FIFO_OUT=0）
//   平滑档：LATENCY=2211、定长 DE + 像素 FIFO
//   锐化档：LATENCY=2213（= 2211 + 2）、定长 DE + 像素 FIFO
//-------------------------------------------------------------
video_sync #(
    .LATENCY      (3),
    .USE_FIFO_OUT (0)
) u_sync_gray(
    .clk        (pixel_clk),
    .rst_n      (~rx_rst),
    .gray_in    (gray_w),
    .gray_valid (gray_v),
    .de_in      (video_de),
    .hs_in      (video_hs),
    .vs_in      (video_vs),
    .rgb_out    (rgb_gray),
    .de_out     (de_gray),
    .hs_out     (hs_gray),
    .vs_out     (vs_gray),
    .und_evt    (und_gray),
    .ovf_evt    (ovf_gray)
);

video_sync #(
    .LATENCY      (SYNC_BASE),
    .USE_FIFO_OUT (1)
) u_sync_gauss(
    .clk        (pixel_clk),
    .rst_n      (~rx_rst),
    .gray_in    (gauss_w),
    .gray_valid (gauss_v),
    .de_in      (video_de),
    .hs_in      (video_hs),
    .vs_in      (video_vs),
    .rgb_out    (rgb_gauss),
    .de_out     (de_gauss),
    .hs_out     (hs_gauss),
    .vs_out     (vs_gauss),
    .und_evt    (und_gauss),
    .ovf_evt    (ovf_gauss)
);

video_sync #(
    .LATENCY      (SYNC_BASE + SHARP_PIPE),
    .USE_FIFO_OUT (1)
) u_sync_sharp(
    .clk        (pixel_clk),
    .rst_n      (~rx_rst),
    .gray_in    (sharp_w),
    .gray_valid (sharp_v),
    .de_in      (video_de),
    .hs_in      (video_hs),
    .vs_in      (video_vs),
    .rgb_out    (rgb_sharp),
    .de_out     (de_sharp),
    .hs_out     (hs_sharp),
    .vs_out     (vs_sharp),
    .und_evt    (und_sharp),
    .ovf_evt    (ovf_sharp)
);

//*****************************************************
//**   任务四④：模式号 4 选 1 mux → 编码器
//*****************************************************
// 四路都在 pixel_clk 域，最终统一打一拍再送编码器（对四路是等量的 1 拍，
// 不改变任何相对相位）。模式 0 就是厂家原始环回那根线。
reg [23:0] enc_din_r;
reg        enc_de_r, enc_hs_r, enc_vs_r;

always @(posedge pixel_clk) begin
    if (rx_rst) begin
        enc_din_r <= 24'd0;
        enc_de_r  <= 1'b0;
        enc_hs_r  <= 1'b0;
        enc_vs_r  <= 1'b0;
    end else begin
        case (mode_pix)
            2'd0: begin   // 直通：hdmi_rx 原始输出
                enc_din_r <= video_rgb;
                enc_de_r  <= video_de;
                enc_hs_r  <= video_hs;
                enc_vs_r  <= video_vs;
            end
            2'd1: begin   // 灰度
                enc_din_r <= rgb_gray;
                enc_de_r  <= de_gray;
                enc_hs_r  <= hs_gray;
                enc_vs_r  <= vs_gray;
            end
            2'd2: begin   // 高斯平滑
                enc_din_r <= rgb_gauss;
                enc_de_r  <= de_gauss;
                enc_hs_r  <= hs_gauss;
                enc_vs_r  <= vs_gauss;
            end
            default: begin // 拉普拉斯锐化
                enc_din_r <= rgb_sharp;
                enc_de_r  <= de_sharp;
                enc_hs_r  <= hs_sharp;
                enc_vs_r  <= vs_sharp;
            end
        endcase
    end
end

dvi_transmitter_top u_rgb2dvi_0(
    .pclk           (pixel_clk),
    .pclk_x5        (pixel_clk_5x),
    .reset_n        (~rx_rst),
                
    .video_din      (enc_din_r),
    .video_hsync    (enc_hs_r),
    .video_vsync    (enc_vs_r),
    .video_de       (enc_de_r),
                
    .tmds_clk_p     (clk_hdmi_out_p),
    .tmds_clk_n     (clk_hdmi_out_n),
    .tmds_data_p    (data_hdmi_out_p),
    .tmds_data_n    (data_hdmi_out_n), 
    .tmds_oen       (hdmi_out_oen)
    );  

//*****************************************************
//**   调试：每帧拍数统计 + ILA（pixel_clk 域）
//*****************************************************
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

// probe0 = video_de
// probe1 = {enc_vs, enc_hs, enc_de, gauss_v, gray_v, video_vs, video_hs}
// probe2 = {gauss_w, sharp_w}
// probe3 = 上一帧灰度核输出拍数（应 ≈ 2073600）
// probe4 = 上一帧高斯核输出拍数（应 ≈ 2073600）
dbg_ila u_dbg_ila (
    .clk    (pixel_clk),
    .probe0 (video_de),
    .probe1 ({enc_vs_r, enc_hs_r, enc_de_r, gauss_v, gray_v, video_vs, video_hs}),
    .probe2 ({gauss_w, sharp_w}),
    .probe3 (dbg_gray_beats),
    .probe4 (dbg_gauss_beats)
);

//*****************************************************
//**   任务四⑤：LED
//*****************************************************
// led[1:0] = 当前模式号（00=直通 01=灰度 10=平滑 11=锐化）
//            取自 sys_clk 域，所以没有 HDMI 输入时按键依然能看到模式变化
// led[2]   = 当前档的像素 FIFO 出现过欠载（DE 比数据早 -> 左黑条）
// led[3]   = 当前档的像素 FIFO 出现过溢出（深度不够 -> 撕裂）
//            两灯只在模式 2/3（FIFO 档）有意义，模式 0/1 恒灭
assign led[1:0] = mode_bin_sys;

wire und_sel = (mode_pix == 2'd2) ? und_gauss :
               (mode_pix == 2'd3) ? und_sharp : 1'b0;
wire ovf_sel = (mode_pix == 2'd2) ? ovf_gauss :
               (mode_pix == 2'd3) ? ovf_sharp : 1'b0;

reg und_seen, ovf_seen;
reg vs_enc_d;
always @(posedge pixel_clk) begin
    vs_enc_d <= enc_vs_r;
    if (rx_rst) begin
        und_seen <= 1'b0;
        ovf_seen <= 1'b0;
    end else if (enc_vs_r && !vs_enc_d) begin
        und_seen <= 1'b0;            // 每帧清零
        ovf_seen <= 1'b0;
    end else begin
        if (und_sel) und_seen <= 1'b1;
        if (ovf_sel) ovf_seen <= 1'b1;
    end
end
assign led[2] = und_seen;
assign led[3] = ovf_seen;

endmodule
