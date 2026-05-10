#Requires -Version 5.0
<#
.SYNOPSIS
    Film-Qualitaetsanalyse fuer Windows
.DESCRIPTION
    Analysiert eine Video-Datei mit ffprobe und bewertet Codec, Quelle,
    Aufloesung, Bitrate, Quality Factor, Farbtiefe und Dateigroesse.
.PARAMETER InputPath
    Pfad zur Video-Datei (MKV, MP4, AVI, ...)
.EXAMPLE
    .\analyse.ps1 "C:\Filme\Movie.2023.1080p.WEB-DL.x265.mkv"
.NOTES
    Benoetigt ffprobe (Teil von ffmpeg): https://ffmpeg.org/download.html
    Author: tg4nd4lf
    Version: 1.0
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# ffprobe suchen
# ---------------------------------------------------------------------------

function Find-FFProbe {
    $candidates = @(
        "ffprobe",
        "ffprobe.exe",
        "C:\ffmpeg\bin\ffprobe.exe",
        "C:\Program Files\ffmpeg\bin\ffprobe.exe",
        "C:\Program Files (x86)\ffmpeg\bin\ffprobe.exe",
        "$env:LOCALAPPDATA\ffmpeg\bin\ffprobe.exe",
        "$env:ProgramFiles\ffmpeg\bin\ffprobe.exe"
    )
    foreach ($c in $candidates) {
        try {
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
        } catch {}
        if (Test-Path $c) { return $c }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Ausgabe-Hilfsfunktionen
# ---------------------------------------------------------------------------

$RatingColors = @{
    "Schlecht"   = "Red"
    "Akzeptabel" = "Yellow"
    "Gut"        = "Green"
    "Sehr gut"   = "Cyan"
}

function Write-Row {
    param(
        [string]$Label,
        [string]$Value,
        [string]$Rating = ""
    )
    Write-Host ("  {0,-22} " -f ($Label)) -NoNewline
    Write-Host $Value -NoNewline
    if ($Rating -and $RatingColors.ContainsKey($Rating)) {
        Write-Host "   [" -NoNewline
        Write-Host $Rating -ForegroundColor $RatingColors[$Rating] -NoNewline
        Write-Host "]"
    } else {
        Write-Host ""
    }
}

function Format-FileSize {
    param([long]$Bytes)
    $gb = $Bytes / 1GB
    if ($gb -ge 1) { return "{0:F2} GB" -f $gb }
    return "{0:F1} MB" -f ($Bytes / 1MB)
}

function Format-Duration {
    param([double]$Seconds)
    $h = [int]($Seconds / 3600)
    $m = [int](($Seconds % 3600) / 60)
    $s = [int]($Seconds % 60)
    if ($h -gt 0) { return "{0}h {1:D2}m {2:D2}s" -f $h, $m, $s }
    return "{0}m {1:D2}s" -f $m, $s
}

function Format-AudioChannels {
    param([int]$Ch)
    switch ($Ch) {
        1 { return "1.0 (Mono)" }
        2 { return "2.0 (Stereo)" }
        6 { return "5.1" }
        8 { return "7.1" }
        default { return "$Ch ch" }
    }
}

# ---------------------------------------------------------------------------
# Quellen-Erkennung
# ---------------------------------------------------------------------------

function Get-SourceRating {
    param([string]$Filename)
    $lower = $Filename.ToLower()
    $patterns = @(
        @{ Rating = "Sehr gut";   Pattern = "web.?dl|blu.?ray|bdrip|bdremux|remux" },
        @{ Rating = "Gut";        Pattern = "webrip" },
        @{ Rating = "Akzeptabel"; Pattern = "dvdrip|dvdscr|hdrip|hdtv" },
        @{ Rating = "Schlecht";   Pattern = "\bcam\b|\bts\b|\btc\b|telesync|telecine" }
    )
    foreach ($p in $patterns) {
        if ($lower -match $p.Pattern) {
            return @{ Rating = $p.Rating; Label = ($Matches[0]).ToUpper() }
        }
    }
    return @{ Rating = ""; Label = "Unbekannt" }
}

# ---------------------------------------------------------------------------
# Codec-Bewertung
# ---------------------------------------------------------------------------

function Get-CodecRating {
    param([string]$CodecName, [int]$BitDepth)
    switch ($CodecName.ToLower()) {
        "hevc" {
            if ($BitDepth -eq 10) { return @{ Rating = "Sehr gut"; Display = "H.265 / x265 (10-bit)" } }
            return @{ Rating = "Gut"; Display = "H.265 / x265 (8-bit)" }
        }
        "h264"       { return @{ Rating = "Akzeptabel"; Display = "H.264 / x264" } }
        "av1"        { return @{ Rating = "Sehr gut";   Display = "AV1" } }
        "vp9"        { return @{ Rating = "Gut";        Display = "VP9" } }
        "mpeg2video" { return @{ Rating = "Schlecht";   Display = "MPEG-2" } }
        "mpeg4"      { return @{ Rating = "Schlecht";   Display = "MPEG-4 / XviD" } }
        "divx"       { return @{ Rating = "Schlecht";   Display = "DivX" } }
        "xvid"       { return @{ Rating = "Schlecht";   Display = "XviD" } }
        default      { return @{ Rating = "Akzeptabel"; Display = $CodecName } }
    }
}

# ---------------------------------------------------------------------------
# Aufloesung
# ---------------------------------------------------------------------------

function Get-ResolutionRating {
    param([int]$Width, [int]$Height)
    if ($Height -ge 2160 -or $Width -ge 3840) { return @{ Rating = "Sehr gut";   Label = "2160p (4K UHD)" } }
    if ($Height -ge 1080)                      { return @{ Rating = "Gut";        Label = "1080p (Full HD)" } }
    if ($Height -ge 720)                       { return @{ Rating = "Akzeptabel"; Label = "720p (HD)" } }
    return @{ Rating = "Schlecht"; Label = "${Height}p (SD)" }
}

# ---------------------------------------------------------------------------
# Bitrate
# ---------------------------------------------------------------------------

function Get-BitrateRating {
    param([double]$Kbps, [string]$Codec)
    $efficient = $Codec -match "hevc|av1|vp9"
    if ($efficient) {
        if ($Kbps -gt 6000)  { return "Sehr gut" }
        if ($Kbps -ge 3000)  { return "Gut" }
        if ($Kbps -ge 1000)  { return "Akzeptabel" }
        return "Schlecht"
    } else {
        if ($Kbps -gt 10000) { return "Sehr gut" }
        if ($Kbps -ge 5000)  { return "Gut" }
        if ($Kbps -ge 2000)  { return "Akzeptabel" }
        return "Schlecht"
    }
}

# ---------------------------------------------------------------------------
# Quality Factor
# ---------------------------------------------------------------------------

function Get-QualityFactorRating {
    param([double]$Qf)
    if ($Qf -gt 0.15)  { return "Sehr gut" }
    if ($Qf -ge 0.10)  { return "Gut" }
    if ($Qf -ge 0.05)  { return "Akzeptabel" }
    return "Schlecht"
}

# ---------------------------------------------------------------------------
# Farbtiefe
# ---------------------------------------------------------------------------

function Get-BitDepth {
    param($Stream)
    $bprs = $Stream.bits_per_raw_sample
    if ($bprs -and [string]$bprs -ne "0") { return [int]$bprs }
    $pix = [string]$Stream.pix_fmt
    if ($pix -match "p10|10le|10be") { return 10 }
    if ($pix -match "p12|12le|12be") { return 12 }
    if ($pix -match "^yuv(j?)42[024]p$") { return 8 }
    return 0
}

function Get-BitDepthRating {
    param([int]$Depth, [bool]$Hdr)
    if ($Depth -ge 10 -and $Hdr) { return @{ Rating = "Sehr gut";   Label = "${Depth}-bit HDR" } }
    if ($Depth -ge 10)           { return @{ Rating = "Gut";        Label = "${Depth}-bit SDR" } }
    if ($Depth -eq 8)            { return @{ Rating = "Akzeptabel"; Label = "8-bit SDR" } }
    if ($Depth -gt 0)            { return @{ Rating = "Schlecht";   Label = "${Depth}-bit" } }
    return @{ Rating = ""; Label = "Unbekannt" }
}

# ---------------------------------------------------------------------------
# Dateigroesse pro Stunde
# ---------------------------------------------------------------------------

function Get-SizeRating {
    param([long]$Bytes, [double]$Seconds)
    $gbPerHour = ($Bytes / 1GB) / ($Seconds / 3600)
    if ($gbPerHour -gt 6)  { return "Sehr gut" }
    if ($gbPerHour -ge 3)  { return "Gut" }
    if ($gbPerHour -ge 1)  { return "Akzeptabel" }
    return "Schlecht"
}

# ---------------------------------------------------------------------------
# FPS parsen
# ---------------------------------------------------------------------------

function Parse-FPS {
    param([string]$FpsStr)
    if (-not $FpsStr -or $FpsStr -eq "0/0") { return 0 }
    if ($FpsStr -match "^(\d+)/(\d+)$") {
        $num = [int]$Matches[1]
        $den = [int]$Matches[2]
        if ($den -eq 0) { return 0 }
        return [math]::Round($num / $den, 3)
    }
    try { return [double]$FpsStr } catch { return 0 }
}

# ---------------------------------------------------------------------------
# Hauptlogik
# ---------------------------------------------------------------------------

# Datei pruefen
if (-not (Test-Path $InputPath)) {
    Write-Host "Fehler: Datei nicht gefunden: $InputPath" -ForegroundColor Red
    exit 1
}

# ffprobe suchen
$ffprobe = Find-FFProbe
if (-not $ffprobe) {
    Write-Host "Fehler: ffprobe nicht gefunden." -ForegroundColor Red
    Write-Host "ffmpeg herunterladen: https://ffmpeg.org/download.html" -ForegroundColor Yellow
    exit 1
}

# ffprobe ausfuehren
try {
    $ffArgs = @("-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", $InputPath)
    $raw = & $ffprobe @ffArgs 2>&1
    $meta = $raw | ConvertFrom-Json
} catch {
    Write-Host "Fehler beim Lesen der Datei: $_" -ForegroundColor Red
    exit 1
}

# Streams und Format extrahieren
$videoStream = $meta.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
$audioStream = $meta.streams | Where-Object { $_.codec_type -eq "audio" } | Select-Object -First 1
$fmt = $meta.format

if (-not $videoStream) {
    Write-Host "Fehler: Kein Video-Stream gefunden." -ForegroundColor Red
    exit 1
}

# Basiswerte
$duration   = [double]($fmt.duration ?? $videoStream.duration ?? 0)
$rawBitrate = $videoStream.bit_rate ?? $fmt.bit_rate
$bitrateKbps = if ($rawBitrate) { [double]$rawBitrate / 1000 } else { 0 }
$bitDepth   = Get-BitDepth -Stream $videoStream
$fps        = Parse-FPS -FpsStr ([string]$videoStream.r_frame_rate)
$width      = [int]$videoStream.width
$height     = [int]$videoStream.height
$fileSize   = [long]$fmt.size
$codecName  = [string]$videoStream.codec_name
$colorXfer  = [string]$videoStream.color_transfer
$colorPrim  = [string]$videoStream.color_primaries
$pixFmt     = [string]$videoStream.pix_fmt

# HDR
$hdrTransfers = @("smpte2084", "arib-std-b67", "smpte428")
$hdrPrimaries = @("bt2020", "bt2020nc", "bt2020c")
$isHdr = ($hdrTransfers -contains $colorXfer) -or ($hdrPrimaries -contains $colorPrim)

# Bewertungen berechnen
$codec      = Get-CodecRating     -CodecName $codecName -BitDepth $bitDepth
$source     = Get-SourceRating    -Filename (Split-Path $InputPath -Leaf)
$resolution = Get-ResolutionRating -Width $width -Height $height
$bdInfo     = Get-BitDepthRating   -Depth $bitDepth -Hdr $isHdr

$bitrateRating = if ($bitrateKbps -gt 0) { Get-BitrateRating -Kbps $bitrateKbps -Codec $codecName } else { "" }
$bitrateStr    = if ($bitrateKbps -gt 0) { "{0:N0} kbps" -f $bitrateKbps } else { "Unbekannt" }

$qfRating = ""
$qfStr    = "Unbekannt"
if ($bitrateKbps -gt 0 -and $width -gt 0 -and $height -gt 0 -and $fps -gt 0) {
    $qf       = ($bitrateKbps * 1000) / ($width * $height * $fps)
    $qfRating = Get-QualityFactorRating -Qf $qf
    $qfStr    = "{0:F4}" -f $qf
}

$sizeStr    = if ($fileSize -gt 0) { Format-FileSize -Bytes $fileSize } else { "Unbekannt" }
$sizeRating = ""
if ($fileSize -gt 0 -and $duration -gt 0) {
    $gbPerHour  = ($fileSize / 1GB) / ($duration / 3600)
    $sizeStr   += "  ({0:F2} GB/h)" -f $gbPerHour
    $sizeRating = Get-SizeRating -Bytes $fileSize -Seconds $duration
}

# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------

$sep = "-" * 60
$filename = Split-Path $InputPath -Leaf

Write-Host ""
Write-Host "  $sep"
Write-Host "  Film-Qualitaetsanalyse" -ForegroundColor White
Write-Host "  $sep"
Write-Host ""

Write-Row "Datei:"           $filename
Write-Row "Groesse:"         $sizeStr                                    $sizeRating
Write-Row "Laufzeit:"        (if ($duration -gt 0) { Format-Duration -Seconds $duration } else { "Unbekannt" })
Write-Host ""
Write-Row "Codec:"           $codec.Display                              $codec.Rating
Write-Row "Quelle:"          $source.Label                               $source.Rating
Write-Row "Aufloesung:"      ("{0}  ({1}x{2})" -f $resolution.Label, $width, $height)  $resolution.Rating
Write-Row "Bitrate (Video):" $bitrateStr                                 $bitrateRating
Write-Row "Quality Factor:"  $qfStr                                      $qfRating
Write-Row "Farbtiefe:"       $bdInfo.Label                               $bdInfo.Rating

if ($isHdr) {
    Write-Row "HDR:" ($colorXfer ? $colorXfer : "Ja")
}
if ($pixFmt) {
    Write-Row "Pixel-Format:" $pixFmt
}
if ($audioStream) {
    $aInfo = ([string]$audioStream.codec_name).ToUpper()
    if ($audioStream.channels) {
        $aInfo += "  " + (Format-AudioChannels -Ch ([int]$audioStream.channels))
    }
    if ($audioStream.bit_rate) {
        $aInfo += "  @ {0:N0} kbps" -f ([double]$audioStream.bit_rate / 1000)
    }
    Write-Row "Audio:" $aInfo
}
if ($fps -gt 0) {
    Write-Row "Framerate:" "$fps fps"
}

Write-Host ""
Write-Host "  $sep"
Write-Host -NoNewline "  Legende:  "
Write-Host -NoNewline "Schlecht"   -ForegroundColor Red
Write-Host -NoNewline "  Akzeptabel" -ForegroundColor Yellow
Write-Host -NoNewline "  Gut"      -ForegroundColor Green
Write-Host -NoNewline "  Sehr gut" -ForegroundColor Cyan
Write-Host ""
Write-Host ""
