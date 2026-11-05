`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/14 22:22:46
// Design Name: 
// Module Name: hdmi_bright
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module hdmi_bright
(
    input  wire [7:0]  bright     ,        // 'h80 = normal
    input  wire        pixel_clk  ,        //像素时钟
    input  wire        ivideo_hs  ,         //行信号
    input  wire        ivideo_vs  ,         //场信号
    input  wire        ivideo_de  ,        //数据有效使能
    input  wire [23:0] ivideo_rgb ,        //像素数据
    output wire        ivideo_hs  ,         //行信号
    output wire        ivideo_vs  ,         //场信号
    output wire        ivideo_de  ,        //数据有效使能
    output wire [23:0] ivideo_rgb          //像素数据
);
wire [7:0] a = bright - 'h80 ;
wire [7:0] b = 'h80 - bright ;

always @ ( posedge pixel_clk )
begin
    r <= ivideo_rgb[7:0] * 
    output wire        ivideo_hs  ,         //行信号
    output wire        ivideo_vs  ,         //场信号
    output wire        ivideo_de  ,        //数据有效使能
    output wire [23:0] ivideo_rgb          //像素数据
end
endmodule
