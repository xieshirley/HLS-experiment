@echo off
setlocal
set VIVADO_BIN=D:\software\vivado18_3\systemfile\Vivado\2018.3\bin
set PRJ=D:\HLS\HLS-experiment\lab2_hdmi_loop\vivado_prj\hdmi_loop\hdmi_loop.srcs\sources_1
cd /d "%~dp0"
call "%VIVADO_BIN%\xvlog.bat" --nolog "%PRJ%\imports\hls\rgb2gray\rgb2gray.v" "%PRJ%\imports\hls\rgb2gray\rgb2gray_mac_mulabkb.v" "%PRJ%\new\video_core.v" "tb_probe.v"
if errorlevel 1 goto :err
call "%VIVADO_BIN%\xelab.bat" --nolog -s sim_probe --debug off tb_probe
if errorlevel 1 goto :err
call "%VIVADO_BIN%\xsim.bat" --nolog sim_probe -R
goto :eof
:err
echo ***** FAILED *****
exit /b 1
