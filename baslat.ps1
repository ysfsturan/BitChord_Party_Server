# BitChord Listen Together - yerel parti sunucusu + HTTPS tunel
# Tek pencere. Baslatmak icin baslat.bat dosyasina cift tikla.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

# ---------- AYARLAR ----------
if (-not $env:PORT)                   { $env:PORT = "8000" }
if (-not $env:JAM_MAX_MEMBERS)        { $env:JAM_MAX_MEMBERS = "10" }      # parti basina cihaz (2-10)
if (-not $env:JAM_MAX_PARTIES)        { $env:JAM_MAX_PARTIES = "50" }      # eszamanli parti
if (-not $env:JAM_MAX_UPCOMING_QUEUE) { $env:JAM_MAX_UPCOMING_QUEUE = "25" }
if (-not $env:JAM_TRUST_PROXY)        { $env:JAM_TRUST_PROXY = "true" }    # Cloudflare arkasinda gercek IP icin

# Sabit adres (named tunnel) icin ikisini doldur; bos birakirsan gecici trycloudflare.com adresi acilir:
$tunnelName = ""    # ornek: "bitchord-parti"
$publicUrl  = ""    # ornek: "https://parti.alanadin.com"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$runDir       = Join-Path $here "run"
$serverExe    = Join-Path $here "bitchord-jam.exe"
$cfExe        = Join-Path $here "cloudflared.exe"
$watchdogPidF = Join-Path $runDir "watchdog.pid"
$serverPidF   = Join-Path $runDir "server.pid"
$tunnelPidF   = Join-Path $runDir "tunnel.pid"
$stopFlag     = Join-Path $runDir "stop.flag"
$serverOutLog = Join-Path $runDir "server.out.log"
$serverErrLog = Join-Path $runDir "server.err.log"
$cfOutLog     = Join-Path $runDir "tunnel.out.log"
$cfLog        = Join-Path $runDir "tunnel.log"

$script:serverProc = $null
$script:tunnelProc = $null

if (-not (Test-Path -LiteralPath $runDir)) { New-Item -ItemType Directory -Path $runDir | Out-Null }

function Wait-Exit {
    if ((-not [Console]::IsInputRedirected) -and [Environment]::UserInteractive) {
        Read-Host "Kapatmak icin Enter" | Out-Null
    }
}

function Test-ValidExe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.Length -le 1000000) { return $false }
        $fs = [System.IO.File]::OpenRead($item.FullName)
        try {
            $buf = New-Object byte[] 2
            $read = $fs.Read($buf, 0, 2)
            return ($read -eq 2 -and $buf[0] -eq 0x4D -and $buf[1] -eq 0x5A)
        } finally {
            $fs.Dispose()
        }
    } catch {
        return $false
    }
}

function Read-SharedText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
            try {
                return $sr.ReadToEnd()
            } finally {
                $sr.Dispose()
            }
        } finally {
            $fs.Dispose()
        }
    } catch {
        return ""
    }
}

function Get-LogTail {
    param([string]$Path, [int]$Lines = 5)
    $txt = Read-SharedText -Path $Path
    if (-not $txt) { return @() }
    $arr = $txt -split "`r?`n" | Where-Object { $_.Trim() -ne "" }
    if ($arr.Count -le $Lines) { return $arr }
    return $arr[($arr.Count - $Lines)..($arr.Count - 1)]
}

