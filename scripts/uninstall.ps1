# Claude Island uninstaller: removes the Claude Code hooks and the startup shortcut,
# and stops the island. Your folder (custom images, settings.json) is left alone -
# delete it yourself if you want everything gone.
$ErrorActionPreference = 'Continue'

$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path $settingsPath) {
    $text = Get-Content $settingsPath -Raw
    if ($text -and $text.Trim()) {
        Copy-Item $settingsPath "$settingsPath.bak-claudeisland-uninstall" -Force
        $settings = $text | ConvertFrom-Json
        if ($settings.PSObject.Properties['hooks']) {
            foreach ($p in @($settings.hooks.PSObject.Properties)) {
                $kept = @(@($p.Value) | Where-Object { $_ -and -not ((@($_.hooks) | ForEach-Object { [string]$_.command }) -join ' ' -match 'ClaudeIsland|island-hook\.ps1') })
                if ($kept.Count -eq 0) { $settings.hooks.PSObject.Properties.Remove($p.Name) }
                else { $settings.hooks | Add-Member -NotePropertyName $p.Name -NotePropertyValue $kept -Force }
            }
            if (@($settings.hooks.PSObject.Properties).Count -eq 0) { $settings.PSObject.Properties.Remove('hooks') }
        }
        [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding $false))
        Write-Host 'Removed Claude Code hooks.'
    }
}

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'ClaudeIsland\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Island.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA 'ClaudeIsland') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'state') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Claude Island stopped and removed. This folder is still here with your custom images and settings.' -ForegroundColor Green
