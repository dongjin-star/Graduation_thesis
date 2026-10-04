<#
.SYNOPSIS
    Records a Seoul TOPIS traffic CCTV HLS (m3u8) stream for a given duration.

.PARAMETER Url
    The playlist.m3u8 URL copied from browser devtools (required)

.PARAMETER Duration
    Recording length in seconds. Default 60 (for testing)

.PARAMETER Label
    Unused in the filename (kept for backward compatibility / future use).

.PARAMETER SkipFix
    Skip the automatic 30fps CFR "_fixed" copy that is created by default
    after recording (via Fix-Recording.ps1).

.PARAMETER FixFps
    Frame rate passed to Fix-Recording.ps1 for the automatic fixed copy. Default 30

.PARAMETER FixCrf
    CRF passed to Fix-Recording.ps1 for the automatic fixed copy. Default 18

.PARAMETER MinFreeMemoryGB
    Minimum free RAM (GB) required to start recording. If free memory is
    below this, the script aborts before even connecting to the stream
    (a long recording getting OOM-killed partway through is how footage was
    lost before). Default 3. Use -Force to start anyway.

.PARAMETER Force
    Start the recording even if the free-memory check fails.

.EXAMPLE
    .\Record-CCTV.ps1 -Url "https://.../playlist.m3u8"
    .\Record-CCTV.ps1 -Url "https://.../playlist.m3u8" -Duration 3600
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [int]$Duration = 60,

    [string]$Label = "cctv",

    [string]$Referer = "https://topis.seoul.go.kr/",

    [string]$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",

    [string]$FfmpegPath = "",

    [switch]$SkipFix,

    [int]$FixFps = 30,

    [int]$FixCrf = 18,

    [double]$MinFreeMemoryGB = 3,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Pre-flight memory check. A long unattended recording getting OOM-killed
# mid-way produces an unplayable/unrecoverable file (see mkv rationale
# below), so check for headroom before even starting.
$os = Get-CimInstance Win32_OperatingSystem
$totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
Write-Host ("Free memory: {0}GB / {1}GB total" -f $freeGB, $totalGB)

if ($freeGB -lt $MinFreeMemoryGB) {
    Write-Host ""
    Write-Host "Top memory-consuming processes:"
    Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 8 Name, @{N='MemMB';E={[math]::Round($_.WorkingSet/1MB,0)}} | Format-Table -AutoSize | Out-String | Write-Host

    if (-not $Force) {
        Write-Error "Free memory (${freeGB}GB) is below the ${MinFreeMemoryGB}GB minimum. Close some of the programs above, or pass -Force to start anyway."
        exit 1
    } else {
        Write-Warning "Free memory (${freeGB}GB) is below the ${MinFreeMemoryGB}GB minimum, but -Force was set. Continuing anyway."
    }
}

# Resolve ffmpeg executable.
# NOTE: the system ffmpeg (gyan.dev build) uses gnutls for TLS, which cannot
# validate TOPIS CCTV certificates because the server does not send its
# intermediate certificate during the handshake and gnutls has no AIA-fetch
# fallback. The bundled build below (BtbN) uses Windows SChannel for TLS,
# same as curl, which resolves this automatically.
$bundledFfmpeg = Join-Path $PSScriptRoot "tools\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe"

if ($FfmpegPath -ne "") {
    $ffmpegExe = $FfmpegPath
} elseif (Test-Path $bundledFfmpeg) {
    $ffmpegExe = $bundledFfmpeg
} else {
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        Write-Error "ffmpeg not found. Install it with 'winget install ffmpeg' or from https://www.gyan.dev/ffmpeg/builds/ and add it to PATH."
        exit 1
    }
    $ffmpegExe = $ffmpeg.Source
    Write-Warning "Using system ffmpeg ($ffmpegExe). If it uses gnutls for TLS, TOPIS https streams may fail with 'Peer certificate failed verification'."
}

# Prepare recordings folder (next to this script)
$outDir = Join-Path $PSScriptRoot "recordings"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

# Filename: {yyyyMMdd_HHmmss} ({duration}).mkv (based on recording start time)
# NOTE: raw capture uses .mkv, not .mp4. MP4's index (moov atom) is only
# written once at the very end, so if the process is killed mid-recording
# (e.g. an OOM kill) the entire file becomes unplayable ("moov atom not
# found") and all footage is lost. Matroska writes data progressively, so a
# killed recording is still playable/recoverable up to the last flushed
# cluster. Fix-Recording.ps1 converts the final analysis copy to .mp4 anyway.
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ($Duration % 60 -eq 0) {
    $durationLabel = "$($Duration / 60)min"
} else {
    $durationLabel = "${Duration}s"
}
$outFile = Join-Path $outDir "$timestamp ($durationLabel).mkv"

Write-Host "Recording started : $timestamp"
Write-Host "Duration           : ${Duration}s"
Write-Host "Output file        : $outFile"
Write-Host ""

$headers = "Referer: $Referer`r`n"

& $ffmpegExe -y -nostats -loglevel warning `
    -fflags +genpts+discardcorrupt `
    -user_agent $UserAgent `
    -headers $headers `
    -i $Url `
    -t $Duration `
    -c copy `
    $outFile

if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) {
    $size = (Get-Item $outFile).Length / 1MB
    Write-Host ""
    Write-Host ("Recording complete: {0} ({1:N1} MB)" -f $outFile, $size)

    if (-not $SkipFix) {
        Write-Host ""
        Write-Host "Creating fixed (CFR) copy..."
        $fixScript = Join-Path $PSScriptRoot "Fix-Recording.ps1"
        & $fixScript -InputFile $outFile -Fps $FixFps -Crf $FixCrf -FfmpegPath $ffmpegExe
    }
} else {
    Write-Warning "Recording may have failed. ffmpeg exit code: $LASTEXITCODE"
    Write-Host "Note: if '-c copy' fails due to a stream format issue, try re-encoding instead:"
    Write-Host "  & `"$ffmpegExe`" -y -user_agent `"$UserAgent`" -headers `"$headers`" -i `"$Url`" -t $Duration -c:v libx264 `"$outFile`""
}
