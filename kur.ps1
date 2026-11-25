# BitChord Parti Sunucusu - kurulum
# Gerekli dosyalari indirir: cloudflared.exe + bitchord-jam.exe
param([switch]$Force)

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

$repo = "ysfsturan/bit-chord-party-server"
$cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
$jamUrl = "https://github.com/$repo/releases/latest/download/bitchord-jam.exe"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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

function Test-ExeRunningHere {
    param([string]$ExePath)
    $full = [System.IO.Path]::GetFullPath($ExePath)
    $name = [System.IO.Path]::GetFileName($full)
    try {
        $procs = Get-CimInstance Win32_Process -Filter ("Name = '{0}'" -f $name) -ErrorAction Stop
        foreach ($p in $procs) {
            if ($p.ExecutablePath -and ($p.ExecutablePath.Equals($full, [System.StringComparison]::OrdinalIgnoreCase))) {
                return $true
            }
        }
    } catch { }
    return $false
}

function Get-LatestReleaseSha256 {
    param([string]$Repo, [string]$AssetName)
    try {
        $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
        $headers = @{ "User-Agent" = "bit-chord-party-server-installer" }
        $rel = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        foreach ($asset in $rel.assets) {
            if ($asset.name -eq $AssetName -and $asset.digest -match "^sha256:([0-9a-fA-F]{64})$") {
                return $Matches[1].ToLowerInvariant()
            }
        }
    } catch { }
    return $null
}

function Get-File {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Label,
        [string]$ExpectedSha256 = ""
    )
    Write-Host "  $Label indiriliyor..." -ForegroundColor Gray
    $tmp = "$OutFile.tmp"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

    $downloaded = $false
    $curl = Join-Path $env:SystemRoot "System32\curl.exe"
    if (Test-Path -LiteralPath $curl) {
        & $curl -L --fail --progress-bar --connect-timeout 15 --max-time 300 --retry 2 -o $tmp $Url
        if ($LASTEXITCODE -eq 0 -and (Test-ValidExe $tmp)) {
            $downloaded = $true
        } else {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }

    if (-not $downloaded) {
        $prevProg = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"
        try {
            Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
            if (Test-ValidExe $tmp) {
                $downloaded = $true
            }
        } catch {
            $downloaded = $false
        } finally {
            $ProgressPreference = $prevProg
        }
    }

    if (-not $downloaded) {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        return $false
    }

    if ($ExpectedSha256) {
        $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $ExpectedSha256) {
            Write-Host "  HATA: SHA-256 dogrulamasi basarisiz (beklenen: $ExpectedSha256, gelen: $actual)." -ForegroundColor Red
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            return $false
        }
    }

    Move-Item -Path $tmp -Destination $OutFile -Force
    return $true
}

Write-Host ""
Write-Host "  ==============================================" -ForegroundColor DarkCyan
Write-Host "     BitChord Parti Sunucusu - Kurulum" -ForegroundColor Cyan
Write-Host "  ==============================================" -ForegroundColor DarkCyan
Write-Host ""

# 1) cloudflared
$cfExe = Join-Path $here "cloudflared.exe"
if ((-not $Force) -and (Test-ValidExe $cfExe)) {
    Write-Host "  cloudflared.exe zaten var, atlandi." -ForegroundColor DarkGray
} else {
    if (Test-Path -LiteralPath $cfExe) {
        if (Test-ExeRunningHere $cfExe) {
            Write-Host "  HATA: cloudflared.exe su anda calisiyor. Once durdur.bat calistir." -ForegroundColor Red
            Wait-Exit; exit 1
        }
        if (-not $Force) {
            Write-Host "  cloudflared.exe bozuk veya eksik gorunuyor, yeniden indiriliyor..." -ForegroundColor Yellow
        }
    }
    if (-not (Get-File -Url $cfUrl -OutFile $cfExe -Label "Cloudflare tuneli (cloudflared)")) {
        Write-Host "  HATA: cloudflared.exe indirilemedi. Internet baglantisini kontrol et." -ForegroundColor Red
        Wait-Exit; exit 1
    }
    Write-Host "        tamam." -ForegroundColor Green
}

# 2) sunucu
$jamExe = Join-Path $here "bitchord-jam.exe"
if ((-not $Force) -and (Test-ValidExe $jamExe)) {
    Write-Host "  bitchord-jam.exe zaten var, atlandi." -ForegroundColor DarkGray
} else {
    if (Test-Path -LiteralPath $jamExe) {
        if (Test-ExeRunningHere $jamExe) {
            Write-Host "  HATA: bitchord-jam.exe su anda calisiyor. Once durdur.bat calistir." -ForegroundColor Red
            Wait-Exit; exit 1
        }
        if (-not $Force) {
            Write-Host "  bitchord-jam.exe bozuk veya eksik gorunuyor, yeniden indiriliyor..." -ForegroundColor Yellow
        }
    }
    $expectedSha = Get-LatestReleaseSha256 -Repo $repo -AssetName "bitchord-jam.exe"
    if (-not (Get-File -Url $jamUrl -OutFile $jamExe -Label "Parti sunucusu (bitchord-jam)" -ExpectedSha256 $expectedSha)) {
        Write-Host ""
        Write-Host "  HATA: Sunucu indirilemedi." -ForegroundColor Red
        Write-Host "  Alternatif: kaynak klasorunden kendin derleyebilirsin (README > Gelistirme)." -ForegroundColor Yellow
        Wait-Exit; exit 1
    }
    if ($expectedSha) {
        Write-Host "        tamam (SHA-256 dogrulandi)." -ForegroundColor Green
    } else {
        Write-Host "        tamam." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "  ==============================================" -ForegroundColor Green
Write-Host "   KURULUM TAMAM" -ForegroundColor White
Write-Host "  ==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Simdi baslat.bat dosyasina cift tikla." -ForegroundColor Gray
Write-Host ""
Wait-Exit
