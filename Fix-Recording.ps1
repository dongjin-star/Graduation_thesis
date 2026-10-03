<#
.SYNOPSIS
    Creates an analysis-ready copy of a recorded CCTV clip with a fixed (CFR)
    frame rate and regenerated timestamps. The original file is left untouched.

.PARAMETER InputFile
    Path to the recorded .mp4 file (required)

.PARAMETER Fps
    Target constant frame rate. Default 30 (source is ~26.4fps; 30 duplicates
    frames to reach CFR instead of dropping them, avoiding ghosting)

.PARAMETER Crf
    libx264 CRF (quality). Lower = better quality / larger file. Default 18

.EXAMPLE
    .\Fix-Recording.ps1 -InputFile ".\recordings\ch130_20261003_161918.mp4"
    -> creates .\recordings\ch130_20261003_161918_fixed.mp4
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [int]$Fps = 30,

    [int]$Crf = 18,

    [string]$FfmpegPath = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $InputFile)) {
    Write-Error "Input file not found: $InputFile"
    exit 1
}

# Resolve ffmpeg executable (prefer the bundled schannel build for consistency
# with Record-CCTV.ps1, though TLS is not involved for local file processing).
$bundledFfmpeg = Join-Path $PSScriptRoot "tools\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe"

if ($FfmpegPath -ne "") {
    $ffmpegExe = $FfmpegPath
} elseif (Test-Path $bundledFfmpeg) {
    $ffmpegExe = $bundledFfmpeg
} else {
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        Write-Error "ffmpeg not found."
        exit 1
    }
    $ffmpegExe = $ffmpeg.Source
}

$inputItem = Get-Item $InputFile
# Always output .mp4 regardless of input container (raw captures are .mkv).
$outFile = Join-Path $inputItem.DirectoryName ($inputItem.BaseName + "_fixed.mp4")

Write-Host "Input  : $InputFile"
Write-Host "Output : $outFile"
Write-Host "Target : ${Fps}fps CFR, libx264 crf $Crf"
Write-Host ""

& $ffmpegExe -y -nostats -loglevel warning `
    -fflags +genpts `
    -i $InputFile `
    -r $Fps -fps_mode cfr `
    -c:v libx264 -crf $Crf -preset medium `
    -c:a aac `
    $outFile

if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) {
    $size = (Get-Item $outFile).Length / 1MB
    Write-Host ""
    Write-Host ("Fixed copy created: {0} ({1:N1} MB)" -f $outFile, $size)
    Write-Host "Original file left unchanged: $InputFile"
} else {
    Write-Warning "Re-encoding may have failed. ffmpeg exit code: $LASTEXITCODE"
}
