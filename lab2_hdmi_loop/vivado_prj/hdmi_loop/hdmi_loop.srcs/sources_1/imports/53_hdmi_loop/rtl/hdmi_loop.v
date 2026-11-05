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
    output [2:0]        data_hdmi_out_p        //输出差分数据
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
wire [7:0]  gray_w;
wire        gray_v;
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
//**        视频处理：HLS 核 + 核外同步对齐
//*****************************************************
// rgb2gray 核是纯流水线（ap_ctrl_none，1 像素/拍），
// 核输出 dst 有效沿比输入 src 有效沿晚 3 拍（LATENCY = 3）。
// 行/场/数据有效由 video_sync 统一补偿这 3 拍：
//   de_out      = 核输出 TVALID（= de 延迟 3 拍，核停顿也不会错拍）
//   hs_out/vs_out = hs/vs 延迟 3 拍
//   rgb_out     = {gray,gray,gray}
video_core u_video_core(
    .clk        (pixel_clk),        // 像素时钟
    .rst_n      (~rx_rst),          // 复位，低有效
    .rgb_in     (video_rgb),        // 输入 RGB
    .de_in      (video_de),         // 输入数据有效 -> src TVALID
    .src_ready  (),                 // src TREADY（调试时可接 ILA 观察）
    .gray_out   (gray_w),           // 灰度像素 -> dst TDATA
    .gray_valid (gray_v),           // 灰度有效   -> dst TVALID
    .gray_ready (1'b1)              // 同步模块不反压
);

video_sync #(
    .LATENCY    (3)                 // 核流水线延迟拍数：3 拍
) u_video_sync(
    .clk        (pixel_clk),
    .rst_n      (~rx_rst),
    .gray_in    (gray_w),
    .gray_valid (gray_v),
    .de_in      (video_de),
    .hs_in      (video_hs),
    .vs_in      (video_vs),
    .rgb_out    (rgb_proc),         // 送 dvi_transmitter_top
    .de_out     (de_proc),
    .hs_out     (hs_proc),
    .vs_out     (vs_proc)
);

dvi_transmitter_top u_rgb2dvi_0(
    .pclk           (pixel_clk),
    .pclk_x5        (pixel_clk_5x),
    .reset_n        (~rx_rst),
                
    .video_din      (rgb_proc),//(video_rgb),
    .video_hsync    (hs_proc),  //(video_hs),/
    .video_vsync    (vs_proc),  //(video_vs),/
    .video_de       (de_proc),  //(video_de),/
                
    .tmds_clk_p     (clk_hdmi_out_p),
    .tmds_clk_n     (clk_hdmi_out_n),
    .tmds_data_p    (data_hdmi_out_p),
    .tmds_data_n    (data_hdmi_out_n), 
    .tmds_oen       (hdmi_out_oen)
    );  
endmodule