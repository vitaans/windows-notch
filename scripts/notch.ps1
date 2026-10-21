# Send a notice to the island from anywhere: a script, a build, a terminal.
#   notch "Deploy finished"                      a plain notice
#   notch "Tests failed" -Kind fail -Text "3 of 120"
#   notch run npm test                            runs the command, then shows passed / failed
#   notch timer 25                                starts a 25 minute timer
# (notch.cmd in the island folder calls this; add that folder to PATH to use it anywhere.)
param(
    [Parameter(Position = 0)][string]$Title = 'Done',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
    [ValidateSet('info', 'success', 'fail')][string]$Kind = 'info',
    [string]$Text = ''
)
$root = Split-Path $PSScriptRoot -Parent
$inbox = Join-Path $root 'state\inbox'
New-Item -ItemType Directory -Force -Path $inbox | Out-Null
function Send($o) {
    $id = [guid]::NewGuid().ToString('N')
    $tmp = Join-Path $inbox "$id.tmp"
    [IO.File]::WriteAllText($tmp, ($o | ConvertTo-Json -Compress))
    Move-Item -LiteralPath $tmp -Destination (Join-Path $inbox "$id.json") -Force
}

if ($Title -eq 'run' -and $Rest) {
    $cmd = $Rest -join ' '
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & cmd.exe /c $cmd
    $code = $LASTEXITCODE
    $secs = [int]$sw.Elapsed.TotalSeconds
    $name = if ($cmd.Length -gt 60) { $cmd.Substring(0, 59) + [char]0x2026 } else { $cmd }
    if ($code -eq 0) { Send @{ kind = 'success'; title = 'Passed'; text = "$name  ($secs s)" } }
    else { Send @{ kind = 'fail'; title = "Failed (exit $code)"; text = "$name  ($secs s)" } }
    exit $code
}
if ($Title -eq 'timer') {
    $min = if ($Rest) { [double]$Rest[0] } else { 25 }
    Send @{ kind = 'timer'; minutes = $min; title = "$min min timer" }
    exit 0
}
if (-not $Text -and $Rest) { $Text = $Rest -join ' ' }
Send @{ kind = $Kind; title = $Title; text = $Text }
