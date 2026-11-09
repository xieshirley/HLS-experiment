@echo off
REM ?? hw_server ? 3270 ???3121 ?? Windows ???????????
set EXE=D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\unwrapped\win64.o\hw_server.exe
tasklist /FI "IMAGENAME eq hw_server.exe" | find /I "hw_server.exe" >nul && (echo hw_server already running) || (
  start "" "%EXE%" -s TCP::3270
  echo started hw_server on 3270
)
timeout /t 3 >nul
netstat -ano | findstr ":3270" | findstr LISTENING