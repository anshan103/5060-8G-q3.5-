# ============================================================
#  chat-ninfer.ps1  --  和本地 27B 模型对话（交互式）
#  双击桌面「和本地 27B 聊天」即可；也可直接运行。
#
#  命令：/clear 清空上下文    /exit 退出
#
#  注意：PowerShell 5.1 的 Invoke-RestMethod 在响应头没有 charset 时
#        会按 ISO-8859-1 解码，中文会变乱码。所以这里用 Invoke-WebRequest
#        拿原始字节，再显式按 UTF-8 转码。
# ============================================================

# ---- 控制台编码：输入输出都强制 UTF-8 ----
try {
    & chcp.com 65001 > $null
    [Console]::InputEncoding  = [Text.Encoding]::UTF8
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $OutputEncoding = [Text.Encoding]::UTF8
} catch {}
$Host.UI.RawUI.WindowTitle = '本地 27B 模型 · 对话'

$base     = 'http://127.0.0.1:8095'
$model    = 'ninfer-local'
$history  = New-Object System.Collections.ArrayList
$maxTurns = 12

function Test-Api {
    try {
        $r = Invoke-WebRequest "$base/v1/models" -UseBasicParsing -TimeoutSec 3
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Ask-Model([array]$messages) {
    $body = @{
        model      = $model
        messages   = $messages
        max_tokens = 800
        stream     = $false
    } | ConvertTo-Json -Depth 8 -Compress

    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $r = Invoke-WebRequest -Uri "$base/v1/chat/completions" -Method Post `
            -ContentType 'application/json; charset=utf-8' `
            -Body $bytes -UseBasicParsing -TimeoutSec 600

    # 关键：按 UTF-8 解原始字节，绕开 PS 5.1 的默认 ISO-8859-1
    $ms = New-Object System.IO.MemoryStream
    $r.RawContentStream.Position = 0
    $r.RawContentStream.CopyTo($ms)
    $json = [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
    $ms.Dispose()
    return $json
}

Write-Host ''
Write-Host '  ============================================' -ForegroundColor DarkCyan
Write-Host '    本地 27B 模型  (NInfer · RTX 5060 8GB)' -ForegroundColor DarkCyan
Write-Host '  ============================================' -ForegroundColor DarkCyan
Write-Host ''

if (-not (Test-Api)) {
    Write-Host '  服务没在运行。' -ForegroundColor Yellow
    Write-Host '  请先双击桌面上的「本地 27B 模型（NInfer）」，等十几秒再回来。' -ForegroundColor Yellow
    Write-Host ''
    Read-Host '  按回车关闭'
    exit 1
}

Write-Host '  直接打字提问，回车发送。' -ForegroundColor DarkGray
Write-Host '  /clear 清空上下文    /exit 退出' -ForegroundColor DarkGray
Write-Host ''

while ($true) {
    Write-Host '  你 ▸ ' -ForegroundColor Green -NoNewline
    $line = Read-Host
    if ($null -eq $line) { break }
    $line = $line.Trim()
    if ($line -eq '') { continue }

    if ($line -match '^/(exit|quit)$') { Write-Host ''; Write-Host '  再见。' -ForegroundColor DarkGray; return }
    if ($line -match '^/clear$') {
        $history.Clear()
        Write-Host '  上下文已清空。' -ForegroundColor DarkGray
        Write-Host ''
        continue
    }

    [void]$history.Add(@{ role = 'user'; content = $line })
    if ($history.Count -gt $maxTurns * 2) {
        $start = $history.Count - $maxTurns * 2
        $history = New-Object System.Collections.ArrayList (,$history[$start..($history.Count - 1)])
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $json = Ask-Model @($history)
    } catch {
        Write-Host '  请求失败：' -ForegroundColor Red -NoNewline
        Write-Host $_.Exception.Message -ForegroundColor Red
        [void]$history.RemoveAt($history.Count - 1)
        Write-Host ''
        continue
    }
    $sw.Stop()

    $answer = [string]$json.choices[0].message.content
    $answer = $answer.Trim()
    [void]$history.Add(@{ role = 'assistant'; content = $answer })

    $out = [int]$json.usage.completion_tokens
    $tps = if ($sw.Elapsed.TotalSeconds -gt 0) { $out / $sw.Elapsed.TotalSeconds } else { 0 }

    Write-Host ''
    Write-Host '  模型 ▸ ' -ForegroundColor Cyan -NoNewline
    Write-Host $answer
    Write-Host ''
    Write-Host ("  [{0:N1}s · {1} tokens · {2:N1} tok/s]" -f $sw.Elapsed.TotalSeconds, $out, $tps) -ForegroundColor DarkGray
    Write-Host ''
}
