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
// File name:           tmds_clock
// Descriptions:        HDMI时钟模块
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2020/5/8 9:30:00
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module tmds_clock(

     input      tmds_clk_p,
     input      tmds_clk_n,


     output     pixelclk,
     output     serialclk,
     output     alocked     
    );

//wire define  
wire        clk_in_hdmi_clk;
wire        pixelclk;     
wire        serialclk; 
wire        alocked;
wire        clkfbout_hdmi_clk;
wire        clk_out_5x_hdmi_clk;

//*****************************************************
//**                    main code
//***************************************************** 
  
IBUFDS  # (
  .DIFF_TERM     ("FALSE"),
  .IBUF_LOW_PWR  ("TRUE"),
  .IOSTANDARD    ("TMDS_33")    
) u_IBUFDS(
  .O    (clk_in_hdmi_clk),
  .I    (tmds_clk_p),
  .IB   (tmds_clk_n)     
); 

     
MMCME2_ADV                                                                 
#(.BANDWIDTH            ("OPTIMIZED"),
  .CLKOUT4_CASCADE      ("FALSE"),
  .COMPENSATION         ("ZHOLD"),
  .STARTUP_WAIT         ("FALSE"),
  .DIVCLK_DIVIDE        (1),                //分频系数
  .CLKFBOUT_MULT_F      (5.000),            //反馈时钟的倍数系数
  .CLKFBOUT_PHASE       (0.000),
  .CLKFBOUT_USE_FINE_PS ("FALSE"),
  .CLKOUT0_DIVIDE_F     (1.000),            //分频系数，相位延迟，占空比
  .CLKOUT0_PHASE        (0.000),
  .CLKOUT0_DUTY_CYCLE   (0.500),
  .CLKOUT0_USE_FINE_PS  ("FALSE"),
  .CLKOUT1_DIVIDE       (5),                //分频系数，相位延迟，占空比
  .CLKOUT1_PHASE        (0.000),
  .CLKOUT1_DUTY_CYCLE   (0.500),
  .CLKOUT1_USE_FINE_PS  ("FALSE"),
  .CLKIN1_PERIOD        (6.667))            //输入时钟的周期，单位ns
                                      
mmcm_adv_inst                                                         
  // Output clocks                                                    
 (                                                                    
  .CLKFBOUT            (clkfbout_hdmi_clk),                           
  .CLKFBOUTB           (),                            
  .CLKOUT0             (clk_out_5x_hdmi_clk),                         
  .CLKOUT0B            (),                             
  .CLKOUT1             (clk_out_1x_hdmi_clk),                              
  .CLKOUT1B            (),                             
  .CLKOUT2             (),                              
  .CLKOUT2B            (),                             
  .CLKOUT3             (),                              
  .CLKOUT3B            (),                             
  .CLKOUT4             (),                              
  .CLKOUT5             (),                              
  .CLKOUT6             (),                              
   // Input clock control                                             
  .CLKFBIN             (clkfbout_hdmi_clk),                           
  .CLKIN1              (clk_in_hdmi_clk),                             
  .CLKIN2              (1'b0),                                        
   // Tied to always select the primary input clock                   
  .CLKINSEL            (1'b1),                                        
  // Ports for dynamic reconfiguration                                
  .DADDR               (7'h0),                                        
  .DCLK                (1'b0),                                        
  .DEN                 (1'b0),                                        
  .DI                  (16'h0),                                       
  .DO                  (),                                   
  .DRDY                (),                                 
  .DWE                 (1'b0),                                        
  // Ports for dynamic phase shift                                    
  .PSCLK               (1'b0),                                        
  .PSEN                (1'b0),                                        
  .PSINCDEC            (1'b0),                                        
  .PSDONE              (),                               
  // Other control and status signals                                 
  .LOCKED              (alocked),                                
  .CLKINSTOPPED        (),                         
  .CLKFBSTOPPED        (),                         
  .PWRDWN              (1'b0),                                        
  .RST                 (0));                           
 
// 5x fast serial clock
BUFG u_BUFG(
      .O (serialclk), // 1-bit output: Clock output (connect to I/O clock loads).
      .I (clk_out_5x_hdmi_clk)  // 1-bit input: Clock input (connect to an IBUF or BUFMR).
   );   
   
BUFG u_BUFG_0(
      .O (pixelclk), // 1-bit output: Clock output (connect to I/O clock loads).
      .I (clk_out_1x_hdmi_clk)  // 1-bit input: Clock input (connect to an IBUF or BUFMR).
   );      
 
 
endmodule