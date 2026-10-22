# ============================================================
#  stop-ninfer.ps1  --  停止本地 27B 模型，释放显存与固定内存
#  由桌面快捷方式调用；也可直接运行。
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = '停止本地 27B 模型'

$procs = @(Get-Process -Name 'ninfer-serve-120a' -ErrorAction SilentlyContinue)

if ($procs.Count -eq 0) {
    Write-Host ''
    Write-Host '  本地 27B 模型本来就没在运行。' -ForegroundColor Yellow
    Write-Host ''
    Start-Sleep -Seconds 2
    exit 0
}

$before = 0
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $line = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
    if ($line) { $before = [int]$line }
}

Write-Host ''
Write-Host ("  正在停止 {0} 个引擎进程..." -f $procs.Count) -ForegroundColor Cyan
foreach ($p in $procs) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {}
}

# 等它真正退出
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 250
    if (-not (Get-Process -Name 'ninfer-serve-120a' -ErrorAction SilentlyContinue)) { break }
}

$left = @(Get-Process -Name 'ninfer-serve-120a' -ErrorAction SilentlyContinue).Count
if ($left -gt 0) {
    Write-Host ("  还有 {0} 个进程没退出，可能需要管理员权限。" -f $left) -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit 1
}

Start-Sleep -Milliseconds 800
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $after = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
    if ($after) {
        $freed = [int]$before - [int]$after
        Write-Host ("  已停止。显存 {0} MiB -> {1} MiB（释放 {2} MiB）" -f $before, [int]$after, $freed) -ForegroundColor Green
    } else {
        Write-Host '  已停止。' -ForegroundColor Green
    }
} else {
    Write-Host '  已停止。' -ForegroundColor Green
}
Write-Host ''
Start-Sleep -Seconds 2
exit 0
