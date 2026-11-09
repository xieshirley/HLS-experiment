@echo off
setlocal
REM run_shift.bat -- 同步只打 1 拍 错位复现（报告 错位复现-理论对照）
set VIVADO_BIN=D:\software\vivado18_3\systemfile\Vivado\2018.3\bin
cd /d "%~dp0"
call "%VIVADO_BIN%\xvlog.bat" --nolog "tb_shift_demo.v"
if errorlevel 1 goto :err
call "%VIVADO_BIN%\xelab.bat" --nolog -s sim_shift --debug off tb_shift_demo
if errorlevel 1 goto :err
call "%VIVADO_BIN%\xsim.bat" --nolog sim_shift -R
if errorlevel 1 goto :err
goto :eof
:err
echo.
echo ***** BUILD/SIM FAILED *****
exit /b 1