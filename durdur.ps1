# BitChord parti sunucusunu ve tuneli durdurur.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$runDir = Join-Path $here "run"

foreach ($f in @("tunnel.pid", "server.pid")) {
    $p = Join-Path $runDir $f
    if (Test-Path $p) {
        $procId = (Get-Content $p -Raw -ErrorAction SilentlyContinue)
        if ($procId) { $procId = $procId.Trim() }
        if ($procId) { & taskkill /F /PID $procId 2>$null | Out-Null }
        Remove-Item $p -Force -ErrorAction SilentlyContinue
    }
}

# PID dosyasi kalmadiysa isimden temizle
& taskkill /F /IM bitchord-jam.exe 2>$null | Out-Null
& taskkill /F /IM cloudflared.exe 2>$null | Out-Null

Write-Host "Parti sunucusu ve tunel durduruldu." -ForegroundColor Green
