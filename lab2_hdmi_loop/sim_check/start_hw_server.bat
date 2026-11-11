@echo off
REM ============================================================
REM  ?? hw_server ? 3270 ??
REM    * ???? 3121?Windows ?????(???????? 2799-2898/
REM      3026-3125/3346-3445) ???? 3121??? Socket bind error
REM    * ????? hw_server.bat ??????? call setupEnv.bat?
REM      ??? unwrapped\win64.o\hw_server.exe ???????
REM      ?? JTAG ?????targets ???
REM ============================================================
set HS=D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\hw_server.bat
tasklist /FI "IMAGENAME eq hw_server.exe" | find /I "hw_server.exe" >nul
if %errorlevel%==0 (
  echo hw_server already running
) else (
  start "" /min "%HS%" -s TCP::3270
  echo started hw_server on port 3270
)
timeout /t 4 >nul
netstat -ano | findstr ":3270" | findstr LISTENING
echo.
echo Next, in Vivado Tcl Console:
echo    disconnect_hw_server -quiet
echo    connect_hw_server -url localhost:3270
echo    open_hw_target