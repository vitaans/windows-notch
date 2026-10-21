# Claude Island setup - run once (Install.cmd). Everything runs from this folder;
# after this, updating is just replacing files here: the island restarts itself.
# - points Claude Code's hooks at scripts\island-hook.ps1 (backup of settings.json kept)
# - moves over settings from the old %LOCALAPPDATA%\ClaudeIsland install, if any
# - adds the Start with Windows shortcut (on a fresh install, or if it was already on)
# - starts the island

$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$root    = Split-Path $scripts -Parent
New-Item -ItemType Directory -Force -Path (Join-Path $root 'state\sessions'), (Join-Path $root 'companions') | Out-Null
Get-ChildItem $scripts -Filter *.ps1 | Unblock-File -ErrorAction SilentlyContinue

$lnkPath  = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Island.lnk'
$oldDir   = Join-Path $env:LOCALAPPDATA 'ClaudeIsland'
$hadOld   = Test-Path $oldDir
$hadState = Test-Path (Join-Path $root 'state\island.log')
$firstInstall = -not $hadOld -and -not $hadState -and -not (Test-Path $lnkPath)

# ---- stop any running island (old or new location) -------------------------
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'ClaudeIsland\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 400

# ---- migrate the old install ------------------------------------------------
if ($hadOld) {
    $oldCfg = Join-Path $oldDir 'config.json'
    $newCfg = Join-Path $root 'settings.json'
    if ((Test-Path $oldCfg) -and -not (Test-Path $newCfg)) {
        Copy-Item $oldCfg $newCfg
        Write-Host 'Moved your settings from the old install.'
    }
    Remove-Item $oldDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- hooks in ~/.claude/settings.json --------------------------------------
$hookPath = Join-Path $scripts 'island-hook.ps1'
$cmd = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$hookPath`""

$claudeDir = Join-Path $env:USERPROFILE '.claude'
New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
$settingsPath = Join-Path $claudeDir 'settings.json'

$settings = $null
if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.bak-claudeisland" -Force
    $text = Get-Content $settingsPath -Raw
    if ($text -and $text.Trim()) { $settings = $text | ConvertFrom-Json }
}
if (-not $settings) { $settings = New-Object PSObject }
if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject)
}

Write-Host 'Pointing Claude Code hooks at this folder...'
foreach ($ev in 'UserPromptSubmit', 'PreToolUse', 'Notification', 'Stop', 'SessionEnd') {
    $existing = @()
    if ($settings.hooks.PSObject.Properties[$ev]) { $existing = @($settings.hooks.$ev) }
    # drop previous Claude Island entries (old or new location) so re-running is safe
    $kept = @($existing | Where-Object { $_ -and -not ((@($_.hooks) | ForEach-Object { [string]$_.command }) -join ' ' -match 'ClaudeIsland|island-hook\.ps1') })

    $entry = New-Object PSObject
    if ($ev -eq 'PreToolUse') { $entry | Add-Member -NotePropertyName matcher -NotePropertyValue '*' }
    $entry | Add-Member -NotePropertyName hooks -NotePropertyValue @(
        [pscustomobject]@{ type = 'command'; command = $cmd; timeout = 10 }
    )
    $settings.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue (@($kept) + @($entry)) -Force
}
[IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding $false))

# ---- startup shortcut ------------------------------------------------------
$psExe      = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$overlay    = Join-Path $scripts 'ClaudeIsland.ps1'
$launchArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$overlay`""
if ($firstInstall -or (Test-Path $lnkPath)) {
    Write-Host 'Start with Windows: on (change it from the tray menu).'
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath  = $psExe
    $lnk.Arguments   = $launchArgs
    $lnk.WindowStyle = 7
    $lnk.Description = 'Claude Island overlay'
    $lnk.Save()
} else {
    Write-Host 'Start with Windows: off (kept as you set it).'
}

# ---- start it --------------------------------------------------------------
Start-Process -FilePath $psExe -ArgumentList $launchArgs -WindowStyle Hidden

Write-Host ''
Write-Host "Claude Island is running from $root" -ForegroundColor Green
Write-Host 'Right-click the pill icon in the tray for options and a test run.'
Write-Host 'Restart open Claude Code sessions so they pick up the hooks.'
Write-Host 'From now on, updates are just new files in this folder - no reinstalling.'
