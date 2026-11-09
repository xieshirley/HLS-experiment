@echo off
setlocal
set VIVADO_BIN=D:\software\vivado18_3\systemfile\Vivado\2018.3\bin
set PRJ=D:\HLS\HLS-experiment\lab2_hdmi_loop\vivado_prj\hdmi_loop\hdmi_loop.srcs\sources_1
cd /d "%~dp0"
call "%VIVADO_BIN%\xvlog.bat" --nolog "%PRJ%\imports\53_hdmi_loop\rtl\hdmi_loop.v" "%PRJ%\new\video_core.v" "%PRJ%\new\video_sync.v"
echo EXITCODE=%errorlevel%
