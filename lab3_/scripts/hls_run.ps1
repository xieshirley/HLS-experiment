# hls_run.ps1 —— 实验三 HLS 统一调用封装
# 用法（必须在完全权限/非沙箱下运行，见 AGENTS.md）：
#   pwsh scripts\hls_run.ps1 -Tcl hls\nn_accel\run_hls.tcl
# 输出 tee 到 logs\hls_run.log 并返回退出码。

param(
  [Parameter(Mandatory=$true)][string]$Tcl
)

$LOADER = 'D:\software\vivado18_3\systemfile\Vivado\2018.3\bin\loader.bat'
$logdir = Join-Path $PSScriptRoot '..\logs'
New-Item -ItemType Directory -Force -Path $logdir | Out-Null
$log = Join-Path $logdir 'hls_run.log'

# 切到 tcl 所在目录（脚本里用相对路径 add_files）
$tclFull = $Tcl
if (Test-Path -LiteralPath $Tcl) { $tclFull = (Resolve-Path -LiteralPath $Tcl).Path }
$tclDir = [System.IO.Path]::GetDirectoryName($tclFull)
if (-not $tclDir) {
  Write-Error ("无法从 '" + $Tcl + "' 推导目录，请传绝对路径或用 -WorkDir")
  exit 2
}
Set-Location $tclDir
$tclName = [System.IO.Path]::GetFileName($tclFull)

Write-Output ("[hls_run] tcl    = " + $tclFull)
Write-Output ("[hls_run] dir    = " + $tclDir)
Write-Output ("[hls_run] script = " + $tclName)
Write-Output ("[hls_run] log    = " + $log)

$cmd = "`"$LOADER`" -exec vivado_hls -f `"$tclName`""
$out = cmd /c "$cmd 2>&1"
$code = $LASTEXITCODE

# 打印尾部关键行 + 全量落盘
$out | Set-Content -Path $log -Encoding UTF8
$out | Select-Object -Last 40
Write-Output ("[hls_run] exit code = " + $code)
exit $code
