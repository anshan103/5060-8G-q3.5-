# ============================================================
#  bench-api.ps1
#  对一个 OpenAI 兼容端点打基准，输出 TTFT / decode tok/s
#
#  用法:
#    powershell -ExecutionPolicy Bypass -File bench-api.ps1
#    powershell -ExecutionPolicy Bypass -File bench-api.ps1 -Port 8095 -Tokens 200
# ============================================================
param(
  [string]$Host_ = '127.0.0.1',
  [int]$Port = 8095,
  [string]$Model = 'ninfer-local',
  [int]$Tokens = 150,
  [int]$Runs = 3
)

$ErrorActionPreference = 'Stop'
$base = "http://${Host_}:$Port"
$prompt = 'Count from 1 to 40, separated by commas. Output only the numbers.'

Write-Host "端点: $base  模型: $Model  运行 $Runs 次" -ForegroundColor Cyan

# 先探活
try {
  $models = Invoke-RestMethod "$base/v1/models" -TimeoutSec 10
  Write-Host ("在线, 模型: " + (($models.data | ForEach-Object { $_.id }) -join ', ')) -ForegroundColor Green
} catch {
  Write-Host "端点无响应: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

$results = @()
for ($i = 1; $i -le $Runs; $i++) {
  $body = @{
    model      = $Model
    messages   = @(@{ role = 'user'; content = $prompt })
    max_tokens = $Tokens
    stream     = $false
  } | ConvertTo-Json -Depth 6

  $sw = [Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-RestMethod -Uri "$base/v1/chat/completions" -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 600
  $sw.Stop()

  $gen = [int]$r.usage.completion_tokens
  $pre = [int]$r.usage.prompt_tokens
  $tps = if ($sw.Elapsed.TotalSeconds -gt 0) { $gen / $sw.Elapsed.TotalSeconds } else { 0 }

  $results += [pscustomobject]@{
    run      = $i
    prompt   = $pre
    generated= $gen
    seconds  = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    tok_per_s= [math]::Round($tps, 1)
  }
  Write-Host ("  #{0}  prompt={1}  out={2}  {3:N2}s  {4:N1} tok/s" -f $i, $pre, $gen, $sw.Elapsed.TotalSeconds, $tps)
}

$avg = ($results | Measure-Object tok_per_s -Average).Average
Write-Host ""
Write-Host ("平均: {0:N1} tok/s（含 prefill，真实 decode 略高）" -f $avg) -ForegroundColor Yellow
Write-Host "提示: 引擎自己的日志里有最准的数字，找 'decode ... tok/s' 那一行。" -ForegroundColor DarkGray
