@echo off
setlocal
set VIVADO_BIN=D:\software\vivado18_3\systemfile\Vivado\2018.3\bin
set SRC=D:\HLS\HLS-experiment\lab2_hdmi_loop\vivado_prj\hdmi_loop\hdmi_loop.srcs\sources_1\new
cd /d "%~dp0"

call "%VIVADO_BIN%\xvlog.bat" --nolog "%SRC%\video_sync.v" "sim_stub_sync_fifo_2x4096.v" "tb_video_sync.v"
if errorlevel 1 goto :err

call "%VIVADO_BIN%\xelab.bat" --nolog -s sim_vs --debug off tb_video_sync
if errorlevel 1 goto :err

call "%VIVADO_BIN%\xsim.bat" --nolog sim_vs -R
if errorlevel 1 goto :err
goto :eof

:err
echo.
echo ***** BUILD/SIM FAILED *****
exit /b 1
