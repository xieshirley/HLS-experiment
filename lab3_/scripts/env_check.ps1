# env_check.ps1 —— 实验三环境自检（在 lab3_ 目录运行：pwsh scripts\env_check.ps1）
# 输出全绿 = S1 通过。仅做检查，不改工程。

$ErrorActionPreference = 'Continue'
$VIVADO = 'D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\vivado.bat'
$LOADER = 'D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\loader.bat'
$VENV   = 'D:\HLS\HLS-experiment\lab3_\.venv\Scripts\python.exe'
$PART   = 'xc7a35tfgg484-2'

Write-Output '================ env_check ================'
Write-Output ('[1] Vivado bat exists : ' + (Test-Path $VIVADO))
Write-Output ('[2] HLS loader exists : ' + (Test-Path $LOADER))

# Vivado version
$v = & $VIVADO -version 2>&1 | Select-Object -First 1
Write-Output ("[3] Vivado version    : " + $v)

# HLS version (loader.bat, no tee path)
$h = cmd /c "`"$LOADER`" -exec vivado_hls -version 2>&1" | Select-Object -First 2
Write-Output ("[4] HLS version       : " + ($h -join ' | '))

# venv python
Write-Output ('[5] venv python exists: ' + (Test-Path $VENV))
if (Test-Path $VENV) {
  $pv = & $VENV -V 2>&1
  Write-Output ("    venv python ver   : " + $pv)
  $pkgs = & $VENV -m pip list --format=freeze 2>&1 | Out-String
  foreach ($p in 'torch','numpy','matplotlib','pyserial','pillow') {
    $hit = ($pkgs -split "`n") | Where-Object { $_ -like "$p==*" } | Select-Object -First 1
    Write-Output ("    pkg $p            : " + $(if($hit){$hit.Trim()}else{'MISSING'}))
  }
}

# serial ports
$coms = Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DeviceID
Write-Output ("[6] serial COM ports  : " + $(if($coms){($coms -join ', ')}else{'NONE (board not plugged)'}))

# pypi
try {
  $t = Test-NetConnection -ComputerName pypi.org -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
  if ($null -eq $t) { $t = Test-Connection pypi.org -Count 1 -Quiet }
  Write-Output ("[7] pypi reachable    : " + $t)
} catch { Write-Output '[7] pypi reachable    : ERROR' }

Write-Output '================ end ================'
