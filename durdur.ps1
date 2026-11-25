# BitChord parti sunucusunu ve tuneli durdurur (yalnizca bu klasorun surecleri).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$runDir = Join-Path $here "run"
$stopFlag = Join-Path $runDir "stop.flag"
$watchdogPidF = Join-Path $runDir "watchdog.pid"
$tunnelPidF = Join-Path $runDir "tunnel.pid"
$serverPidF = Join-Path $runDir "server.pid"

$stoppedAny = $false

# 1) Watchdog varsa once temiz cikis sinyali gonder
if (Test-Path -LiteralPath $watchdogPidF) {
    $raw = (Get-Content -LiteralPath $watchdogPidF -Raw -ErrorAction SilentlyContinue)
    if ($raw) { $raw = $raw.Trim() }
    $wdId = 0
    if ([int]::TryParse($raw, [ref]$wdId) -and $wdId -gt 0 -and $wdId -ne $PID) {
        $wdProc = Get-Process -Id $wdId -ErrorAction SilentlyContinue
        if ($wdProc -and (@("powershell", "pwsh") -contains $wdProc.ProcessName.ToLowerInvariant())) {
            if (-not (Test-Path -LiteralPath $runDir)) { New-Item -ItemType Directory -Path $runDir | Out-Null }
            New-Item -ItemType File -Path $stopFlag -Force | Out-Null
            $stoppedAny = $true
            for ($i = 0; $i -lt 10; $i++) {
                if ($wdProc.HasExited) { break }
                Start-Sleep -Milliseconds 250
            }
            if (-not $wdProc.HasExited) {
                Stop-Process -Id $wdId -Force -ErrorAction SilentlyContinue
                try { $null = $wdProc.WaitForExit(1500) } catch { }
            }
        }
    }
    Remove-Item -LiteralPath $watchdogPidF -Force -ErrorAction SilentlyContinue
}

# 2) Kalan PID dosyalarini guvenli sekilde durdur
$pidTargets = @(
    @{ File = $tunnelPidF; Names = @("cloudflared") },
    @{ File = $serverPidF; Names = @("bitchord-jam") }
)
foreach ($t in $pidTargets) {
    if (Test-Path -LiteralPath $t.File) {
        $raw = (Get-Content -LiteralPath $t.File -Raw -ErrorAction SilentlyContinue)
        if ($raw) { $raw = $raw.Trim() }
        $procId = 0
        if ([int]::TryParse($raw, [ref]$procId) -and $procId -gt 0) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($p -and ($t.Names -contains $p.ProcessName.ToLowerInvariant())) {
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                try { $null = $p.WaitForExit(1500) } catch { }
                $stoppedAny = $true
            }
        }
        Remove-Item -LiteralPath $t.File -Force -ErrorAction SilentlyContinue
    }
}

# 3) Yalnizca bu klasordeki exe yolundan baslatilan surecleri temizle
$ownedPaths = @(
    [System.IO.Path]::GetFullPath((Join-Path $here "bitchord-jam.exe")),
    [System.IO.Path]::GetFullPath((Join-Path $here "cloudflared.exe"))
)
try {
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'bitchord-jam.exe' OR Name = 'cloudflared.exe'" -ErrorAction Stop
    foreach ($p in $procs) {
        if (-not $p.ExecutablePath) { continue }
        foreach ($op in $ownedPaths) {
            if ($p.ExecutablePath.Equals($op, [System.StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
                $stoppedAny = $true
                break
            }
        }
    }
} catch { }

if (Test-Path -LiteralPath $stopFlag) {
    Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue
}

if ($stoppedAny) {
    Write-Host "Parti sunucusu ve tunel durduruldu." -ForegroundColor Green
} else {
    Write-Host "Calisan bir sunucu bulunamadi." -ForegroundColor Yellow
}
