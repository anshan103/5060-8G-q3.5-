# ============================================================
#  fetch-tools.ps1
#  下载便携工具链（不需要管理员权限的那些）
#
#  这些源在国内网络实测可用；GitHub 直连不通，故用镜像。
#
#  用法:
#    powershell -ExecutionPolicy Bypass -File fetch-tools.ps1 [-Dest D:\ninfer\tools]
# ============================================================
param(
  [string]$Dest = 'D:\ninfer\tools'
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

function Get-File([string]$url, [string]$out, [string]$name) {
  if (Test-Path $out) {
    $mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Write-Host "  [skip] $name 已存在 ($mb MB)" -ForegroundColor DarkGray
    return $true
  }
  Write-Host "  [get ] $name" -ForegroundColor Cyan
  & curl.exe -sSL --retry 5 --retry-delay 3 --retry-all-errors -o $out $url
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) {
    Write-Host "  [fail] $name" -ForegroundColor Red
    return $false
  }
  Write-Host ("  [ok  ] {0}  {1:N1} MB" -f $name, ((Get-Item $out).Length / 1MB)) -ForegroundColor Green
  return $true
}

Write-Host "目标目录: $Dest" -ForegroundColor Yellow
Write-Host ""

# --- MinGit（便携 git，38 MB，兼容 npmmirror）---
$mingitVer = 'v2.56.0.windows.2'
$mingitZip = Join-Path $Dest 'mingit.zip'
if (Get-File "https://registry.npmmirror.com/-/binary/git-for-windows/$mingitVer/MinGit-2.56.0.2-64-bit.zip" $mingitZip 'MinGit') {
  if (-not (Test-Path (Join-Path $Dest 'git\cmd\git.exe'))) {
    Expand-Archive $mingitZip (Join-Path $Dest 'git') -Force
    Write-Host "  [unzip] git -> $Dest\git" -ForegroundColor Green
  }
}

# --- CMake（便携版，46 MB；VS BuildTools 已含则不需要）---
$cmakeZip = Join-Path $Dest 'cmake.zip'
$vsCmake = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
if (Test-Path $vsCmake) {
  Write-Host "  [skip] CMake（VS BuildTools 自带）" -ForegroundColor DarkGray
} elseif (Get-File 'https://cmake.org/files/v3.31/cmake-3.31.5-windows-x86_64.zip' $cmakeZip 'CMake') {
  if (-not (Test-Path (Join-Path $Dest 'cmake'))) {
    Expand-Archive $cmakeZip (Join-Path $Dest 'cmake') -Force
    Write-Host "  [unzip] cmake -> $Dest\cmake" -ForegroundColor Green
  }
}

# --- Ninja（275 KB，这个源能通）---
$ninjaZip = Join-Path $Dest 'ninja.zip'
if (Get-File 'https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-win.zip' $ninjaZip 'Ninja') {
  if (-not (Test-Path (Join-Path $Dest 'ninja'))) {
    Expand-Archive $ninjaZip (Join-Path $Dest 'ninja') -Force
    Write-Host "  [unzip] ninja -> $Dest\ninja" -ForegroundColor Green
  }
}

# --- 7zr（588 KB，解压 .7z 用）---
Get-File 'https://www.7-zip.org/a/7zr.exe' (Join-Path $Dest '7zr.exe') '7zr' | Out-Null

Write-Host ""
Write-Host "完成。注意：" -ForegroundColor Yellow
Write-Host "  - VS BuildTools（含 MSVC）必须单独安装，需要管理员权限："
Write-Host "      curl.exe -sSL -o vs_BuildTools.exe https://aka.ms/vs/17/release/vs_BuildTools.exe"
Write-Host "      Start-Process .\vs_BuildTools.exe -Wait -ArgumentList '--quiet','--wait','--norestart','--nocache','--add','Microsoft.VisualStudio.Workload.VCTools','--add','Microsoft.VisualStudio.Component.VC.CMake.Project','--includeRecommended'"
