@echo off
REM ============================================================================
REM  prep_sim_dir.bat <目标目录>   —— 一键准备一个干净的仿真目录
REM
REM  为什么需要：
REM    1) 必须用独立目录/独立库名跑 xsim，否则默认 work 库会被旧快照污染
REM       （表现为 xvlog 卡死、或 xelab 命中旧版 tb）
REM    2) HLS 生成的行缓存 BRAM 带"上电初始化"(*_ram.dat)，.dat 不在当前
REM       目录时 xsim 只能给出 X —— 波形里"前两行是红色"多半就是这个原因
REM
REM  用法：
REM      cd sim_check
REM      prep_sim_dir.bat myrun
REM      然后进 myrun 目录，xvlog/xelab/xsim 照常跑
REM ============================================================================
setlocal
if "%~1"=="" (
  echo usage: prep_sim_dir.bat ^<target_dir^>
  exit /b 1
)

set SIM=%~dp0
set PRJ=%SIM%..\vivado_prj\hdmi_loop\hdmi_loop.srcs\sources_1
set IMP=%PRJ%\imports\hls
set DST=%SIM%%~1

if not exist "%DST%" mkdir "%DST%"

echo --- copy handwritten RTL ---
copy /Y "%PRJ%\new\video_core.v"      "%DST%" >nul
copy /Y "%PRJ%\new\video_sync.v"      "%DST%" >nul
copy /Y "%PRJ%\new\key_mode.v"        "%DST%" >nul
echo --- copy HLS generated RTL + BRAM init (.dat) ---
for %%d in (rgb2gray gauss3x3 unsharp3x3) do (
  if exist "%IMP%\%%d" copy /Y "%IMP%\%%d\*" "%DST%" >nul
)
echo --- copy testbenches ---
copy /Y "%SIM%tb_*.v" "%DST%" >nul

echo.
echo prepared: %DST%
dir /b "%DST%\*.dat" 2>nul | find /C ".dat" >nul && (
  echo   .dat files: OK
) || (
  echo   [WARN] no .dat copied -- kernel line-buffer BRAMs will be X in simulation
)
echo.
echo now run:
echo   cd %DST%
echo   xvlog ^<your_tb^>.v video_core.v video_sync.v rgb2gray.v rgb2gray_mac_mulabkb.v ^
echo          gauss3x3.v gauss3x3_wlb_lb_vbkb.v gauss3x3_wlb_lb_vdEe.v ^
echo          unsharp3x3.v unsharp3x3_wlb_lbbkb.v unsharp3x3_wlb_lbdEe.v
echo   xelab ^<your_tb^> -s snap1
echo   xsim snap1 -R
endlocal
