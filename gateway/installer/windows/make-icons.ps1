# Generates gateway.ico (running) and gateway-off.ico (stopped, grey) for the Windows installer and the tray icon.
# A sibling of the app icon (mobile/windows/runner/resources/app_icon.ico): the same dark green rounded square and cream,
# with an arched gate instead of the "P". Run it again after changing the drawing:
#   powershell -NoProfile -ExecutionPolicy Bypass -File make-icons.ps1
Add-Type -AssemblyName System.Drawing
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function New-GateBitmap([int]$size, [bool]$off) {
    $s = 256.0
    $bmp = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([System.Drawing.Color]::Transparent)
    if ($off) { $bg = [System.Drawing.Color]::FromArgb(255, 96, 99, 96); $fg = [System.Drawing.Color]::FromArgb(255, 205, 205, 200) }
    else      { $bg = [System.Drawing.Color]::FromArgb(255, 74, 93, 68); $fg = [System.Drawing.Color]::FromArgb(255, 238, 232, 219) }
    # rounded square
    $r = 56.0; $d = $r * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90); $path.AddArc(256 - $d, 0, $d, $d, 270, 90)
    $path.AddArc(256 - $d, 256 - $d, $d, $d, 0, 90); $path.AddArc(0, 256 - $d, $d, $d, 90, 90); $path.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush $bg), $path)
    # the gate: an arch open at the bottom, a node inside it, and the road it stands on
    $pen = New-Object System.Drawing.Pen $fg, 24
    $pen.StartCap = 'Flat'; $pen.EndCap = 'Flat'; $pen.LineJoin = 'Round'
    $arch = New-Object System.Drawing.Drawing2D.GraphicsPath
    $arch.AddLine(76, 190, 76, 118); $arch.AddArc(76, 52, 104, 132, 180, 180); $arch.AddLine(180, 118, 180, 190)
    $g.DrawPath($pen, $arch)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $fg), 128 - 17, 134 - 17, 34, 34)
    $road = New-Object System.Drawing.Pen $fg, 16; $road.StartCap = 'Round'; $road.EndCap = 'Round'
    $g.DrawLine($road, 46, 206, 210, 206)
    $g.Dispose()
    if ($size -eq 256) { return $bmp }
    $out = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $go = [System.Drawing.Graphics]::FromImage($out)
    $go.InterpolationMode = 'HighQualityBicubic'; $go.SmoothingMode = 'AntiAlias'; $go.PixelOffsetMode = 'HighQuality'
    $go.DrawImage($bmp, 0, 0, $size, $size); $go.Dispose(); $bmp.Dispose()
    return $out
}

function Write-Ico([string]$file, [bool]$off) {
    $sizes = 16, 24, 32, 48, 64, 128, 256
    $pngs = foreach ($sz in $sizes) {
        $b = New-GateBitmap $sz $off; $ms = New-Object System.IO.MemoryStream
        $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); , $ms.ToArray()
    }
    $fs = [System.IO.File]::Create($file); $w = New-Object System.IO.BinaryWriter $fs
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $sz = $sizes[$i]; $dim = if ($sz -ge 256) { 0 } else { $sz }
        $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $w.Write($p) }
    $w.Dispose(); $fs.Dispose()
}

Write-Ico (Join-Path $here 'gateway.ico') $false
Write-Ico (Join-Path $here 'gateway-off.ico') $true
# a preview sheet for a quick look (not shipped): the app icon, then the gate at 128, 48, 32 and 16 px, then the stopped one
$sheet = New-Object System.Drawing.Bitmap 760, 170
$gs = [System.Drawing.Graphics]::FromImage($sheet); $gs.Clear([System.Drawing.Color]::FromArgb(255, 30, 30, 30)); $gs.InterpolationMode = 'NearestNeighbor'
$x = 10
$appIco = Join-Path $here '..\..\..\mobile\windows\runner\resources\app_icon.ico'
if (Test-Path $appIco) { $gs.DrawImage((New-Object System.Drawing.Icon((Resolve-Path $appIco).Path, 128, 128)).ToBitmap(), $x, 20, 128, 128) }
$x += 148
foreach ($spec in @(@(128, $false), @(48, $false), @(32, $false), @(16, $false), @(48, $true))) {
    $b = New-GateBitmap $spec[0] $spec[1]; $gs.DrawImage($b, $x, 20, $spec[0], $spec[0]); $b.Dispose(); $x += $spec[0] + 20
}
$sheet.Save((Join-Path $env:TEMP 'gateway-icon-preview.png')); $gs.Dispose(); $sheet.Dispose()
Get-ChildItem $here -Filter *.ico | Select-Object Name, Length
