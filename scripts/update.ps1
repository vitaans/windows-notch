# Updates this folder to a release from GitHub. The island starts it from "Install update";
# it runs on its own, so the island's files can be replaced while it is running.
# Kept as they are: settings.json, state\ and your custom images (only new companion folders
# from the release are added). Everything else is replaced with the release's files, then the
# installer runs again (hooks may have changed) and restarts the island.
param([Parameter(Mandatory = $true)][string]$Url, [string]$Version = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$log = Join-Path $root 'state\update.log'
function Log($m) { try { Add-Content -Path $log -Value ("{0:u} {1}" -f (Get-Date), $m) } catch { } }

$work = Join-Path $env:TEMP ('windows-notch-update-' + [guid]::NewGuid().ToString('N'))
try {
    Log "updating to $Version from $Url"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $zip = Join-Path $work 'update.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'windows-notch-updater')
    $wc.DownloadFile($Url, $zip)
    $out = Join-Path $work 'files'
    Expand-Archive -LiteralPath $zip -DestinationPath $out -Force

    # GitHub's zips put everything in one top folder; find the one holding the island
    $island = Get-ChildItem -LiteralPath $out -Recurse -Filter 'ClaudeIsland.ps1' | Select-Object -First 1
    if (-not $island) { throw 'the download does not look like windows-notch' }
    $src = Split-Path (Split-Path $island.FullName -Parent) -Parent

    foreach ($f in Get-ChildItem -LiteralPath $src -Recurse -File -Force) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\')
        if ($rel -eq 'settings.json' -or $rel -like 'state\*' -or $rel -like '.git\*') { continue }
        if ($rel -like 'custom images\*') {
            # a companion folder you already have is yours; only brand-new ones are added
            $parts = $rel.Split('\')
            if ($parts.Count -gt 2 -and (Test-Path -LiteralPath (Join-Path $root ('custom images\' + $parts[1])))) { continue }
            if ($parts.Count -eq 2 -and (Test-Path -LiteralPath (Join-Path $root $rel))) { continue }
        }
        $dest = Join-Path $root $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    }
    Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter *.ps1 | Unblock-File -ErrorAction SilentlyContinue
    Log "files updated; running the installer"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\install.ps1') | Out-Null
    Log "done"
} catch {
    Log ("failed: " + $_.Exception.Message)
    # tell the island, so the failure doesn't go unnoticed
    try {
        $inbox = Join-Path $root 'state\inbox'; New-Item -ItemType Directory -Force -Path $inbox | Out-Null
        [IO.File]::WriteAllText((Join-Path $inbox ([guid]::NewGuid().ToString('N') + '.json')),
            (@{ kind = 'fail'; title = 'Update failed'; text = $_.Exception.Message } | ConvertTo-Json -Compress))
    } catch { }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
