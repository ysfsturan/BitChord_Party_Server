# BitChord Parti Sunucusu - kurulum
# Gerekli dosyalari indirir: cloudflared.exe + bitchord-jam.exe

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

$repo = "ysfsturan/bit-chord-party-server"
$cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
$jamUrl = "https://github.com/$repo/releases/latest/download/bitchord-jam.exe"

Write-Host ""
Write-Host "  ==============================================" -ForegroundColor DarkCyan
Write-Host "     BitChord Parti Sunucusu - Kurulum" -ForegroundColor Cyan
Write-Host "  ==============================================" -ForegroundColor DarkCyan
Write-Host ""

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-File {
    param([string]$Url, [string]$OutFile, [string]$Label)
    Write-Host "  $Label indiriliyor..." -ForegroundColor Gray
    $curl = Join-Path $env:SystemRoot "System32\curl.exe"
    if (Test-Path $curl) {
        & $curl -L --fail --silent --show-error -o $OutFile $Url
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 1000000)) { return $true }
    }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
        return $true
    } catch {
        return $false
    }
}

# 1) cloudflared
if (Test-Path "cloudflared.exe") {
    Write-Host "  cloudflared.exe zaten var, atlandi." -ForegroundColor DarkGray
} else {
    if (-not (Get-File -Url $cfUrl -OutFile "cloudflared.exe" -Label "Cloudflare tuneli (cloudflared)")) {
        Write-Host "  HATA: cloudflared.exe indirilemedi. Internet baglantisini kontrol et." -ForegroundColor Red
        Read-Host "Kapatmak icin Enter"; exit 1
    }
    Write-Host "        tamam." -ForegroundColor Green
}

# 2) sunucu
if (Test-Path "bitchord-jam.exe") {
    Write-Host "  bitchord-jam.exe zaten var, atlandi." -ForegroundColor DarkGray
} else {
    if (-not (Get-File -Url $jamUrl -OutFile "bitchord-jam.exe" -Label "Parti sunucusu (bitchord-jam)")) {
        Write-Host ""
        Write-Host "  HATA: Sunucu indirilemedi." -ForegroundColor Red
        Write-Host "  Alternatif: kaynak klasorunden kendin derleyebilirsin (README > Gelistirme)." -ForegroundColor Yellow
        Read-Host "Kapatmak icin Enter"; exit 1
    }
    Write-Host "        tamam." -ForegroundColor Green
}

Write-Host ""
Write-Host "  ==============================================" -ForegroundColor Green
Write-Host "   KURULUM TAMAM" -ForegroundColor White
Write-Host "  ==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Simdi baslat.bat dosyasina cift tikla." -ForegroundColor Gray
Write-Host ""
Read-Host "Kapatmak icin Enter"
