# Draws Charlie, the example companion, from text grids: each character is one pixel (see $palette),
# scaled up to 128x128 PNGs with hard edges. Copy this to make your own pixel companion.
#   powershell -ExecutionPolicy Bypass -File docs\examples\draw-charlie.ps1
param([string]$Out = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'custom images\Charlie'))

Add-Type -AssemblyName System.Drawing
$scale = 8   # 16 x 8 = 128 px

$palette = @{
    'K' = '#2A1A16'   # outline
    'B' = '#D97857'   # body
    'W' = '#F2A587'   # highlight
    'S' = '#B85F42'   # shade
    'F' = '#1E2230'   # face screen
    'E' = '#9CF2D0'   # eyes
    'A' = '#F2A587'   # antenna, off
    'L' = '#FFD166'   # antenna, lit
    'Y' = '#FFB340'   # "!" and sparkles
    'N' = '#FFFFFF'   # music note
}

# 16 x 16 base body; faces and extras are swapped in per frame below
$base = @(
    '................'
    '.......AA.......'
    '.......KK.......'
    '...KKKKKKKKKK...'
    '..KBBBBBBBBBBK..'
    '..KBWWBBBBBBBK..'
    '..KBFFFFFFFFBK..'
    '..KBFEEFFEEFBK..'
    '..KBFEEFFEEFBK..'
    '..KBFFFFFFFFBK..'
    '..KBBBBBBBBBBK..'
    '..KSSSSSSSSSSK..'
    '...KKKKKKKKKK...'
    '....KK....KK....'
    '................'
    '................'
)
$eyes = @{
    open  = @('..KBFEEFFEEFBK..', '..KBFEEFFEEFBK..')
    blink = @('..KBFFFFFFFFBK..', '..KBFEEFFEEFBK..')
    left  = @('..KBEEFFEEFFBK..', '..KBEEFFEEFFBK..')
    right = @('..KBFFEEFFEEBK..', '..KBFFEEFFEEBK..')
    happy = @('..KBFEFFFFEFBK..', '..KBEFEFFEFEBK..')
}

function Frame([string]$face, [hashtable]$set = @{}) {
    $g = [string[]]$base.Clone()
    $g[7] = $eyes[$face][0]; $g[8] = $eyes[$face][1]
    foreach ($k in $set.Keys) {           # "row,col" = 'char'
        $r, $c = $k -split ','; $r = [int]$r; $c = [int]$c
        $g[$r] = $g[$r].Substring(0, $c) + $set[$k] + $g[$r].Substring($c + 1)
    }
    $g
}
function Save-Png([string[]]$grid, [string]$name) {
    $bmp = New-Object System.Drawing.Bitmap (16 * $scale), (16 * $scale)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.Clear([System.Drawing.Color]::Transparent)
    for ($y = 0; $y -lt 16; $y++) {
        for ($x = 0; $x -lt 16; $x++) {
            $ch = [string]$grid[$y][$x]
            if (-not $palette.ContainsKey($ch)) { continue }
            $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($palette[$ch]))
            $gr.FillRectangle($brush, $x * $scale, $y * $scale, $scale, $scale)
            $brush.Dispose()
        }
    }
    $gr.Dispose()
    $bmp.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$lit = @{ '1,7' = 'L'; '1,8' = 'L' }
$bang  = @{ '3,14' = 'Y'; '4,14' = 'Y'; '5,14' = 'Y'; '7,14' = 'Y' }
$bang2 = @{ '2,14' = 'Y'; '3,14' = 'Y'; '4,14' = 'Y'; '6,14' = 'Y' }
$noteR = @{ '0,14' = 'N'; '0,15' = 'N'; '1,14' = 'N'; '2,13' = 'N'; '2,14' = 'N'; '3,13' = 'N'; '3,14' = 'N' }
$noteL = @{ '0,2' = 'N'; '0,3' = 'N'; '1,2' = 'N'; '2,1' = 'N'; '2,2' = 'N'; '3,1' = 'N'; '3,2' = 'N' }

# idle: mostly still, a glance, then a blink at the end of the loop
$i = 0
foreach ($f in 'open', 'open', 'open', 'open', 'left', 'open', 'open', 'blink') { $i++; Save-Png (Frame $f) "idle_$i.png" }
# working: eyes scan left and right, antenna light blinks
Save-Png (Frame 'left' $lit) 'working_1.png'
Save-Png (Frame 'left')      'working_2.png'
Save-Png (Frame 'right' $lit) 'working_3.png'
Save-Png (Frame 'right')     'working_4.png'
# needs your input: a bouncing "!"
Save-Png (Frame 'open' ($bang + $lit)) 'needs_1.png'
Save-Png (Frame 'open' $bang2)         'needs_2.png'
# done: happy eyes and a sparkle
Save-Png (Frame 'happy' @{ '1,2' = 'Y'; '5,14' = 'Y' }) 'done_1.png'
Save-Png (Frame 'happy' @{ '2,13' = 'Y'; '0,3' = 'Y' }) 'done_2.png'
# sleep: eyes shut, a "z" that comes and goes (shown after a while without mouse or keyboard)
Save-Png (Frame 'blink' @{ '0,13' = 'N'; '0,14' = 'N'; '0,15' = 'N'; '1,15' = 'N'; '2,14' = 'N'; '3,13' = 'N'; '3,14' = 'N'; '3,15' = 'N' }) 'sleep_1.png'
Save-Png (Frame 'blink') 'sleep_2.png'
# music: a note hopping from side to side
Save-Png (Frame 'blink' $noteR) 'music_1.png'
Save-Png (Frame 'blink' $noteL) 'music_2.png'

[IO.File]::WriteAllText((Join-Path $Out 'companion.json'),
    "{`n  `"size`": 28,`n  `"fps`": 4,`n  `"pixelated`": true,`n  `"breathe`": false`n}`n")
Write-Host "Charlie drawn into $Out"