function Stop-PidSafe {
    param([string]$PidFile, [string[]]$ExpectedNames)
    if (-not (Test-Path -LiteralPath $PidFile)) { return }
    $raw = (Get-Content -LiteralPath $PidFile -Raw -ErrorAction SilentlyContinue)
    if ($raw) { $raw = $raw.Trim() }
    $procId = 0
    if ([int]::TryParse($raw, [ref]$procId) -and $procId -gt 0 -and $procId -ne $PID) {
        $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($p -and ($ExpectedNames -contains $p.ProcessName.ToLowerInvariant())) {
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            try { $null = $p.WaitForExit(2000) } catch { }
        }
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

function Stop-OwnedByPath {
    $targets = @(
        [System.IO.Path]::GetFullPath($serverExe),
        [System.IO.Path]::GetFullPath($cfExe)
    )
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = 'bitchord-jam.exe' OR Name = 'cloudflared.exe'" -ErrorAction Stop
        foreach ($p in $procs) {
            if (-not $p.ExecutablePath) { continue }
            foreach ($t in $targets) {
                if ($p.ExecutablePath.Equals($t, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
                    break
                }
            }
        }
    } catch { }
}

function Stop-PreviousWatchdog {
    if (-not (Test-Path -LiteralPath $watchdogPidF)) { return }
    $raw = (Get-Content -LiteralPath $watchdogPidF -Raw -ErrorAction SilentlyContinue)
    if ($raw) { $raw = $raw.Trim() }
    $oldId = 0
    if ([int]::TryParse($raw, [ref]$oldId) -and $oldId -gt 0 -and $oldId -ne $PID) {
        $oldProc = Get-Process -Id $oldId -ErrorAction SilentlyContinue
        if ($oldProc -and (@("powershell", "pwsh") -contains $oldProc.ProcessName.ToLowerInvariant())) {
            New-Item -ItemType File -Path $stopFlag -Force | Out-Null
            $null = $oldProc.WaitForExit(2500)
            if (-not $oldProc.HasExited) {
                Stop-Process -Id $oldId -Force -ErrorAction SilentlyContinue
                try { $null = $oldProc.WaitForExit(1500) } catch { }
            }
        }
    }
    Remove-Item -LiteralPath $watchdogPidF -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue
}

function Stop-All {
    if ($script:tunnelProc) {
        try {
            if (-not $script:tunnelProc.HasExited) {
                Stop-Process -Id $script:tunnelProc.Id -Force -ErrorAction SilentlyContinue
                $null = $script:tunnelProc.WaitForExit(1500)
            }
        } catch { }
        $script:tunnelProc = $null
    }
    if ($script:serverProc) {
        try {
            if (-not $script:serverProc.HasExited) {
                Stop-Process -Id $script:serverProc.Id -Force -ErrorAction SilentlyContinue
                $null = $script:serverProc.WaitForExit(1500)
            }
        } catch { }
        $script:serverProc = $null
    }
    Stop-PidSafe -PidFile $tunnelPidF -ExpectedNames @("cloudflared")
    Stop-PidSafe -PidFile $serverPidF -ExpectedNames @("bitchord-jam")
    Stop-OwnedByPath

    if (Test-Path -LiteralPath $watchdogPidF) {
        $cur = (Get-Content -LiteralPath $watchdogPidF -Raw -ErrorAction SilentlyContinue)
        if ($cur -and $cur.Trim() -eq [string]$PID) {
            Remove-Item -LiteralPath $watchdogPidF -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ListeningPortOwner {
    param([int]$Port)
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($conn) { return [int]$conn.OwningProcess }
    } catch {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $iar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(200) -and $tcp.Connected) {
                return -1
            }
        } catch {
        } finally {
            $tcp.Close()
        }
    }
    return $null
}

function Test-Health {
    param([string]$BaseUrl)
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/healthz" -UseBasicParsing -TimeoutSec 4 -Headers @{ "Cache-Control" = "no-cache" } -ErrorAction Stop
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Start-Server {
    foreach ($f in @($serverOutLog, $serverErrLog)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    $p = Start-Process -FilePath $serverExe -WorkingDirectory $here -NoNewWindow -RedirectStandardOutput $serverOutLog -RedirectStandardError $serverErrLog -PassThru
    Set-Content -LiteralPath $serverPidF -Value $p.Id -Encoding ASCII
    return $p
}

function Start-Tunnel {
    foreach ($f in @($cfOutLog, $cfLog)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    if ($tunnelName) {
        $cfArgs = @("tunnel", "--no-autoupdate", "run", $tunnelName)
    } else {
        $cfArgs = @("tunnel", "--url", "http://127.0.0.1:$port", "--no-autoupdate")
    }
    $p = Start-Process -FilePath $cfExe -ArgumentList $cfArgs -WorkingDirectory $here -NoNewWindow -RedirectStandardOutput $cfOutLog -RedirectStandardError $cfLog -PassThru
    Set-Content -LiteralPath $tunnelPidF -Value $p.Id -Encoding ASCII
    return $p
}

function Wait-Local {
    param([System.Diagnostics.Process]$Proc)
    for ($i = 0; $i -lt 30; $i++) {
        if ($Proc -and $Proc.HasExited) { return $false }
        Start-Sleep -Milliseconds 400
        if ($Proc -and $Proc.HasExited) { return $false }
        if (Test-Health -BaseUrl "http://127.0.0.1:$port") { return $true }
    }
    return $false
}

function Read-TunnelUrl {
    param([System.Diagnostics.Process]$Proc)
    if ($tunnelName) {
        for ($i = 0; $i -lt 5; $i++) {
            if ($Proc -and $Proc.HasExited) { return $null }
            Start-Sleep -Milliseconds 400
        }
        if ($Proc -and $Proc.HasExited) { return $null }
        return $publicUrl
    }
    for ($i = 0; $i -lt 60; $i++) {
        if ($Proc -and $Proc.HasExited) { return $null }
        Start-Sleep -Milliseconds 400
        if ($Proc -and $Proc.HasExited) { return $null }
        $txt = Read-SharedText -Path $cfLog
        if ($txt -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") { return $Matches[0] }
    }
    return $null
}

function Show-Banner {
    param([string]$Url)
    Write-Host ""
    Write-Host "  ==============================================" -ForegroundColor Green
    if ($Url) {
        Write-Host "   SUNUCU ADRESI (uygulamaya bunu gir):" -ForegroundColor White
        Write-Host ""
        Write-Host "   $Url" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  ==============================================" -ForegroundColor Green
        try {
            Set-Clipboard -Value $Url -ErrorAction Stop
            Write-Host "  Adres panoya kopyalandi." -ForegroundColor DarkGray
        } catch { }
    } else {
        Write-Host "   SABIT TUNEL BASLATILDI ($tunnelName)" -ForegroundColor White
        Write-Host ""
        Write-Host "   Uygulamaya kendi domain adresini gir (https://...)." -ForegroundColor Yellow
        Write-Host "   Not: baslat.ps1 icinde `$publicUrl ayarlarsan otomatik gosterilir." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  ==============================================" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  BitChord > Ayarlar > Listen Together" -ForegroundColor Gray
    Write-Host "  Parti olustur -> 6 haneli kodu arkadaslarina gonder." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Kapatmak icin: Ctrl+C, Q veya durdur.bat" -ForegroundColor DarkGray
    Write-Host ""
}

function Wait-WatchdogTick {
    for ($i = 0; $i -lt 10; $i++) {
        if (Test-Path -LiteralPath $stopFlag) { return "stop" }
        if ((-not [Console]::IsInputRedirected) -and [Environment]::UserInteractive) {
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ((($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C)) -or ($k.Key -eq [ConsoleKey]::Q)) {
                    return "stop"
                }
            }
        }
        Start-Sleep -Milliseconds 200
    }
    return "continue"
}

Write-Host ""
Write-Host "  ==============================================" -ForegroundColor DarkCyan
Write-Host "        BitChord - Parti Sunucusu" -ForegroundColor Cyan
Write-Host "  ==============================================" -ForegroundColor DarkCyan
Write-Host ""

# ---------- DOGRULAMA ----------
$port = 0
if (-not [int]::TryParse($env:PORT.Trim(), [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
    Write-Host "  HATA: Gecersiz PORT degeri ('$($env:PORT)'). 1-65535 arasi olmali." -ForegroundColor Red
    Wait-Exit; exit 1
}

$maxMembers = 0
if ([int]::TryParse($env:JAM_MAX_MEMBERS.Trim(), [ref]$maxMembers)) {
    if ($maxMembers -lt 2 -or $maxMembers -gt 10) {
        Write-Host "  UYARI: JAM_MAX_MEMBERS ($maxMembers) 2-10 disinda; sunucu varsayilan 5 kullanacak." -ForegroundColor Yellow
    }
} else {
    Write-Host "  UYARI: Gecersiz JAM_MAX_MEMBERS ('$($env:JAM_MAX_MEMBERS)'); sunucu varsayilan 5 kullanacak." -ForegroundColor Yellow
}

$tunnelName = $tunnelName.Trim()
$publicUrl = $publicUrl.Trim().TrimEnd("/")
if ($tunnelName -and $publicUrl) {
    $env:JAM_PUBLIC_ORIGIN = $publicUrl
}

if (-not (Test-ValidExe $serverExe)) {
    Write-Host "  HATA: bitchord-jam.exe bulunamadi veya bozuk. Once kur.bat calistir." -ForegroundColor Red
    Wait-Exit; exit 1
}
if (-not (Test-ValidExe $cfExe)) {
    Write-Host "  HATA: cloudflared.exe bulunamadi veya bozuk. Once kur.bat calistir." -ForegroundColor Red
    Wait-Exit; exit 1
}

Stop-PreviousWatchdog
Stop-All

$busyOwner = Get-ListeningPortOwner -Port $port
if ($null -ne $busyOwner) {
    $ownerInfo = if ($busyOwner -gt 0) { " (PID: $busyOwner)" } else { "" }
    Write-Host "  HATA: $port portu baska bir program tarafindan kullaniliyor$ownerInfo." -ForegroundColor Red
    Write-Host "  Cozum: Once diger sunucuyu kapat veya baslat.ps1 icinden PORT ayarini degistir." -ForegroundColor Yellow
    Wait-Exit; exit 1
}

Set-Content -LiteralPath $watchdogPidF -Value $PID -Encoding ASCII

$origTreatCtrlC = $false
$hasConsoleInput = (-not [Console]::IsInputRedirected) -and [Environment]::UserInteractive
if ($hasConsoleInput) {
    $origTreatCtrlC = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true
}

try {
    # ---------- 1. SUNUCU ----------
    Write-Host "  [1/2] Sunucu baslatiliyor (port $port)..." -ForegroundColor Gray
    $script:serverProc = Start-Server
    $serverStartedAt = [DateTime]::UtcNow
    if (-not (Wait-Local -Proc $script:serverProc)) {
        Write-Host "  HATA: Sunucu baslamadi (port $port)." -ForegroundColor Red
        foreach ($line in (Get-LogTail -Path $serverErrLog)) { Write-Host "    $line" -ForegroundColor DarkGray }
        Stop-All
        Wait-Exit; exit 1
    }

    # ---------- 2. TUNEL ----------
    Write-Host "  [2/2] HTTPS tuneli aciliyor..." -ForegroundColor Gray
    $script:tunnelProc = Start-Tunnel
    $tunnelStartedAt = [DateTime]::UtcNow
    $url = Read-TunnelUrl -Proc $script:tunnelProc
    if ($null -eq $url) {
        Write-Host "  HATA: Tunel acilamadi. Internet baglantisini veya Cloudflare erisimini kontrol et." -ForegroundColor Red
        foreach ($line in (Get-LogTail -Path $cfLog)) { Write-Host "    $line" -ForegroundColor DarkGray }
        Write-Host "  Detay: $cfLog" -ForegroundColor DarkGray
        Stop-All
        Wait-Exit; exit 1
    }

    Show-Banner -Url $url
    if ($url) {
        Write-Host "  Adres dogrulaniyor..." -ForegroundColor DarkGray
        $verified = $false
        $verifyStart = [DateTime]::UtcNow
    } else {
        $verified = $true
    }

    # ---------- BEKCI ----------
    $serverRestarts = 0
    $tunnelRestarts = 0
    while ($true) {
        if ((Wait-WatchdogTick) -eq "stop") { break }

        if (-not $verified) {
            if (Test-Health -BaseUrl $url) {
                $verified = $true
                Write-Host "  Hazir. Arkadaslarin adresi girebilir." -ForegroundColor Green
                Write-Host ""
            } elseif (([DateTime]::UtcNow - $verifyStart) -ge [TimeSpan]::FromSeconds(120)) {
                Write-Host "  UYARI: Adres 2 dakikadir cevap vermiyor. Cloudflare tarafinda gecikme olabilir." -ForegroundColor Yellow
                Write-Host ""
                $verified = $true
            }
        }

        if ($script:serverProc.HasExited) {
            if (([DateTime]::UtcNow - $serverStartedAt) -ge [TimeSpan]::FromMinutes(5)) {
                $serverRestarts = 0
            }
            if ($serverRestarts -lt 5) {
                $serverRestarts++
                Write-Host "  Sunucu kapandi, yeniden baslatiliyor ($serverRestarts/5)..." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                $script:serverProc = Start-Server
                $serverStartedAt = [DateTime]::UtcNow
                if (Wait-Local -Proc $script:serverProc) {
                    Write-Host "  Sunucu tekrar hazir (partiler sifirlandi, adres ayni)." -ForegroundColor Green
                } else {
                    Write-Host "  UYARI: Sunucu yeniden baslatilamadi." -ForegroundColor Red
                    foreach ($line in (Get-LogTail -Path $serverErrLog)) { Write-Host "    $line" -ForegroundColor DarkGray }
                }
            } else {
                Write-Host "  Sunucu 5 kez kapandi, vazgeciliyor." -ForegroundColor Red
                break
            }
        }

        if ($script:tunnelProc.HasExited) {
            if (([DateTime]::UtcNow - $tunnelStartedAt) -ge [TimeSpan]::FromMinutes(5)) {
                $tunnelRestarts = 0
            }
            if ($tunnelRestarts -lt 5) {
                $tunnelRestarts++
                Write-Host "  Tunel koptu, yeniden aciliyor ($tunnelRestarts/5)..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                $script:tunnelProc = Start-Tunnel
                $tunnelStartedAt = [DateTime]::UtcNow
                $newUrl = Read-TunnelUrl -Proc $script:tunnelProc
                if ($null -ne $newUrl) {
                    $url = $newUrl
                    if ($url) {
                        $verified = $false
                        $verifyStart = [DateTime]::UtcNow
                    } else {
                        $verified = $true
                    }
                    Show-Banner -Url $url
                    if ($url) { Write-Host "  Adres dogrulaniyor..." -ForegroundColor DarkGray }
                } else {
                    Write-Host "  Tunel yeniden acilamadi." -ForegroundColor Red
                    foreach ($line in (Get-LogTail -Path $cfLog)) { Write-Host "    $line" -ForegroundColor DarkGray }
                }
            } else {
                Write-Host "  Tunel 5 kez koptu, vazgeciliyor." -ForegroundColor Red
                break
            }
        }
    }
}
finally {
    if ($hasConsoleInput) {
        [Console]::TreatControlCAsInput = $origTreatCtrlC
    }
    if (Test-Path -LiteralPath $stopFlag) { Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue }
    Stop-All
    Write-Host "  Sunucu ve tunel kapatildi." -ForegroundColor DarkGray
}
