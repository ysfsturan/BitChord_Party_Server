# BitChord Listen Together - yerel parti sunucusu + HTTPS tunel
# Tek pencere. Baslatmak icin baslat.bat dosyasina cift tikla.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

$runDir = Join-Path $here "run"
$cfLog = Join-Path $runDir "tunnel.log"
$serverBat = Join-Path $here "sunucu-baslat.bat"
$tunnelBat = Join-Path $here "tunel-baslat.bat"

if (-not (Test-Path $runDir)) { New-Item -ItemType Directory -Path $runDir | Out-Null }

# ---------- AYARLAR ----------
$env:PORT = "8000"
$env:JAM_MAX_MEMBERS = "10"      # parti basina cihaz (2-10)
$env:JAM_MAX_PARTIES = "50"      # eszamanli parti
$env:JAM_MAX_UPCOMING_QUEUE = "25"
$env:JAM_TRUST_PROXY = "true"    # Cloudflare arkasinda gercek IP icin

function Stop-All {
    & taskkill /F /IM cloudflared.exe 2>$null | Out-Null
    & taskkill /F /IM bitchord-jam.exe 2>$null | Out-Null
    Start-Sleep -Milliseconds 600
}

function Test-Health {
    param([string]$BaseUrl)
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/healthz" -UseBasicParsing -TimeoutSec 4
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Wait-Local {
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 400
        if (Test-Health -BaseUrl "http://localhost:8000") { return $true }
    }
    return $false
}

function Read-TunnelUrl {
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 400
        if (Test-Path $cfLog) {
            $txt = Get-Content $cfLog -Raw -ErrorAction SilentlyContinue
            if ($txt -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") { return $Matches[0] }
        }
    }
    return $null
}

function Show-Banner {
    param([string]$Url)
    Write-Host ""
    Write-Host "  ==============================================" -ForegroundColor Green
    Write-Host "   SUNUCU ADRESI (uygulamaya bunu gir):" -ForegroundColor White
    Write-Host ""
    Write-Host "   $Url" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ==============================================" -ForegroundColor Green
    try { Set-Clipboard -Value $Url } catch { }
    Write-Host "  Adres panoya kopyalandi." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  BitChord > Ayarlar > Listen Together" -ForegroundColor Gray
    Write-Host "  Parti olustur -> 6 haneli kodu arkadaslarina gonder." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Kapatmak icin: Ctrl+C veya durdur.bat" -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host ""
Write-Host "  ==============================================" -ForegroundColor DarkCyan
Write-Host "        BitChord - Parti Sunucusu" -ForegroundColor Cyan
Write-Host "  ==============================================" -ForegroundColor DarkCyan
Write-Host ""

if (-not (Test-Path (Join-Path $here "bitchord-jam.exe"))) {
    Write-Host "  HATA: bitchord-jam.exe bulunamadi. once kur.bat calistir." -ForegroundColor Red
    Read-Host "Kapatmak icin Enter"; exit 1
}
if (-not (Test-Path (Join-Path $here "cloudflared.exe"))) {
    Write-Host "  HATA: cloudflared.exe bulunamadi. once kur.bat calistir." -ForegroundColor Red
    Read-Host "Kapatmak icin Enter"; exit 1
}

Stop-All

# ---------- 1. SUNUCU ----------
Write-Host "  [1/2] Sunucu baslatiliyor..." -ForegroundColor Gray
& $serverBat
if (-not (Wait-Local)) {
    Write-Host "  HATA: Sunucu baslamadi. 8000 portu dolu olabilir." -ForegroundColor Red
    Stop-All
    Read-Host "Kapatmak icin Enter"; exit 1
}

# ---------- 2. TUNEL ----------
Write-Host "  [2/2] HTTPS tuneli aciliyor..." -ForegroundColor Gray
if (Test-Path $cfLog) { Remove-Item $cfLog -Force -ErrorAction SilentlyContinue }
& $tunnelBat
$url = Read-TunnelUrl
if (-not $url) {
    Write-Host "  HATA: Tunel adresi alinamadi. Internet baglantisini kontrol et." -ForegroundColor Red
    Write-Host "  Detay: $cfLog" -ForegroundColor DarkGray
    Stop-All
    Read-Host "Kapatmak icin Enter"; exit 1
}

Show-Banner -Url $url
Write-Host "  Adres dogrulaniyor..." -ForegroundColor DarkGray

# ---------- BEKCI ----------
$serverRestarts = 0
$verified = $false
$verifyTries = 0
try {
    while ($true) {
        Start-Sleep -Seconds 2

        if (-not $verified) {
            $verifyTries++
            if (Test-Health -BaseUrl $url) {
                $verified = $true
                Write-Host "  Hazir. Arkadaslarin adresi girebilir." -ForegroundColor Green
                Write-Host ""
            } elseif ($verifyTries -ge 60) {
                Write-Host "  UYARI: Adres 2 dakikadir cevap vermiyor. Cloudflare tarafinda gecikme olabilir." -ForegroundColor Yellow
                Write-Host ""
                $verified = $true
            }
        }

        if (-not (Get-Process -Name "bitchord-jam" -ErrorAction SilentlyContinue)) {
            if ($serverRestarts -lt 5) {
                $serverRestarts++
                Write-Host "  Sunucu kapandi, yeniden baslatiliyor ($serverRestarts/5)..." -ForegroundColor Yellow
                & $serverBat
                $null = Wait-Local
                Write-Host "  Sunucu tekrar hazir (partiler sifirlandi, adres ayni)." -ForegroundColor Green
            } else {
                Write-Host "  Sunucu 5 kez kapandi, vazgeciliyor." -ForegroundColor Red
                break
            }
        }

        if (-not (Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue)) {
            Write-Host "  Tunel koptu, yeniden aciliyor (adres degisecek)..." -ForegroundColor Yellow
            if (Test-Path $cfLog) { Remove-Item $cfLog -Force -ErrorAction SilentlyContinue }
            & $tunnelBat
            $newUrl = Read-TunnelUrl
            if ($newUrl) {
                $url = $newUrl
                $verified = $false
                $verifyTries = 0
                Show-Banner -Url $url
                Write-Host "  Adres dogrulaniyor..." -ForegroundColor DarkGray
            } else {
                Write-Host "  Tunel yeniden acilamadi. Internet baglantisini kontrol et." -ForegroundColor Red
                break
            }
        }
    }
}
finally {
    Stop-All
    Write-Host "  Sunucu ve tunel kapatildi." -ForegroundColor DarkGray
}
