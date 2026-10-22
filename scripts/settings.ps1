# Copyright (C) 2026 the windows-notch authors. Licensed GPL-3.0-or-later, see LICENSE.
# The settings window: every option in settings.json with a plain explanation, grouped by page.
# Changes are saved right away; the island notices the file changed and applies them live.
# Opened from the tray menu (Settings...), by double-clicking the tray icon, or Settings.cmd.

param([string]$Snapshot = '', [string]$StartPage = 'General')   # -Snapshot file.png: draw the window to a picture and quit (for docs and checks)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\WindowsNotch.Settings', [ref]$createdNew)
if (-not $createdNew) { return }   # already open

$Root    = Split-Path $PSScriptRoot -Parent
$CfgPath = Join-Path $Root 'settings.json'
$Island  = Join-Path $PSScriptRoot 'ClaudeIsland.ps1'
$CompDir = Join-Path $Root 'custom images'

# Defaults come straight from the island script, so there's only one list to keep up to date
$defaults = [ordered]@{}
try {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Island, [ref]$null, [ref]$null)
    $as = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:cfg' }, $true)
    $defaults = Invoke-Expression $as.Right.Extent.Text
} catch { }

$cfg = [ordered]@{}
foreach ($k in $defaults.Keys) { $cfg[$k] = $defaults[$k] }
$script:extra = [ordered]@{}   # keys in settings.json this window doesn't know, kept as they are
$script:stamp = [datetime]::MinValue
function Read-Settings {
    if (-not (Test-Path $CfgPath)) { return }
    try {
        $j = [IO.File]::ReadAllText($CfgPath) | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { if ($cfg.Contains($p.Name)) { $cfg[$p.Name] = $p.Value } else { $script:extra[$p.Name] = $p.Value } }
        $script:stamp = (Get-Item -LiteralPath $CfgPath).LastWriteTimeUtc
    } catch { }
}
function Save-Settings {
    $o = [ordered]@{}
    foreach ($k in $cfg.Keys) { $o[$k] = $cfg[$k] }
    foreach ($k in $script:extra.Keys) { $o[$k] = $script:extra[$k] }
    try {
        [IO.File]::WriteAllText($CfgPath, ($o | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
        $script:stamp = (Get-Item -LiteralPath $CfgPath).LastWriteTimeUtc
        $uiSaved.Text = 'Saved ' + (Get-Date).ToString('HH:mm:ss')
    } catch { $uiSaved.Text = "Couldn't save: " + $_.Exception.Message }
}
Read-Settings

# ---- what each option is ---------------------------------------------------------------
# type: toggle | slider (min, max, step, unit) | text | color | choice (options) | stats | mascot | startup
function S($key, $label, $desc, $type = 'toggle', $a = $null, $b = $null, $c = $null, $d = '') {
    @{ key = $key; label = $label; desc = $desc; type = $type; min = $a; max = $b; step = $c; unit = $d; options = $a }
}
$pages = [ordered]@{
    'General' = @(
        (S 'showWorking' 'Show while Claude works' 'The island shows what Claude Code is doing, with a timer.')
        (S 'sound' 'Chime' 'A soft sound when Claude finishes a task or needs your input.')
        (S 'chimeAfterSeconds' 'Chime only for longer tasks' 'Quick answers stay silent; tasks at least this long chime when they finish.' 'slider' 0 300 5 's')
        (S 'doneSeconds' '"Task complete" stays for' 'How long the finished message stays before the island moves on.' 'slider' 2 60 1 's')
        (S 'music' 'Now playing' 'When Claude is idle, show the song playing in Spotify, your browser or any media app.')
        (S 'musicPausedSeconds' 'Keep the song after pausing' 'How long the song stays on the island after you pause it.' 'slider' 0 30 1 's')
        (S 'clickThrough' 'Click through' 'Clicks go to the window under the island, so it never gets in the way. Ctrl+click it to open it.')
        (S 'peekOpacity' 'Fade under the cursor' 'With click through on, the island fades to this while your cursor is over it.' 'slider' 0 1 0.05 '%')
        (S 'sleepAfterMinutes' 'Companion naps after' 'The companion falls asleep after this long without mouse or keyboard. 0 = never.' 'slider' 0 60 1 'min')
        (S '::startup' 'Start with Windows' 'Open the island when you sign in.' 'startup')
        (S 'updateCheck' 'Check for updates' 'Once a day, look for a newer version. Nothing installs unless you click it.')
    )
    'Look' = @(
        (S 'size' 'Size' 'Scales the whole island.' 'slider' 0.5 2 0.05 'x')
        (S 'cornerRadius' 'Roundness' 'How round the corners are.' 'slider' 0 40 1 'px')
        (S 'offsetX' 'Move left or right' 'Shifts the island from the center of the screen.' 'slider' -800 800 5 'px')
        (S 'offsetY' 'Move down' 'Pushes the island down from the top edge.' 'slider' 0 400 1 'px')
        (S 'backgroundColor' 'Background color' 'The color behind the text.' 'color')
        (S 'backgroundOpacity' 'Background strength' '0% is fully see-through, 100% is solid.' 'slider' 0 1 0.05 '%')
        (S 'expandedOpacity' 'Background when open' 'Darker while the island is open, so the panels stay readable.' 'slider' 0 1 0.05 '%')
        (S 'borderOpacity' 'Outline' 'The thin line around the island.' 'slider' 0 1 0.05 '%')
        (S 'glowStrength' 'Glow' 'The colored light around the island (orange while Claude works, green when done...). 0 = off.' 'slider' 0 2 0.05 'x')
        (S 'textShadow' 'Text shadow' 'Keeps text readable over bright wallpapers.')
        (S 'blur' 'Frosted glass' 'Blurs what is behind the island. While on, the island is left out of your screenshots and recordings.')
        (S 'blurStrength' 'Glass blur amount' 'How blurry the glass is.' 'slider' 2 20 1 '')
        (S 'expandedWidth' 'Width when open' 'How wide the island gets when you open it.' 'slider' 300 800 10 'px')
        (S 'accent' 'Working color' 'Color while Claude works.' 'color')
        (S 'doneColor' 'Done color' 'Color when a task is complete.' 'color')
        (S 'needsColor' 'Needs-you color' 'Color when Claude is waiting for you.' 'color')
        (S 'mascot' 'Companion' 'The little character on the right of the island. Add your own in the custom images folder.' 'mascot')
    )
    'Notices' = @(
        (S 'popups' 'Show notices' 'Short messages in the island. While Claude or music is on, they appear in a bubble next to it. Turn off to hide them all.')
        (S 'popupSeconds' 'Notices stay for' 'How long a notice stays.' 'slider' 1 30 1 's')
        (S 'popupDownloads' 'Downloads' 'A download finished. Click it to show the file.')
        (S 'popupScreenshots' 'Screenshots' 'A screenshot was saved, with a small preview. Click it to open.')
        (S 'popupDevices' 'Devices' 'Headphones, a mouse, keyboard, USB drive or camera connected or removed.')
        (S 'popupAudioOutput' 'Sound output' 'Sound switched to other speakers or headphones.')
        (S 'popupVolume' 'Volume and brightness' 'A slim bar when you change them.')
        (S 'popupNetwork' 'Network and VPN' 'Wi-Fi or Ethernet connected or lost, VPN on or off.')
        (S 'popupBattery' 'Battery and charger' 'Charger plugged in or out, battery low. Laptops only.')
        (S 'popupLocks' 'Caps Lock and Num Lock' 'Shows when they turn on or off.')
        (S 'popupClipboard' 'Clipboard' 'A short preview of what you copied. Password managers are skipped.')
        (S 'popupFocus' 'Do Not Disturb' 'Shows when Focus turns on or off.')
        (S 'popupGitHub' 'GitHub pull requests' 'Your open PRs: checks passed or failed, approved. Needs the GitHub CLI, signed in.')
        (S 'calendarIcsUrl' 'Calendar link' 'Your calendar''s private iCal (.ics) address, for "meeting in 5 minutes" reminders. Leave empty for none.' 'text')
        (S 'calendarMinutes' 'Remind me before meetings' 'How early the meeting reminder shows.' 'slider' 1 30 1 'min')
    )
    'Fullscreen' = @(
        (S 'fullscreenNotch' 'Slim notch in fullscreen' 'While a game or video is fullscreen, a small black tab at the top replaces the island.')
        (S 'fullscreenClock' 'Clock in the notch' 'In fullscreen, the notch shows the time when nothing else is going on.')
    )
    'Stats and weather' = @(
        (S 'stats' 'System stats when idle' 'When nothing else is on, the island shows your PC''s stats.')
        (S 'statsItems' 'Which stats' 'Pick what shows in the island when idle.' 'stats')
        (S 'weatherCity' 'Weather city' 'Your city (for example Istanbul) for the weather button. Leave empty for none.' 'text')
    )
    'Timer' = @(
        (S 'timerMinutes' 'Focus length' 'Pomodoro timer: how long you focus (tray menu > Timer).' 'slider' 5 120 5 'min')
        (S 'breakMinutes' 'Break length' 'Pomodoro timer: how long the break is.' 'slider' 1 60 1 'min')
    )
    'Animations' = @(
        (S 'showMs' 'Pop in' 'How long the island takes to appear.' 'slider' 0 1500 10 'ms')
        (S 'hideMs' 'Shrink away' 'How long it takes to disappear.' 'slider' 0 1500 10 'ms')
        (S 'switchMs' 'Bounce on change' 'The little bounce when what it shows changes.' 'slider' 0 1500 10 'ms')
        (S 'resizeMs' 'Resize' 'The island smoothly changing size.' 'slider' 0 1500 10 'ms')
        (S 'expandMs' 'Open and close' 'Opening and closing the panels.' 'slider' 0 1500 10 'ms')
        (S 'textMs' 'Text change' 'Old text fading out and new text in.' 'slider' 0 1500 10 'ms')
        (S 'musicTrackMs' 'Song change' 'Cross-fade between songs.' 'slider' 0 3000 50 'ms')
        (S 'resizeOverlap' 'Width and height together' '0% = width first, then height. 100% = both at once.' 'slider' 0 1 0.05 '%')
        (S 'solidDuringResize' 'Solid while resizing' 'With frosted glass on, turn solid while the island resizes, which looks smoother.' 'choice' @(@('grow', 'When growing'), @('both', 'Always'), @('off', 'Never')))
        (S 'solidFadeMs' 'Fade to solid' 'How long the fade to solid and back takes.' 'slider' 0 1000 10 'ms')
        (S 'blurRefreshMs' 'Glass refresh' 'How often the glass updates what''s behind it. Lower is smoother but uses more CPU.' 'slider' 30 1000 10 'ms')
        (S 'fps' 'Frame rate' '0 = match your monitor. Applies after a restart (tray menu > Restart).' 'slider' 0 240 10 'fps')
    )
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Notch settings" Width="820" Height="640" MinWidth="680" MinHeight="460"
        WindowStartupLocation="CenterScreen" Background="#161618" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display" FontFamily="Segoe UI Variable Text, Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="Accent" Color="#D97857"/>
    <!-- switch -->
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Border x:Name="Track" Width="40" Height="22" CornerRadius="11" Background="#3A3A3E">
            <Ellipse x:Name="Knob" Width="16" Height="16" Fill="#E6FFFFFF" HorizontalAlignment="Left" Margin="3,0,0,0"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="Track" Property="Background" Value="#D97857"/>
              <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
              <Setter TargetName="Knob" Property="Margin" Value="0,0,3,0"/>
              <Setter TargetName="Knob" Property="Fill" Value="#FFFFFFFF"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <!-- slider -->
    <Style x:Key="TrackFill" TargetType="RepeatButton">
      <Setter Property="OverridesDefaultStyle" Value="True"/><Setter Property="Focusable" Value="False"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RepeatButton">
        <Border Height="4" CornerRadius="2" Background="#D97857"/></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="TrackEmpty" TargetType="RepeatButton">
      <Setter Property="OverridesDefaultStyle" Value="True"/><Setter Property="Focusable" Value="False"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RepeatButton">
        <Border Height="4" CornerRadius="2" Background="#3A3A3E"/></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="Slider">
      <Setter Property="IsMoveToPointEnabled" Value="True"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Slider">
        <Track x:Name="PART_Track" Height="22">
          <Track.DecreaseRepeatButton><RepeatButton Style="{StaticResource TrackFill}" Command="Slider.DecreaseLarge"/></Track.DecreaseRepeatButton>
          <Track.IncreaseRepeatButton><RepeatButton Style="{StaticResource TrackEmpty}" Command="Slider.IncreaseLarge"/></Track.IncreaseRepeatButton>
          <Track.Thumb><Thumb><Thumb.Template><ControlTemplate>
            <Ellipse Width="16" Height="16" Fill="#FFFFFFFF" Stroke="#40000000" StrokeThickness="1"/>
          </ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
        </Track>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <!-- pill buttons (page list, choices, companions, stats) -->
    <Style x:Key="Pick" TargetType="ToggleButton">
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Foreground" Value="#CCFFFFFF"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton">
        <Border x:Name="B" CornerRadius="14" Padding="12,5,12,6" Margin="0,0,6,6" Background="#26FFFFFF">
          <ContentPresenter/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#3DFFFFFF"/></Trigger>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="B" Property="Background" Value="#D97857"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Nav" TargetType="ToggleButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ToggleButton">
        <Border x:Name="B" CornerRadius="8" Padding="14,9" Margin="0,0,0,2" Background="Transparent">
          <TextBlock x:Name="T" Text="{TemplateBinding Content}" Foreground="#B3FFFFFF" FontSize="13.5"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#14FFFFFF"/></Trigger>
          <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="B" Property="Background" Value="#26FFFFFF"/>
            <Setter TargetName="T" Property="Foreground" Value="#FFFFFFFF"/><Setter TargetName="T" Property="FontWeight" Value="SemiBold"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Plain" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="B" CornerRadius="8" Padding="12,6" Background="#26FFFFFF">
          <TextBlock Text="{TemplateBinding Content}" Foreground="#E6FFFFFF" FontSize="12.5"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#3DFFFFFF"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#26FFFFFF"/><Setter Property="Foreground" Value="#FFFFFFFF"/>
      <Setter Property="BorderBrush" Value="#33FFFFFF"/><Setter Property="CaretBrush" Value="#FFFFFFFF"/>
      <Setter Property="Padding" Value="6,4"/><Setter Property="FontSize" Value="12.5"/>
    </Style>
  </Window.Resources>
  <DockPanel Background="#161618">
    <!-- left: pages -->
    <Border DockPanel.Dock="Left" Width="200" Background="#111113" Padding="12,18,12,12">
      <DockPanel>
        <StackPanel DockPanel.Dock="Top" Margin="6,0,0,18">
          <TextBlock Text="Windows Notch" Foreground="#FFFFFFFF" FontSize="17" FontWeight="SemiBold"
                     FontFamily="Segoe UI Variable Display, Segoe UI"/>
          <TextBlock x:Name="Ver" Foreground="#80FFFFFF" FontSize="11.5" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel x:Name="Nav"/>
      </DockPanel>
    </Border>
    <!-- bottom bar -->
    <Border DockPanel.Dock="Bottom" Background="#111113" Padding="20,10">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="BtnReset" Style="{StaticResource Plain}" Content="Reset this page" Margin="0,0,8,0"/>
          <Button x:Name="BtnFile" Style="{StaticResource Plain}" Content="Open settings.json"/>
        </StackPanel>
        <TextBlock x:Name="Saved" Foreground="#80FFFFFF" FontSize="12" VerticalAlignment="Center"
                   Text="Changes apply right away."/>
      </DockPanel>
    </Border>
    <!-- right: the options of the chosen page -->
    <ScrollViewer x:Name="Scroll" VerticalScrollBarVisibility="Auto" Padding="28,20,28,20">
      <StackPanel>
        <TextBlock x:Name="PageTitle" Foreground="#FFFFFFFF" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,14"
                   FontFamily="Segoe UI Variable Display, Segoe UI"/>
        <StackPanel x:Name="Rows"/>
      </StackPanel>
    </ScrollViewer>
  </DockPanel>
</Window>
"@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
foreach ($n in 'Nav', 'Rows', 'PageTitle', 'Saved', 'BtnReset', 'BtnFile', 'Ver', 'Scroll') { Set-Variable -Name ("ui" + $n) -Value $win.FindName($n) -Scope Script }
try { $uiVer.Text = 'v' + ([IO.File]::ReadAllText((Join-Path $Root 'VERSION'))).Trim() } catch { }

function New-Brush($hex) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }
function Text($s, $size, $color, $weight = 'Normal') {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $s; $t.FontSize = $size; $t.Foreground = New-Brush $color; $t.FontWeight = $weight; $t.TextWrapping = 'Wrap'
    $t
}
function New-Pick($content, [bool]$on) {
    $b = New-Object System.Windows.Controls.Primitives.ToggleButton
    $b.Style = $win.FindResource('Pick'); $b.IsChecked = $on
    $b.Content = Text $content 12.5 '#FFFFFFFF'
    $b
}

# Saving waits a moment while a slider is being dragged or text typed, so the island isn't
# re-read on every pixel
$saveTimer = New-Object System.Windows.Threading.DispatcherTimer
$saveTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$saveTimer.Add_Tick({ $saveTimer.Stop(); Save-Settings })
function Set-Value($key, $value) { $cfg[$key] = $value; $saveTimer.Stop(); $saveTimer.Start() }

function Format-Value($s, $v) {
    switch ($s.unit) {
        '%' { '{0}%' -f [int][math]::Round([double]$v * 100) }
        'x' { '{0:0.##}x' -f [double]$v }
        '' { '{0}' -f $v }
        default { if ($s.key -eq 'fps' -and [double]$v -eq 0) { 'auto' } elseif ($s.key -eq 'sleepAfterMinutes' -and [double]$v -eq 0) { 'never' } else { '{0} {1}' -f $v, $s.unit } }
    }
}

# Startup shortcut, the same one the tray menu makes
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Windows Notch.lnk'
function Set-Autostart([bool]$on) {
    try {
        if ($on) {
            $ws = New-Object -ComObject WScript.Shell
            $lnk = $ws.CreateShortcut($startupLnk)
            $lnk.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Island`""
            $lnk.WindowStyle = 7; $lnk.Description = 'Windows Notch'; $lnk.Save()
        } else { Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function New-Row($s) {
    $row = New-Object System.Windows.Controls.Border
    $row.Background = New-Brush '#1E1E21'; $row.CornerRadius = 10; $row.Padding = New-Object System.Windows.Thickness(16, 12, 16, 12)
    $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
    $dp = New-Object System.Windows.Controls.DockPanel
    $wide = @('mascot', 'stats', 'choice') -contains $s.type
    $ctl = $null
    switch ($s.type) {
        'toggle' {
            $ctl = New-Object System.Windows.Controls.CheckBox
            $ctl.Style = $win.FindResource('Switch'); $ctl.IsChecked = [bool]$cfg[$s.key]; $ctl.Tag = $s.key; $ctl.VerticalAlignment = 'Center'
            $ctl.Add_Click({ Set-Value ([string]$this.Tag) ([bool]$this.IsChecked) })
            $row.Cursor = [System.Windows.Input.Cursors]::Hand; $row.Tag = $ctl   # the whole row flips it
            $row.Add_MouseLeftButtonUp({ param($o, $e) $c = $o.Tag; if (-not $c.IsMouseOver) { $c.IsChecked = -not $c.IsChecked; Set-Value ([string]$c.Tag) ([bool]$c.IsChecked) } })
        }
        'startup' {
            $ctl = New-Object System.Windows.Controls.CheckBox
            $ctl.Style = $win.FindResource('Switch'); $ctl.IsChecked = (Test-Path -LiteralPath $startupLnk); $ctl.VerticalAlignment = 'Center'
            $ctl.Add_Click({ Set-Autostart ([bool]$this.IsChecked); $this.IsChecked = (Test-Path -LiteralPath $startupLnk); $uiSaved.Text = 'Saved ' + (Get-Date).ToString('HH:mm:ss') })
        }
        'slider' {
            $ctl = New-Object System.Windows.Controls.DockPanel; $ctl.Width = 260; $ctl.VerticalAlignment = 'Center'
            $val = Text '' 12.5 '#CCFFFFFF'; $val.Width = 64; $val.TextAlignment = 'Right'; $val.FontFamily = New-Object System.Windows.Media.FontFamily 'Cascadia Mono, Consolas'
            $val.VerticalAlignment = 'Center'
            [System.Windows.Controls.DockPanel]::SetDock($val, 'Right'); [void]$ctl.Children.Add($val)
            $sl = New-Object System.Windows.Controls.Slider
            $sl.Minimum = [double]$s.min; $sl.Maximum = [double]$s.max; $sl.SmallChange = [double]$s.step; $sl.LargeChange = [double]$s.step
            $sl.TickFrequency = [double]$s.step; $sl.IsSnapToTickEnabled = $true
            $sl.Value = [math]::Max([double]$s.min, [math]::Min([double]$s.max, [double]$cfg[$s.key])); $sl.VerticalAlignment = 'Center'
            $val.Text = Format-Value $s $cfg[$s.key]
            $sl.Tag = @{ s = $s; val = $val }
            $sl.Add_ValueChanged({
                $t = $this.Tag; $v = [math]::Round($this.Value, 2)
                if ([double]$t.s.step -ge 1) { $v = [int]$v }
                $t.val.Text = Format-Value $t.s $v
                Set-Value $t.s.key $v
            })
            [void]$ctl.Children.Add($sl)
        }
        'text' {
            $ctl = New-Object System.Windows.Controls.TextBox
            $ctl.Width = 260; $ctl.Text = [string]$cfg[$s.key]; $ctl.Tag = $s.key; $ctl.VerticalAlignment = 'Center'
            $ctl.Add_TextChanged({ Set-Value ([string]$this.Tag) $this.Text.Trim() })
        }
        'color' {
            $ctl = New-Object System.Windows.Controls.StackPanel; $ctl.Orientation = 'Horizontal'; $ctl.VerticalAlignment = 'Center'
            $sw = New-Object System.Windows.Controls.Border
            $sw.Width = 28; $sw.Height = 28; $sw.CornerRadius = 14; $sw.BorderBrush = New-Brush '#40FFFFFF'; $sw.BorderThickness = 1
            $sw.Cursor = [System.Windows.Input.Cursors]::Hand; $sw.ToolTip = 'Pick a color'
            try { $sw.Background = New-Brush ([string]$cfg[$s.key]) } catch { }
            $tb = New-Object System.Windows.Controls.TextBox
            $tb.Width = 96; $tb.Text = [string]$cfg[$s.key]; $tb.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
            $tb.FontFamily = New-Object System.Windows.Media.FontFamily 'Cascadia Mono, Consolas'
            $state = @{ key = $s.key; sw = $sw; tb = $tb }
            $tb.Tag = $state; $sw.Tag = $state
            $tb.Add_TextChanged({
                $st = $this.Tag; $t = $this.Text.Trim()
                if ($t -match '^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$') { $st.sw.Background = New-Brush $t; Set-Value $st.key $t.ToUpper() }
            })
            $sw.Add_MouseLeftButtonUp({
                $st = $this.Tag
                $d = New-Object System.Windows.Forms.ColorDialog; $d.FullOpen = $true
                try { $c = [System.Drawing.ColorTranslator]::FromHtml($st.tb.Text.Trim()); $d.Color = $c } catch { }
                if ($d.ShowDialog() -eq 'OK') { $st.tb.Text = '#{0:X2}{1:X2}{2:X2}' -f $d.Color.R, $d.Color.G, $d.Color.B }
            })
            [void]$ctl.Children.Add($sw); [void]$ctl.Children.Add($tb)
        }
        'choice' {
            $ctl = New-Object System.Windows.Controls.WrapPanel; $ctl.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
            $group = New-Object System.Collections.ArrayList
            foreach ($o in $s.options) {
                $b = New-Pick $o[1] ([string]$cfg[$s.key] -eq $o[0])
                $b.Tag = @{ key = $s.key; value = $o[0]; group = $group }
                [void]$group.Add($b)
                $b.Add_Click({ $t = $this.Tag; foreach ($x in $t.group) { $x.IsChecked = ($x -eq $this) }; Set-Value $t.key $t.value })
                [void]$ctl.Children.Add($b)
            }
        }
        'stats' {
            $ctl = New-Object System.Windows.Controls.WrapPanel; $ctl.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
            $all = @(@('cpu', 'CPU'), @('gpu', 'GPU'), @('ram', 'RAM'), @('net', 'Network speed'), @('weather', 'Weather'))
            $cur = @(([string]$cfg.statsItems).ToLower() -split '[,\s]+')
            foreach ($o in $all) {
                $b = New-Pick $o[1] ($cur -contains $o[0]); $b.Tag = $o[0]
                $b.Add_Click({
                    $keys = @('cpu', 'gpu', 'ram', 'net', 'weather')
                    $on = @($this.Parent.Children | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
                    Set-Value 'statsItems' (@($keys | Where-Object { $on -contains $_ }) -join ',')
                })
                [void]$ctl.Children.Add($b)
            }
        }
        'mascot' {
            $ctl = New-Object System.Windows.Controls.WrapPanel; $ctl.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
            $names = @(@('off', 'Off'))
            foreach ($c in 'cloud', 'clay', 'honey', 'sage', 'ocean', 'plum') { $names += , @($c, ('Sprout (' + $c + ')')) }
            if (Test-Path -LiteralPath $CompDir) {
                foreach ($d in @(Get-ChildItem -LiteralPath $CompDir -Directory | Sort-Object Name)) { $names += , @($d.Name, $d.Name) }
            }
            $group = New-Object System.Collections.ArrayList
            foreach ($o in $names) {
                $b = New-Pick $o[1] ([string]$cfg.mascot -eq $o[0])
                $b.Tag = @{ value = $o[0]; group = $group }
                [void]$group.Add($b)
                $b.Add_Click({ $t = $this.Tag; foreach ($x in $t.group) { $x.IsChecked = ($x -eq $this) }; Set-Value 'mascot' $t.value })
                [void]$ctl.Children.Add($b)
            }
            $open = New-Object System.Windows.Controls.Button
            $open.Style = $win.FindResource('Plain'); $open.Content = 'Open custom images folder'; $open.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
            $open.Add_Click({ New-Item -ItemType Directory -Force -Path $CompDir | Out-Null; Start-Process explorer.exe "`"$CompDir`"" })
            [void]$ctl.Children.Add($open)
        }
    }
    $words = New-Object System.Windows.Controls.StackPanel; $words.VerticalAlignment = 'Center'
    [void]$words.Children.Add((Text $s.label 13.5 '#FFFFFFFF' 'SemiBold'))
    $dsc = Text $s.desc 12 '#8CFFFFFF'; $dsc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$words.Children.Add($dsc)
    if ($wide) {
        $sp = New-Object System.Windows.Controls.StackPanel
        [void]$sp.Children.Add($words); [void]$sp.Children.Add($ctl)
        $row.Child = $sp
    } else {
        $ctl.Margin = New-Object System.Windows.Thickness(20, 0, 0, 0)
        [System.Windows.Controls.DockPanel]::SetDock($ctl, 'Right')
        [void]$dp.Children.Add($ctl); [void]$dp.Children.Add($words)
        $row.Child = $dp
    }
    $row
}

$script:page = ''
function Show-Page($name) {
    $script:page = $name
    $uiPageTitle.Text = $name
    $uiRows.Children.Clear()
    foreach ($s in $pages[$name]) { [void]$uiRows.Children.Add((New-Row $s)) }
    foreach ($b in $uiNav.Children) { $b.IsChecked = ([string]$b.Content -eq $name) }
    $uiScroll.ScrollToTop()
}
foreach ($name in $pages.Keys) {
    $b = New-Object System.Windows.Controls.Primitives.ToggleButton
    $b.Style = $win.FindResource('Nav'); $b.Content = $name
    $b.Add_Click({ Show-Page ([string]$this.Content) })
    [void]$uiNav.Children.Add($b)
}
$uiBtnReset.Add_Click({
    $r = [System.Windows.MessageBox]::Show("Put every option on the $($script:page) page back to its default?", 'Windows Notch', 'OKCancel', 'Question')
    if ($r -ne 'OK') { return }
    foreach ($s in $pages[$script:page]) { if ($defaults.Contains($s.key)) { $cfg[$s.key] = $defaults[$s.key] } }
    Save-Settings; Show-Page $script:page
})
$uiBtnFile.Add_Click({ Start-Process notepad.exe "`"$CfgPath`"" })
# settings.json changed elsewhere (the tray menu, a text editor): show the new values
$win.Add_Activated({
    try {
        if ((Test-Path $CfgPath) -and (Get-Item -LiteralPath $CfgPath).LastWriteTimeUtc -ne $script:stamp -and -not $saveTimer.IsEnabled) { Read-Settings; Show-Page $script:page }
    } catch { }
})
$win.Add_Closing({ if ($saveTimer.IsEnabled) { $saveTimer.Stop(); Save-Settings } })

Show-Page $(if ($pages.Contains($StartPage)) { $StartPage } else { 'General' })
if ($Snapshot) {
    $win.WindowStartupLocation = 'Manual'; $win.Left = -5000; $win.Top = 0; $win.ShowActivated = $false; $win.Show()
    $win.Dispatcher.Invoke([Action]{ }, 'ApplicationIdle')
    $c = $win.Content
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$c.ActualWidth, [int]$c.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($c)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($Snapshot); $enc.Save($fs); $fs.Close(); $win.Close()
} else { [void]$win.ShowDialog() }
$mutex.ReleaseMutex()
