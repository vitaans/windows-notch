# Copyright (C) 2026 the windows-notch authors. Licensed GPL-3.0-or-later, see LICENSE.
# Publishes a new version: sets VERSION, commits, tags, pushes and creates the GitHub Release
# with a zip of the files. Everyone's island then offers the update within a day.
#   publish 1.1.0
#   publish 1.1.0 "Weather in the stats panel, faster popups"
# Needs the GitHub CLI signed in (winget install GitHub.cli, then gh auth login).
param([Parameter(Mandatory = $true, Position = 0)][string]$Version, [Parameter(Position = 1)][string]$Notes = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$Version = $Version.TrimStart('v', 'V')
[void][version]$Version   # must look like 1.2.3

if (git status --porcelain) { throw 'Commit or stash your changes first, so the release is exactly what is pushed.' }
$current = ([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
if ([version]$Version -le [version]$current) { throw "VERSION is already $current; pick a higher number." }

[IO.File]::WriteAllText((Join-Path $root 'VERSION'), "$Version`n", (New-Object System.Text.UTF8Encoding $false))
git add VERSION
git commit -q -m "Release v$Version"
git tag "v$Version"
git push -q
git push -q origin "v$Version"

$zip = Join-Path $env:TEMP "windows-notch-v$Version.zip"
git archive --format zip --prefix "windows-notch/" -o $zip "v$Version"

$gh = Get-Command gh.exe -ErrorAction SilentlyContinue
if ($gh) {
    if ($Notes) { gh release create "v$Version" $zip --title "v$Version" --notes $Notes }
    else { gh release create "v$Version" $zip --title "v$Version" --generate-notes }
    Write-Host "Released v$Version" -ForegroundColor Green
} else {
    $repo = (git remote get-url origin) -replace '^https://github.com/', '' -replace '\.git$', ''
    Write-Host "Tag v$Version is pushed. The GitHub CLI isn't installed, so finish the release on the website:" -ForegroundColor Yellow
    Write-Host "  https://github.com/$repo/releases/new?tag=v$Version"
    Write-Host "  and attach $zip"
}
