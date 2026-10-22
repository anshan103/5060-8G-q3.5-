# ============================================================
#  check-env.ps1
#  采集本机环境，生成可对比的报告（用于判断能不能跑某个引擎）
#
#  用法:
#    powershell -ExecutionPolicy Bypass -File check-env.ps1 [-Out report.txt]
# ============================================================
param(
  [string]$Out = ''
)

$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]

function Add-Line([string]$t = '') { $lines.Add($t) }
function Section([string]$t) { Add-Line ''; Add-Line "## $t" }

Add-Line "# 环境报告"
Add-Line ("生成时间: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

Section 'CPU'
try {
  $cpu = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop).ProcessorNameString
  Add-Line ("型号: " + $cpu.Trim())
} catch { Add-Line '型号: 读取失败' }
Add-Line ("逻辑核心: " + $env:NUMBER_OF_PROCESSORS)

Section 'GPU / 驱动'
$smi = "$env:SystemRoot\System32\nvidia-smi.exe"
if (Test-Path $smi) {
  & $smi --query-gpu=index,name,driver_version,memory.total,compute_cap --format=csv,noheader 2>&1 |
    ForEach-Object { Add-Line $_ }
  $ver = & $smi 2>&1 | Select-String -Pattern 'CUDA Version' | Select-Object -First 1
  if ($ver) { Add-Line ('CUDA UMD: ' + $ver.ToString().Trim()) }
} else {
  Add-Line 'nvidia-smi 不存在（非 NVIDIA 或未装驱动）'
}

Section '内存'
try {
  $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
  Add-Line ('物理内存: {0:N1} GB' -f ($os.TotalVisibleMemorySize / 1MB))
  Add-Line ('可用: {0:N1} GB' -f ($os.FreePhysicalMemory / 1MB))
} catch { Add-Line '读取失败' }

Section '系统'
try {
  $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
  Add-Line ("产品名: " + $cv.ProductName)
  Add-Line ("Build: " + $cv.CurrentBuild)
  Add-Line ("显示版本: " + $cv.DisplayVersion)
} catch { Add-Line '读取失败' }
Add-Line ("架构: " + $env:PROCESSOR_ARCHITECTURE)

Section '构建工具链'
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
  $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>&1
  if ($vsPath) {
    Add-Line ('MSVC: ' + $vsPath)
    $m = Get-ChildItem "$vsPath\VC\Tools\MSVC" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($m) { Add-Line ('MSVC 版本: ' + $m.Name) }
    $cm = "$vsPath\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    if (Test-Path $cm) { Add-Line ('CMake(VS): ' + ((& $cm --version 2>&1) | Select-Object -First 1)) }
    $ninja = "$vsPath\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
    if (Test-Path $ninja) { Add-Line ('Ninja(VS): 存在') }
  } else {
    Add-Line 'VS 已装但缺 C++ 工具链'
  }
} else {
  Add-Line 'MSVC: 未安装'
}
Add-Line ('CMake(PATH): ' + $(if (Get-Command cmake -ErrorAction SilentlyContinue) { (Get-Command cmake).Source } else { '无' }))
Add-Line ('Ninja(PATH): ' + $(if (Get-Command ninja -ErrorAction SilentlyContinue) { (Get-Command ninja).Source } else { '无' }))
Add-Line ('Git:         ' + $(if (Get-Command git -ErrorAction SilentlyContinue) { (Get-Command git).Source } else { '无' }))
Add-Line ('CUDA_PATH:   ' + $(if ($env:CUDA_PATH) { $env:CUDA_PATH } else { '无' }))

Section '推理运行时'
$ollama = 'C:\Users\' + $env:USERNAME + '\AppData\Local\Programs\Ollama\ollama.exe'
if (Test-Path $ollama) {
  Add-Line ('Ollama: ' + ((& $ollama --version 2>&1) | Select-Object -First 1))
  try {
    $ps = Invoke-RestMethod 'http://127.0.0.1:11434/api/ps' -TimeoutSec 5 -ErrorAction Stop
    $names = @($ps.models | ForEach-Object { $_.name }) -join ', '
    Add-Line ('Ollama 已加载: ' + $(if ($names) { $names } else { '无' }))
  } catch { Add-Line 'Ollama 服务未响应' }
} else {
  Add-Line 'Ollama: 未安装'
}

Section '推理服务端口探测'
foreach ($port in 8080, 8090, 8091, 8095) {
  try {
    $r = Invoke-WebRequest "http://127.0.0.1:$port/v1/models" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    Add-Line ("端口 $port : HTTP $($r.StatusCode)  $($r.Content.Substring(0, [Math]::Min(100, $r.Content.Length)))")
  } catch {
    Add-Line ("端口 $port : 无响应")
  }
}

Section '磁盘'
[IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | ForEach-Object {
  Add-Line ("{0} 剩余 {1,7:N1} GB / 共 {2,7:N1} GB  ({3})" -f $_.Name, ($_.AvailableFreeSpace/1GB), ($_.TotalSize/1GB), $_.DriveFormat)
}

$text = $lines -join "`r`n"
if ($Out) {
  $text | Set-Content -LiteralPath $Out -Encoding UTF8
  Write-Host "报告已写入: $Out"
} else {
  Write-Host $text
}
