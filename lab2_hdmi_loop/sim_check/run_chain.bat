@echo off
REM ==================================================================
REM run_chain.bat -- measure gray->gauss chain latency with REAL HLS RTL
REM look for the "chain latency measurement" block in the output
REM ==================================================================
setlocal
set VIVADO_BIN=D:\software\vivado18_3\systemfile\Vivado\2018.3\bin
set SRC=D:\HLS\HLS-experiment\lab2_hdmi_loop\vivado_prj\hdmi_loop\hdmi_loop.srcs\sources_1
cd /d "%~dp0"

call "%VIVADO_BIN%\xvlog.bat" --nolog ^
  "%SRC%\imports\hls\rgb2gray\rgb2gray.v" ^
  "%SRC%\imports\hls\rgb2gray\rgb2gray_mac_mulabkb.v" ^
  "%SRC%\imports\hls\gauss3x3\gauss3x3.v" ^
  "%SRC%\imports\hls\gauss3x3\gauss3x3_wlb_lb_vbkb.v" ^
  "%SRC%\imports\hls\gauss3x3\gauss3x3_wlb_lb_vdEe.v" ^
  "%SRC%\new\video_core.v" ^
  "%SRC%\new\video_sync.v" ^
  "sim_stub_sync_fifo_2x4096.v" "tb_core_chain.v"
if errorlevel 1 goto :err

call "%VIVADO_BIN%\xelab.bat" --nolog -s sim_chain --debug off tb_core_chain
if errorlevel 1 goto :err

call "%VIVADO_BIN%\xsim.bat" --nolog sim_chain -R
if errorlevel 1 goto :err
goto :eof

:err
echo.
echo ***** BUILD/SIM FAILED *****
exit /b 1
