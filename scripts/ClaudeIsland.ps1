# Claude Island - a Dynamic-Island-style pill for Windows.
# Lives in <island folder>\scripts. Settings: <island folder>\settings.json (applied live).
# Companions: <island folder>\companions\<name>\ (see the README there).
# Replacing this file (or the hook) is all an update needs: the island restarts itself.
#  * Claude Code status: working / needs your input / task complete (model, tokens, API value)
#  * Now playing: album art, title, artist, equalizer; hover for progress and controls
#  * A little mascot that blinks, glances around and hops when a task finishes
# Ideas, price table, mascot palette and pulse timing adapted from Vorssaint (GPL-3.0),
# https://github.com/vorssaint/vorssaint-utils - for personal use.
#
# Draws its own window instead of using Windows notifications, so Focus / Do Not
# Disturb doesn't hide it and nothing lands in the notification center.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$script:SelfPath = $PSCommandPath
$Root     = Split-Path $PSScriptRoot -Parent
$StateDir = Join-Path $Root 'state'
$SessDir  = Join-Path $StateDir 'sessions'
$CompDir  = Join-Path $Root 'companions'
$CfgPath  = Join-Path $Root 'settings.json'
$oldCfg   = Join-Path $Root 'config.json'
if ((Test-Path $oldCfg) -and -not (Test-Path $CfgPath)) { try { Move-Item $oldCfg $CfgPath } catch { } }
$LogPath  = Join-Path $StateDir 'island.log'
New-Item -ItemType Directory -Force -Path $SessDir, $CompDir | Out-Null

# ---- single instance ------------------------------------------------------
$createdNew = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudeIsland.Overlay', [ref]$createdNew)
if (-not $createdNew) { return }

# ---- config ---------------------------------------------------------------
# Defaults. settings.json in the island folder overrides them; it's rewritten in this
# order (with any new options added) and re-read live whenever you save it.
$script:cfg = [ordered]@{
    # --- look
    backgroundOpacity  = 0.55       # 0 = fully see-through, 1 = solid
    backgroundColor    = '#0B0B0D'
    borderOpacity      = 0.15       # thin outline around the pill
    glowStrength       = 1.0        # colored glow around the pill, 0 = off
    textShadow         = $true      # keeps text readable over bright backgrounds
    blur               = $true      # frosted glass behind the pill (while on, the island is left out of screenshots/recordings)
    blurStrength       = 8          # how blurry the glass is, 2 to 20
    blurRefreshMs      = 100        # how often the glass refreshes what's behind it
    solidDuringResize  = 'grow'     # with blur on, turn the pill solid while it resizes: grow, both or off
    solidFadeMs        = 150        # how long the fade to solid (before) and back to glass (after) takes
    size               = 1.0        # scale everything, e.g. 0.85 smaller, 1.2 bigger
    cornerRadius       = 24
    offsetX            = 0          # move left (-) / right (+) from the center, in pixels
    offsetY            = 0          # move down from the top edge, in pixels
    # --- transitions (milliseconds, 0 = instant)
    fps                = 0          # animation frame rate; 0 = match your fastest monitor's refresh rate
    showMs             = 460        # pop in
    hideMs             = 220        # shrink away
    switchMs           = 380        # little bounce when the content changes
    resizeMs           = 320        # pill smoothly changing size when its content changes
    resizeOverlap      = 0.6        # 0 = width first, then height; 1 = both together; 0.8 = height starts when width is 20% done
    textMs             = 260        # changed text cross-fades (old out, new in)
    expandMs           = 360        # hover panel opening/closing: widens first, then grows down (total)
    musicTrackMs       = 250        # cross-fade between songs
    # --- behavior
    sound              = $true      # soft chime on done / needs input
    chimeAfterSeconds  = 20         # only chime for tasks that ran at least this long
    doneSeconds        = 8          # how long the "Task complete" pill stays
    showWorking        = $true      # show the pill while Claude is working
    music              = $true      # show what's playing when Claude is idle
    musicPausedSeconds = 4          # keep the music pill this long after pausing
    clickThrough       = $true      # clicks go through the pill to what's under it; hold Ctrl to hover/click the pill
    peekOpacity        = 0.25       # with click-through on, the pill fades to this while the cursor is over it (1 = no fade)
    mascot             = 'pearl'    # off, a blob color (pearl, lemon, peach, rose, lilac, sky, mint) or a companions folder name
    # --- colors
    accent             = '#D97857'  # working (Claude coral)
    doneColor          = '#34C759'
    needsColor         = '#FFB340'
}
function Write-Log($m) { try { Add-Content -Path $LogPath -Value ("{0:u} {1}" -f (Get-Date), $m) } catch { } }
$script:cfgDefaults = [ordered]@{}; foreach ($k in @($script:cfg.Keys)) { $script:cfgDefaults[$k] = $script:cfg[$k] }
$script:cfgStamp = [datetime]::MinValue
function Read-Config {
    if (-not (Test-Path $CfgPath)) { return $false }
    try {
        $script:cfgStamp = (Get-Item $CfgPath).LastWriteTimeUtc
        $j = [IO.File]::ReadAllText($CfgPath) | ConvertFrom-Json
        $names = @($j.PSObject.Properties | ForEach-Object { $_.Name })
        $j.PSObject.Properties | ForEach-Object { $script:cfg[$_.Name] = $_.Value }
        $script:cfgMissing = @($script:cfgDefaults.Keys | Where-Object { $names -notcontains $_ }).Count -gt 0
        return $true
    } catch { Write-Log ("settings.json: " + $_.Exception.Message); return $false }
}
function Save-Config {
    try {
        $o = [ordered]@{}
        foreach ($k in @($script:cfgDefaults.Keys)) { $o[$k] = $script:cfg[$k] }
        [IO.File]::WriteAllText($CfgPath, ($o | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
        $script:cfgStamp = (Get-Item $CfgPath).LastWriteTimeUtc
    } catch { }
}
$script:cfgMissing = $false
if (-not (Read-Config) -or $script:cfgMissing) { Save-Config }   # writes every option (and new ones after updates) so you can see them

$INV = [System.Globalization.CultureInfo]::InvariantCulture
$ELL = [string][char]0x2026   # ellipsis
$DOT = [string][char]0x00B7   # middle dot
$GLYPH_PLAY  = [string][char]0xE768
$GLYPH_PAUSE = [string][char]0xE769

# Mascot palette (light top, shaded bottom), from Vorssaint
$script:mascotColors = [ordered]@{
    pearl = @('#FCFAF5', '#D6D9E6'); lemon = @('#FFF5A3', '#F7D44D'); peach = @('#FFDBBD', '#FAA380')
    rose  = @('#FFCCDE', '#F28AAD'); lilac = @('#E0D4FF', '#B096F5'); sky   = @('#C4E6FF', '#6EABF7')
    mint  = @('#B8F7DB', '#66D4A8')
}

# ---- Win32: keep it out of Alt+Tab and never steal focus -------------------
if (-not ('IslandNative' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class IslandNative {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] static extern bool SetWindowDisplayAffinity(IntPtr h, uint affinity);
    // Leave the island out of screen captures, so the glass only ever sees what is behind it.
    public static bool ExcludeFromCapture(IntPtr h, bool on) { return SetWindowDisplayAffinity(h, on ? 0x11u : 0u); }

    // Frosted glass: copy the screen behind the pill, shrink it (which averages pixels) and
    // soften it with a few box-blur passes. Returns the small image as BGRA bytes.
    public static byte[] CaptureBlur(int x, int y, int w, int h, int k, int passes, out int sw, out int sh) {
        sw = Math.Max(2, w / k); sh = Math.Max(2, h / k);
        using (var full = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
            using (var g = Graphics.FromImage(full)) g.CopyFromScreen(x, y, 0, 0, new Size(w, h), CopyPixelOperation.SourceCopy);
            using (var small = new Bitmap(sw, sh, PixelFormat.Format32bppArgb)) {
                using (var g2 = Graphics.FromImage(small))
                using (var ia = new ImageAttributes()) {
                    ia.SetWrapMode(WrapMode.TileFlipXY);
                    g2.InterpolationMode = InterpolationMode.HighQualityBilinear;
                    g2.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g2.DrawImage(full, new Rectangle(0, 0, sw, sh), 0, 0, w, h, GraphicsUnit.Pixel, ia);
                }
                var data = small.LockBits(new Rectangle(0, 0, sw, sh), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                var px = new byte[sw * sh * 4];
                for (int row = 0; row < sh; row++) Marshal.Copy(IntPtr.Add(data.Scan0, row * data.Stride), px, row * sw * 4, sw * 4);
                small.UnlockBits(data);
                for (int p = 0; p < passes; p++) { BoxBlur(px, sw, sh, true); BoxBlur(px, sw, sh, false); }
                for (int i = 3; i < px.Length; i += 4) px[i] = 255;
                return px;
            }
        }
    }
    static void BoxBlur(byte[] px, int w, int h, bool horizontal) {
        var src = (byte[])px.Clone();
        int outer = horizontal ? h : w, inner = horizontal ? w : h;
        for (int o = 0; o < outer; o++) {
            for (int i = 0; i < inner; i++) {
                int s0 = 0, s1 = 0, s2 = 0;
                for (int d = -1; d <= 1; d++) {
                    int j = Math.Min(inner - 1, Math.Max(0, i + d));
                    int idx = horizontal ? (o * w + j) * 4 : (j * w + o) * 4;
                    s0 += src[idx]; s1 += src[idx + 1]; s2 += src[idx + 2];
                }
                int t = horizontal ? (o * w + i) * 4 : (i * w + o) * 4;
                px[t] = (byte)(s0 / 3); px[t + 1] = (byte)(s1 / 3); px[t + 2] = (byte)(s2 / 3);
            }
        }
    }

    // Album art: turn the WinRT stream Windows gives us into a classic COM IStream and read it all.
    [DllImport("shcore.dll")] static extern int CreateStreamOverRandomAccessStream(
        [MarshalAs(UnmanagedType.IUnknown)] object ras, ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppv);
    public static byte[] ReadWinRtStream(object ras) {
        Guid iid = new Guid("0000000c-0000-0000-C000-000000000046");
        object o;
        int hr = CreateStreamOverRandomAccessStream(ras, ref iid, out o);
        if (hr != 0) Marshal.ThrowExceptionForHR(hr);
        var st = (System.Runtime.InteropServices.ComTypes.IStream)o;
        var ms = new System.IO.MemoryStream();
        var buf = new byte[65536];
        IntPtr pRead = Marshal.AllocHGlobal(4);
        try {
            for (int i = 0; i < 1024; i++) {
                st.Read(buf, buf.Length, pRead);
                int n = Marshal.ReadInt32(pRead);
                if (n <= 0) break;
                ms.Write(buf, 0, n);
            }
        } finally { Marshal.FreeHGlobal(pRead); Marshal.ReleaseComObject(o); }
        return ms.ToArray();
    }
}
"@
}

# ---- UI -------------------------------------------------------------------
# ---- animation frame rate: WPF defaults to 60 fps; run at the monitor's refresh rate instead
$script:fps = 60
try {
    $want = [int]$script:cfg.fps
    if ($want -le 0) {
        $rates = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { [int]$_.CurrentRefreshRate } | Where-Object { $_ -gt 0 })
        $want = if ($rates.Count) { ($rates | Measure-Object -Maximum).Maximum } else { 60 }
    }
    $script:fps = [math]::Max(30, [math]::Min(360, $want))
    [System.Windows.Media.Animation.Timeline]::DesiredFrameRateProperty.OverrideMetadata(
        [System.Windows.Media.Animation.Timeline], (New-Object System.Windows.FrameworkPropertyMetadata([object][int]$script:fps)))
} catch { Write-Log ("frame rate: " + $_.Exception.Message) }

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Island" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False"
        ShowActivated="False" ResizeMode="NoResize" SizeToContent="Manual" Width="760" Height="380"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Grid x:Name="RootGrid" Margin="36,12,36,36">
    <Grid.LayoutTransform><ScaleTransform x:Name="RootScale" ScaleX="1" ScaleY="1"/></Grid.LayoutTransform>
    <Border x:Name="Pill" Background="Transparent" CornerRadius="24" BorderBrush="#26FFFFFF"
            HorizontalAlignment="Center" VerticalAlignment="Top"
            BorderThickness="1" Padding="0" Opacity="0"
            RenderTransformOrigin="0.5,0" Cursor="Hand" IsHitTestVisible="False">
      <Border.RenderTransform><ScaleTransform ScaleX="0.6" ScaleY="0.6"/></Border.RenderTransform>
      <Border.Effect><DropShadowEffect Color="#D97857" BlurRadius="30" ShadowDepth="0" Opacity="0.55"/></Border.Effect>
      <Grid>
      <Rectangle x:Name="Glass" RadiusX="23" RadiusY="23" RenderOptions.BitmapScalingMode="Linear"/>
      <Rectangle x:Name="Tint" RadiusX="23" RadiusY="23" Fill="#8C0B0B0D"/>
      <Grid x:Name="SizeHost" ClipToBounds="True">
      <StackPanel x:Name="Inner" Margin="10,8,14,8" HorizontalAlignment="Stretch" VerticalAlignment="Top">
        <DockPanel LastChildFill="True">

          <!-- Mascot (right end) -->
          <Grid x:Name="Mascot" DockPanel.Dock="Right" Margin="12,0,2,0" VerticalAlignment="Center" Background="Transparent">
            <Grid.RenderTransform>
              <TransformGroup><TranslateTransform/><TranslateTransform/></TransformGroup>
            </Grid.RenderTransform>
            <Image x:Name="CompImg" Width="26" Height="26" Visibility="Collapsed" Stretch="Uniform" RenderTransformOrigin="0.5,1">
              <Image.RenderTransform><ScaleTransform/></Image.RenderTransform>
            </Image>
            <Canvas x:Name="Blob" Width="22" Height="20">
            <Ellipse Width="22" Height="20">
              <Ellipse.Fill>
                <LinearGradientBrush StartPoint="0.3,0" EndPoint="0.6,1">
                  <GradientStop x:Name="MLight" Color="#FCFAF5" Offset="0.1"/>
                  <GradientStop x:Name="MShade" Color="#D6D9E6" Offset="1"/>
                </LinearGradientBrush>
              </Ellipse.Fill>
            </Ellipse>
            <Ellipse Canvas.Left="4" Canvas.Top="2.6" Width="6" Height="3.4" Fill="#A6FFFFFF"/>
            <Canvas x:Name="Eyes" Width="22" Height="20" RenderTransformOrigin="0.5,0.55">
              <Canvas.RenderTransform>
                <TransformGroup><ScaleTransform/><ScaleTransform/><TranslateTransform/></TransformGroup>
              </Canvas.RenderTransform>
              <Ellipse x:Name="EyeL" Canvas.Left="6.2" Canvas.Top="7.8" Width="3.2" Height="4.8" Fill="#121214"/>
              <Ellipse x:Name="EyeR" Canvas.Left="12.6" Canvas.Top="7.8" Width="3.2" Height="4.8" Fill="#121214"/>
              <Path x:Name="HappyL" Data="M5.6,11.4 Q7.8,7.6 10,11.4" Stroke="#121214" StrokeThickness="1.7"
                    StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Collapsed"/>
              <Path x:Name="HappyR" Data="M12,11.4 Q14.2,7.6 16.4,11.4" Stroke="#121214" StrokeThickness="1.7"
                    StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Collapsed"/>
            </Canvas>
            </Canvas>
          </Grid>

          <Grid>
            <!-- Claude row -->
            <StackPanel x:Name="ClaudeRow" Orientation="Horizontal" VerticalAlignment="Center">
              <Grid Width="28" Height="28" VerticalAlignment="Center">
                <Ellipse x:Name="Ring" Width="9" Height="9" StrokeThickness="1.2" Stroke="#D97857" Opacity="0" RenderTransformOrigin="0.5,0.5">
                  <Ellipse.RenderTransform><ScaleTransform ScaleX="1" ScaleY="1"/></Ellipse.RenderTransform>
                </Ellipse>
                <Ellipse x:Name="Dot" Width="9" Height="9" Fill="#D97857"/>
                <Ellipse x:Name="IconBg" Width="22" Height="22" Fill="#34C759" Visibility="Collapsed"/>
                <Path x:Name="Check" Data="M8.2,14.4 L12,18 L19.8,10.2" Stroke="#0B0B0D" StrokeThickness="2.4"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
                <TextBlock x:Name="Bang" Text="!" Foreground="#0B0B0D" FontWeight="Black" FontSize="14"
                           HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Grid>
              <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                <TextBlock x:Name="TitleText" Foreground="#FFFFFFFF" FontFamily="Segoe UI Variable Display, Segoe UI"
                           FontSize="13.5" FontWeight="SemiBold" MaxWidth="320" TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="SubText" Foreground="#99FFFFFF" FontFamily="Segoe UI Variable Text, Segoe UI"
                           FontSize="11.5" Margin="0,1,0,0" MaxWidth="320" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
              <TextBlock x:Name="TimerText" Foreground="#80FFFFFF" FontFamily="Cascadia Mono, Consolas"
                         FontSize="12" Margin="16,0,0,0" VerticalAlignment="Center"/>
              <Border x:Name="Badge" Background="#2EFFFFFF" CornerRadius="9" Padding="7,1,7,2" Margin="10,0,0,0"
                      VerticalAlignment="Center" Visibility="Collapsed">
                <TextBlock x:Name="BadgeText" Foreground="#E6FFFFFF" FontFamily="Segoe UI" FontSize="11" FontWeight="SemiBold"/>
              </Border>
            </StackPanel>

            <!-- Now playing row -->
            <StackPanel x:Name="MusicRow" Orientation="Horizontal" VerticalAlignment="Center" Visibility="Collapsed">
              <Border x:Name="Art" Width="30" Height="30" CornerRadius="8" Background="#2C2C30" VerticalAlignment="Center">
                <TextBlock x:Name="ArtNote" Text="&#xE8D6;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14"
                           Foreground="#80FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                <TextBlock x:Name="MTitle" Foreground="#FFFFFFFF" FontFamily="Segoe UI Variable Display, Segoe UI"
                           FontSize="13" FontWeight="SemiBold" MaxWidth="260" TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="MArtist" Foreground="#99FFFFFF" FontFamily="Segoe UI Variable Text, Segoe UI"
                           FontSize="11.5" Margin="0,1,0,0" MaxWidth="260" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
              <StackPanel x:Name="Eq" Orientation="Horizontal" Height="14" Margin="16,0,0,0" VerticalAlignment="Center">
                <Rectangle Width="3" Height="14" RadiusX="1.5" RadiusY="1.5" Margin="1,0" Fill="#FFFFFF" VerticalAlignment="Bottom" RenderTransformOrigin="0.5,1"><Rectangle.RenderTransform><ScaleTransform ScaleY="0.3"/></Rectangle.RenderTransform></Rectangle>
                <Rectangle Width="3" Height="14" RadiusX="1.5" RadiusY="1.5" Margin="1,0" Fill="#FFFFFF" VerticalAlignment="Bottom" RenderTransformOrigin="0.5,1"><Rectangle.RenderTransform><ScaleTransform ScaleY="0.3"/></Rectangle.RenderTransform></Rectangle>
                <Rectangle Width="3" Height="14" RadiusX="1.5" RadiusY="1.5" Margin="1,0" Fill="#FFFFFF" VerticalAlignment="Bottom" RenderTransformOrigin="0.5,1"><Rectangle.RenderTransform><ScaleTransform ScaleY="0.3"/></Rectangle.RenderTransform></Rectangle>
                <Rectangle Width="3" Height="14" RadiusX="1.5" RadiusY="1.5" Margin="1,0" Fill="#FFFFFF" VerticalAlignment="Bottom" RenderTransformOrigin="0.5,1"><Rectangle.RenderTransform><ScaleTransform ScaleY="0.3"/></Rectangle.RenderTransform></Rectangle>
              </StackPanel>
            </StackPanel>
          </Grid>
        </DockPanel>

        <!-- Claude sessions (hover) -->
        <StackPanel x:Name="Details" Visibility="Collapsed">
          <StackPanel Margin="4,10,0,2">
            <Border Height="1" Background="#1FFFFFFF" Margin="0,0,0,8"/>
            <StackPanel x:Name="Rows"/>
          </StackPanel>
        </StackPanel>

        <!-- Music controls (hover) -->
        <StackPanel x:Name="MusicDetails" Visibility="Collapsed">
        <StackPanel Margin="2,12,2,0" MinWidth="250">
          <Grid x:Name="ProgGrid" Height="4">
            <Border x:Name="ProgTrack" Background="#26FFFFFF" CornerRadius="2"/>
            <Border x:Name="ProgFill" Background="#E6FFFFFF" CornerRadius="2" HorizontalAlignment="Left" Width="0"/>
          </Grid>
          <Grid x:Name="TimeGrid" Margin="0,5,0,0">
            <TextBlock x:Name="PosText" Foreground="#80FFFFFF" FontFamily="Cascadia Mono, Consolas" FontSize="10.5"/>
            <TextBlock x:Name="DurText" Foreground="#80FFFFFF" FontFamily="Cascadia Mono, Consolas" FontSize="10.5" HorizontalAlignment="Right"/>
          </Grid>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,2,0,2">
            <Border x:Name="BtnPrev" Width="40" Height="32" CornerRadius="16" Background="#01FFFFFF">
              <TextBlock Text="&#xE892;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="15" Foreground="#E6FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border x:Name="BtnPlay" Width="44" Height="32" CornerRadius="16" Background="#01FFFFFF" Margin="6,0">
              <TextBlock x:Name="PlayGlyph" Text="&#xE769;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="19" Foreground="#FFFFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border x:Name="BtnNext" Width="40" Height="32" CornerRadius="16" Background="#01FFFFFF">
              <TextBlock Text="&#xE893;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="15" Foreground="#E6FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </StackPanel>
        </StackPanel>
        </StackPanel>
      </StackPanel>
      </Grid>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

foreach ($n in 'Pill','Ring','Dot','IconBg','Check','Bang','TitleText','SubText','TimerText','Badge','BadgeText',
               'Details','Rows','ClaudeRow','MusicRow','Art','ArtNote','MTitle','MArtist','Eq','MusicDetails',
               'ProgGrid','ProgTrack','ProgFill','TimeGrid','PosText','DurText','BtnPrev','BtnPlay','BtnNext','PlayGlyph',
               'Mascot','MLight','MShade','Eyes','EyeL','EyeR','HappyL','HappyR','Blob','CompImg','RootGrid','RootScale','Inner','Glass','Tint','SizeHost') {
    Set-Variable -Name ("ui" + $n) -Value $win.FindName($n) -Scope Script
}
$scale     = $uiPill.RenderTransform
$glow      = $uiPill.Effect
$ringSc    = $uiRing.RenderTransform
$mHop      = $uiMascot.RenderTransform.Children[0]
$mBob      = $uiMascot.RenderTransform.Children[1]
$eyeBlink  = $uiEyes.RenderTransform.Children[0]
$eyeSize   = $uiEyes.RenderTransform.Children[1]
$eyeLook   = $uiEyes.RenderTransform.Children[2]
$script:hover = $false

$OpacityProp = [System.Windows.UIElement]::OpacityProperty
$ScaleXProp  = [System.Windows.Media.ScaleTransform]::ScaleXProperty
$ScaleYProp  = [System.Windows.Media.ScaleTransform]::ScaleYProperty
$TransXProp  = [System.Windows.Media.TranslateTransform]::XProperty
$TransYProp  = [System.Windows.Media.TranslateTransform]::YProperty
$GlowOpProp  = [System.Windows.Media.Effects.DropShadowEffect]::OpacityProperty

function New-Color($hex) { [System.Windows.Media.ColorConverter]::ConvertFromString($hex) }
function New-Brush($hex) { New-Object System.Windows.Media.SolidColorBrush (New-Color $hex) }
function Dur($ms) { New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($ms)) }

function Animate($target, $prop, [double]$to, [int]$ms, $ease = $null, $from = $null) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.To = $to
    if ($null -ne $from) { $a.From = [double]$from }
    $a.Duration = Dur $ms
    if ($ease) { $a.EasingFunction = $ease }
    $target.BeginAnimation($prop, $a)
}
function Loop($target, $prop, [double]$from, [double]$to, [int]$ms, [bool]$reverse, $ease = $null) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation($from, $to, (Dur $ms))
    $a.AutoReverse = $reverse
    $a.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    if ($ease) { $a.EasingFunction = $ease }
    $target.BeginAnimation($prop, $a)
}
function Stop-Anim($target, $prop) { $target.BeginAnimation($prop, $null) }
function Keyframes($target, $prop, [double[]]$vals, [double[]]$times, [int]$ms) {
    $k = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $k.Duration = Dur $ms
    for ($i = 0; $i -lt $vals.Count; $i++) {
        $f = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame($vals[$i], [System.Windows.Media.Animation.KeyTime]::FromPercent($times[$i]))
        $e = New-Object System.Windows.Media.Animation.QuadraticEase
        $e.EasingMode = if ($i % 2 -eq 1) { 'EaseOut' } else { 'EaseIn' }
        $f.EasingFunction = $e
        [void]$k.KeyFrames.Add($f)
    }
    $target.BeginAnimation($prop, $k)
}
function Sine { $e = New-Object System.Windows.Media.Animation.SineEase; $e.EasingMode = 'EaseInOut'; $e }

$script:glowK = 1.0
function Clamp([double]$v, [double]$lo, [double]$hi) { [math]::Max($lo, [math]::Min($hi, $v)) }
# The window itself never changes size while animating (only the pill inside it does),
# so every animation frame is a plain redraw: no window resizing or re-centering.
function Place-Window {
    $k = Clamp $script:cfg.size 0.5 2.5
    $win.Width  = [math]::Round(760 * $k)
    $win.Height = [math]::Round(380 * $k + (Clamp $script:cfg.offsetY 0 2000))
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.Left = $wa.Left + [math]::Round(($wa.Width - $win.Width) / 2) + [double]$script:cfg.offsetX
    $win.Top  = $wa.Top
}
$script:mainHwnd = [IntPtr]::Zero
$script:blurOn = $false
$script:tintColor = $null; $script:solidColor = $null
$script:glassErr = $false
$blurTimer = New-Object System.Windows.Threading.DispatcherTimer
$blurTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$blurTimer.Add_Tick({
    try { Update-Glass; $script:glassErr = $false }
    catch { if (-not $script:glassErr) { $script:glassErr = $true; Write-Log ("blur: " + $_.Exception.Message) } }
})
function Apply-Glass {
    $v = $script:cfg.blur
    $want = ($v -eq $true) -or (@('blur', 'acrylic', 'on', 'true') -contains ([string]$v).ToLower())
    $script:blurOn = $false
    if ($script:mainHwnd -ne [IntPtr]::Zero) {
        if ($want) {
            if ([IslandNative]::ExcludeFromCapture($script:mainHwnd, $true)) { $script:blurOn = $true }
            else { Write-Log 'blur: Windows would not leave the island out of captures, so blur is off' }
        } else { [void][IslandNative]::ExcludeFromCapture($script:mainHwnd, $false) }
    }
    if (-not $script:blurOn) { $uiGlass.Fill = $null }
    $blurTimer.Interval = [TimeSpan]::FromMilliseconds((Clamp $script:cfg.blurRefreshMs 30 2000))
    Update-Glass
}
# Paints a blurred copy of whatever is behind the pill into the pill's own rounded shape.
function Update-Glass {
    if (-not $script:blurOn -or -not $script:shown -or $uiPill.ActualWidth -le 0) { return }
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    if (-not $src) { return }
    $m = $src.CompositionTarget.TransformToDevice
    $r = $uiPill.TransformToAncestor($win).TransformBounds((New-Object System.Windows.Rect(0, 0, $uiPill.ActualWidth, $uiPill.ActualHeight)))
    $x = [int][math]::Round(($win.Left + $r.X) * $m.M11); $y = [int][math]::Round(($win.Top + $r.Y) * $m.M22)
    $w = [int][math]::Round($r.Width * $m.M11);           $h = [int][math]::Round($r.Height * $m.M22)
    if ($w -lt 4 -or $h -lt 4) { return }
    $k = [int](Clamp $script:cfg.blurStrength 2 20)
    $sw = 0; $sh = 0
    $px = [IslandNative]::CaptureBlur($x, $y, $w, $h, $k, 2, [ref]$sw, [ref]$sh)
    $bs = [System.Windows.Media.Imaging.BitmapSource]::Create($sw, $sh, 96, 96, [System.Windows.Media.PixelFormats]::Bgr32, $null, $px, $sw * 4)
    $bs.Freeze()
    $brush = New-Object System.Windows.Media.ImageBrush $bs
    $brush.Stretch = 'Fill'
    $brush.Freeze()
    $uiGlass.Fill = $brush
}
function Apply-Appearance {
    try {
        $c = New-Color ([string]$script:cfg.backgroundColor)
        $a = [byte][math]::Round(255 * (Clamp $script:cfg.backgroundOpacity 0 1))
        $script:tintColor  = [System.Windows.Media.Color]::FromArgb($a, $c.R, $c.G, $c.B)
        $script:solidColor = [System.Windows.Media.Color]::FromArgb(255, $c.R, $c.G, $c.B)
        $uiTint.Fill = New-Object System.Windows.Media.SolidColorBrush $script:tintColor
        $bc = [System.Windows.Media.Color]::FromArgb([byte][math]::Round(255 * (Clamp $script:cfg.borderOpacity 0 1)), 255, 255, 255)
        $uiPill.BorderBrush = New-Object System.Windows.Media.SolidColorBrush $bc
        $cr = Clamp $script:cfg.cornerRadius 0 40
        $uiPill.CornerRadius = New-Object System.Windows.CornerRadius $cr
        foreach ($l in $uiGlass, $uiTint) { $l.RadiusX = [math]::Max(0, $cr - 1); $l.RadiusY = [math]::Max(0, $cr - 1) }
        $k = Clamp $script:cfg.size 0.5 2.5
        $uiRootScale.ScaleX = $k; $uiRootScale.ScaleY = $k
        $uiRootGrid.Margin = New-Object System.Windows.Thickness(36, (12 + (Clamp $script:cfg.offsetY 0 2000) / $k), 36, 36)
        $script:glowK = Clamp $script:cfg.glowStrength 0 2
        $uiPill.Effect = if ($script:glowK -gt 0) { $glow } else { $null }
        if ($script:cfg.textShadow) {
            $ts = New-Object System.Windows.Media.Effects.DropShadowEffect
            $ts.Color = [System.Windows.Media.Colors]::Black; $ts.ShadowDepth = 0; $ts.BlurRadius = 6; $ts.Opacity = 0.85
            $uiInner.Effect = $ts
        } else { $uiInner.Effect = $null }
        $script:look = ''
        Apply-Glass
        Place-Window
    } catch { Write-Log ("settings: " + $_.Exception.Message) }
}
[Microsoft.Win32.SystemEvents]::add_DisplaySettingsChanged({ try { $win.Dispatcher.BeginInvoke([action]{ Place-Window }) | Out-Null } catch { } })
$win.Add_SourceInitialized({
    $h  = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
    $script:mainHwnd = $h
    $ex = [IslandNative]::GetWindowLong($h, -20)
    [void][IslandNative]::SetWindowLong($h, -20, ($ex -bor 0x80 -bor 0x08000000))  # TOOLWINDOW | NOACTIVATE
})

# ---- mascot -------------------------------------------------------------
$script:mood = 'normal'
# ---- companions -----------------------------------------------------------
# Built-in: the blob (any palette color). Custom: companions\<Name>\ with images per state:
#   idle.png  working.png  needs.png  done.png  music.png   (only idle.png is required)
#   animate a state with numbered frames: idle_1.png, idle_2.png, ...
#   optional companion.json: { "size": 26, "fps": 6, "pixelated": true, "breathe": true }
$script:comp = $null
$script:compFrames = @()
$script:compFrame = 0
$script:compSig = ''
$compTimer = New-Object System.Windows.Threading.DispatcherTimer
$compTimer.Add_Tick({
    if ($script:compFrames.Count -gt 1) {
        $script:compFrame = ($script:compFrame + 1) % $script:compFrames.Count
        $uiCompImg.Source = $script:compFrames[$script:compFrame]
    }
})
$compScale = $uiCompImg.RenderTransform

function Get-Companions {
    if (-not (Test-Path $CompDir)) { return @() }
    @(Get-ChildItem -LiteralPath $CompDir -Directory | Where-Object {
        @(Get-ChildItem -LiteralPath $_.FullName -File | Where-Object { $_.Extension -match '^\.(png|jpe?g|bmp|gif)$' }).Count -gt 0
    } | Sort-Object Name | ForEach-Object { $_.Name })
}
function Get-CompSig($dir) {
    $f = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)
    "$($f.Count)|" + (($f | ForEach-Object { $_.LastWriteTimeUtc.Ticks } | Measure-Object -Maximum).Maximum)
}
function Load-Image($path) {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = 'OnLoad'                     # don't lock the file, so you can edit it
    $bi.CreateOptions = 'IgnoreImageCache'
    $bi.UriSource = New-Object System.Uri $path
    $bi.EndInit(); $bi.Freeze()
    $bi
}
function Load-Frames($files, $state) {
    $rx = '^' + [regex]::Escape($state) + '(?:[_\- ]?(\d+))?\.(png|jpe?g|bmp|gif)$'
    @($files | Where-Object { $_.Name -match $rx } |
        Sort-Object @{ Expression = { if ($_.Name -match '(\d+)\.\w+$') { [int]$Matches[1] } else { 0 } } } |
        ForEach-Object { try { Load-Image $_.FullName } catch { Write-Log ("companion image $($_.Name): " + $_.Exception.Message) } } |
        Where-Object { $_ })
}
function Load-Companion($name) {
    $dir = Join-Path $CompDir $name
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $meta = @{ size = 26; fps = 6; pixelated = $false; breathe = $true }
    $mf = Join-Path $dir 'companion.json'
    if (Test-Path -LiteralPath $mf) {
        try { ([IO.File]::ReadAllText($mf) | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $meta[$_.Name] = $_.Value } }
        catch { Write-Log ("$name\companion.json: " + $_.Exception.Message) }
    }
    $files = @(Get-ChildItem -LiteralPath $dir -File)
    $frames = @{}
    foreach ($st in 'idle', 'working', 'needs', 'done', 'music') { $frames[$st] = @(Load-Frames $files $st) }
    if ($frames.idle.Count -eq 0) {
        # No idle.png: use the first state that has images, or else every image in the folder
        $first = @('working', 'needs', 'done', 'music' | Where-Object { $frames[$_].Count } | Select-Object -First 1)
        if ($first.Count) { $frames.idle = $frames[$first[0]] }
        else { $frames.idle = @($files | Where-Object { $_.Extension -match '^\.(png|jpe?g|bmp|gif)$' } | Sort-Object Name |
                                ForEach-Object { try { Load-Image $_.FullName } catch { } } | Where-Object { $_ }) }
    }
    if ($frames.idle.Count -eq 0) { return $null }
    @{ name = $name; dir = $dir; meta = $meta; frames = $frames }
}
function Mood-State($mood) {
    switch ($mood) { 'focused' { 'working' } 'alert' { 'needs' } 'happy' { 'done' } 'groove' { 'music' } default { 'idle' } }
}
function Show-CompState($state) {
    $c = $script:comp
    if (-not $c) { return }
    $fr = $c.frames[$state]
    if (-not $fr -or $fr.Count -eq 0) { $fr = $c.frames.idle }
    $script:compFrames = @($fr); $script:compFrame = 0
    $uiCompImg.Source = $script:compFrames[0]
    $fps = [math]::Max(1, [math]::Min(30, [double]$c.meta.fps))
    $compTimer.Interval = [TimeSpan]::FromMilliseconds(1000 / $fps)
    if ($script:compFrames.Count -gt 1) { $compTimer.Start() } else { $compTimer.Stop() }
    # A still image breathes gently so it doesn't look frozen
    Stop-Anim $compScale $ScaleYProp; $compScale.ScaleY = 1
    if ($script:compFrames.Count -eq 1 -and $c.meta.breathe -and $state -ne 'music') {
        Loop $compScale $ScaleYProp 1.0 0.94 1300 $true (Sine)
    }
}
function Apply-Companion {
    $name = [string]$script:cfg.mascot
    $compTimer.Stop(); $script:comp = $null
    Stop-Anim $compScale $ScaleYProp; $compScale.ScaleY = 1
    if (-not $name -or $name -eq 'off') { $uiMascot.Visibility = 'Collapsed'; return }
    $uiMascot.Visibility = 'Visible'
    if (-not $script:mascotColors.Contains($name)) {
        $c = Load-Companion $name
        if ($c) {
            $script:comp = $c
            $script:compSig = Get-CompSig $c.dir
            $sz = [math]::Max(12, [math]::Min(40, [double]$c.meta.size))
            $uiCompImg.Width = $sz; $uiCompImg.Height = $sz
            $mode = if ($c.meta.pixelated) { 'NearestNeighbor' } else { 'HighQuality' }
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($uiCompImg, $mode)
            $uiBlob.Visibility = 'Collapsed'; $uiCompImg.Visibility = 'Visible'
            Show-CompState (Mood-State $script:mood)
            return
        }
        Write-Log "companion '$name' not found or has no images; using the blob"
        $name = 'pearl'
    }
    $uiCompImg.Visibility = 'Collapsed'; $uiBlob.Visibility = 'Visible'
    $uiMLight.Color = New-Color $script:mascotColors[$name][0]
    $uiMShade.Color = New-Color $script:mascotColors[$name][1]
}
function Mascot-Mood($mood) {
    if ($script:mood -eq $mood) { return }
    $script:mood = $mood
    if ($script:comp) { Show-CompState (Mood-State $mood) }
    Stop-Anim $mBob $TransYProp; $mBob.Y = 0
    Stop-Anim $eyeLook $TransXProp; $eyeLook.X = 0
    $happy = ($mood -eq 'happy' -or $mood -eq 'groove')
    $uiEyeL.Visibility = if ($happy) { 'Collapsed' } else { 'Visible' }
    $uiEyeR.Visibility = $uiEyeL.Visibility
    $uiHappyL.Visibility = if ($happy) { 'Visible' } else { 'Collapsed' }
    $uiHappyR.Visibility = $uiHappyL.Visibility
    $s = if ($mood -eq 'alert') { 1.25 } else { 1.0 }
    Animate $eyeSize $ScaleXProp $s 160; Animate $eyeSize $ScaleYProp $s 160
    switch ($mood) {
        'happy'  { Mascot-Hop 'celebrate' }
        'alert'  { Mascot-Hop 'perk' }
        'groove' { Loop $mBob $TransYProp 0 -1.6 280 $true (Sine) }
    }
}
function Mascot-Hop($kind) {
    if ($uiMascot.Visibility -ne 'Visible') { return }
    switch ($kind) {
        # Vorssaint's bounce: two quick hops, the second lower
        'celebrate' { Keyframes $mHop $TransYProp @(0, -7, 0, -4.9, 0, -1, 0, 0) @(0, .14, .32, .46, .63, .75, .88, 1) 950 }
        'perk'      { Keyframes $mHop $TransYProp @(0, -4, 0) @(0, .4, 1) 420 }
    }
}
function Mascot-Blink {
    if ($script:comp) { return }
    if ($script:mood -eq 'happy' -or $script:mood -eq 'groove') { return }
    Keyframes $eyeBlink $ScaleYProp @(1, 0.08, 0.08, 1) @(0, .35, .55, 1) 200
}
function Mascot-Glance {
    if ($script:comp) { return }
    $k = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $k.Duration = Dur 1700
    foreach ($p in @(@(0, 0), @(-1.6, 0.12), @(-1.6, 0.45), @(1.6, 0.57), @(1.6, 0.88), @(0, 1))) {
        [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame($p[0], [System.Windows.Media.Animation.KeyTime]::FromPercent($p[1]))))
    }
    $eyeLook.BeginAnimation($TransXProp, $k)
}
$blinkTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:rand = New-Object System.Random
$blinkTimer.Interval = [TimeSpan]::FromSeconds(3)
$blinkTimer.Add_Tick({
    if ($script:shown) {
        if ($script:mood -eq 'focused' -and $script:rand.NextDouble() -lt 0.45) { Mascot-Glance } else { Mascot-Blink }
    }
    $blinkTimer.Interval = [TimeSpan]::FromMilliseconds($script:rand.Next(2400, 6000))
})

# ---- look per state ------------------------------------------------------
$script:look  = ''
$script:shown = $false
$script:artColor = '#8E8E93'

function Stop-Eq { foreach ($r in $uiEq.Children) { Stop-Anim $r.RenderTransform $ScaleYProp; $r.RenderTransform.ScaleY = 0.3 } }
function Start-Eq {
    $i = 0
    foreach ($r in $uiEq.Children) {
        $ms = @(420, 560, 380, 500)[$i]; $lo = @(0.25, 0.35, 0.2, 0.3)[$i]
        Loop $r.RenderTransform $ScaleYProp $lo 1.0 $ms $true (Sine)
        $i++
    }
}

function Set-Look($mode) {
    $key = "$mode|$($script:artColor)"
    if ($script:look -eq $key) { return }
    $script:look = $key
    Stop-Anim $uiRing $OpacityProp; Stop-Anim $ringSc $ScaleXProp; Stop-Anim $ringSc $ScaleYProp; Stop-Anim $glow $GlowOpProp
    $uiRing.Opacity = 0; $glow.Opacity = 0.55 * $script:glowK
    $uiDot.Visibility = 'Collapsed'; $uiIconBg.Visibility = 'Collapsed'
    $uiCheck.Visibility = 'Collapsed'; $uiBang.Visibility = 'Collapsed'
    Stop-Eq

    switch ($mode) {
        'working' {
            $c = [string]$script:cfg.accent
            $uiDot.Fill = New-Brush $c; $uiRing.Stroke = New-Brush $c; $glow.Color = New-Color $c
            $uiDot.Visibility = 'Visible'
            # Vorssaint's pulse: the ring spreads from the dot as it fades, every 1.6 s
            Loop $uiRing $OpacityProp 0.6 0.0 1600 $false
            Loop $ringSc $ScaleXProp 1.0 2.4 1600 $false
            Loop $ringSc $ScaleYProp 1.0 2.4 1600 $false
            $glow.Opacity = 0.35 * $script:glowK
            Mascot-Mood 'focused'
        }
        'needs' {
            $c = [string]$script:cfg.needsColor
            $uiIconBg.Fill = New-Brush $c; $glow.Color = New-Color $c
            $uiIconBg.Visibility = 'Visible'; $uiBang.Visibility = 'Visible'
            Loop $glow $GlowOpProp (0.85 * $script:glowK) (0.3 * $script:glowK) 900 $true
            Mascot-Mood 'alert'
        }
        'done' {
            $c = [string]$script:cfg.doneColor
            $uiIconBg.Fill = New-Brush $c; $glow.Color = New-Color $c
            $uiIconBg.Visibility = 'Visible'; $uiCheck.Visibility = 'Visible'
            $glow.Opacity = 0.7 * $script:glowK
            Mascot-Mood 'happy'
        }
        'music' {
            $glow.Color = New-Color $script:artColor; $glow.Opacity = 0.5 * $script:glowK
            foreach ($r in $uiEq.Children) { $r.Fill = New-Brush $script:artColor }
            Start-Eq
            Mascot-Mood 'groove'
        }
        'musicpaused' {
            $glow.Color = New-Color $script:artColor; $glow.Opacity = 0.25 * $script:glowK
            foreach ($r in $uiEq.Children) { $r.Fill = New-Brush $script:artColor }
            Mascot-Mood 'normal'
        }
    }
}

function Get-Ms($key) { try { [int](Clamp $script:cfg[$key] 0 5000) } catch { [int]$script:cfgDefaults[$key] } }
# Hover panels grow open and shrink closed (expandMs) instead of popping.
# Two-step transitions with overlap. Step 1 runs over [0, d] of the total time and step 2
# over [1 - d, 1], where d = 1 / (2 - overlap): overlap 0 = one after the other,
# 1 = both at once, 0.8 = step 2 starts when step 1 is 20% done. Eased in-out sine.
function Get-Span { 1.0 / (2.0 - (Clamp $script:cfg.resizeOverlap 0 1)) }
function Span-Anim($target, $prop, [double]$from, [double]$to, [int]$ms, [double]$t0, [double]$t1, $done = $null, [int]$delay = 0) {
    $k = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $k.Duration = Dur $ms
    if ($delay -gt 0) { $k.BeginTime = [TimeSpan]::FromMilliseconds($delay) }
    $ease = New-Object System.Windows.Media.Animation.SineEase; $ease.EasingMode = 'EaseInOut'
    $KT = [System.Windows.Media.Animation.KeyTime]
    [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteDoubleKeyFrame($from, $KT::FromPercent(0))))
    if ($t0 -gt 0.0001) { [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame($from, $KT::FromPercent($t0)))) }
    $f = New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame($to, $KT::FromPercent([math]::Min(1, $t1))); $f.EasingFunction = $ease
    [void]$k.KeyFrames.Add($f)
    if ($t1 -lt 0.9999) { [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame($to, $KT::FromPercent(1)))) }
    if ($done) { $k.Add_Completed($done) }
    $target.BeginAnimation($prop, $k)
}
function Phase-Anim($target, $prop, [double]$from, [double]$to, [int]$ms, [int]$phase, $done = $null, [int]$delay = 0) {
    $d = Get-Span
    if ($phase -eq 1) { Span-Anim $target $prop $from $to $ms 0 $d $done $delay }
    else { Span-Anim $target $prop $from $to $ms (1 - $d) 1 $done $delay }
}
# With blur on, the pill can turn solid while it resizes (the glass can't follow a moving
# shape): fade to solid, resize, fade back. Returns how long the resize must wait.
function Get-SolidDelay([bool]$growing) {
    if (-not $script:blurOn -or -not $script:tintColor) { return 0 }
    $mode = ([string]$script:cfg.solidDuringResize).ToLower()
    $on = ($mode -eq 'both' -or $mode -eq 'true') -or ($mode -eq 'grow' -and $growing)
    if (-not $on) { return 0 }
    Get-Ms 'solidFadeMs'
}
function Solid-Pulse([int]$fade, [int]$ms) {
    $b = $uiTint.Fill
    if (-not ($b -is [System.Windows.Media.SolidColorBrush])) { return }
    if ($b.IsFrozen) { $b = $b.Clone(); $uiTint.Fill = $b }
    $total = [double]($fade * 2 + $ms)
    $KT = [System.Windows.Media.Animation.KeyTime]
    $k = New-Object System.Windows.Media.Animation.ColorAnimationUsingKeyFrames
    $k.Duration = Dur $total
    [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteColorKeyFrame($b.Color, $KT::FromPercent(0))))
    [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearColorKeyFrame($script:solidColor, $KT::FromPercent($fade / $total))))
    [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearColorKeyFrame($script:solidColor, $KT::FromPercent(($fade + $ms) / $total))))
    [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearColorKeyFrame($script:tintColor, $KT::FromPercent(1))))
    $b.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $k)
}
# Hover panels: shown/hidden here with a fade; the pill's own size animation (Sync-Size)
# does the widening and growing, so nothing ever pops.
function Grow-In($el) {
    if ($el.Visibility -eq 'Visible' -and [string]$el.Tag -ne 'closing') { return }
    $fo = if ($el.Visibility -eq 'Visible') { $el.Opacity } else { 0 }
    $el.Tag = 'open'
    $el.BeginAnimation($OpacityProp, $null); $el.Opacity = $fo
    $el.Visibility = 'Visible'
    $ms = Get-Ms 'expandMs'
    if ($ms -le 0) { $el.Opacity = 1; return }
    Phase-Anim $el $OpacityProp $fo 1 $ms 2 $null (Get-SolidDelay $true)   # fades in while the pill grows down
}
function Shrink-Out($el) {
    if ($el.Visibility -ne 'Visible' -or [string]$el.Tag -eq 'closing') { return }
    $el.Tag = 'closing'
    $ms = Get-Ms 'expandMs'
    if ($ms -le 0) { $el.Visibility = 'Collapsed'; $el.Tag = ''; return }
    $target = $el
    $done = { if ([string]$target.Tag -eq 'closing') { $target.Visibility = 'Collapsed'; $target.Tag = '' } }.GetNewClosure()
    $cur = $el.Opacity; $el.BeginAnimation($OpacityProp, $null); $el.Opacity = $cur
    Phase-Anim $el $OpacityProp $cur 0 $ms 1 $done (Get-SolidDelay $false)   # fades out while the pill shrinks up
}

# The pill glides to whatever size its content needs. Growing both ways: wider first, then
# taller. Shrinking both ways: shorter first, then narrower. In-out sine throughout.
$script:sizeTarget = ''
$script:sizeHover = $false
function Sync-Size {
    $hoverChanged = ($script:hover -ne $script:sizeHover)
    $script:sizeHover = $script:hover
    $ms = if ($hoverChanged) { Get-Ms 'expandMs' } else { Get-Ms 'resizeMs' }
    # Measure the natural size, counting panels that are on their way out as already gone
    $closing = @($uiDetails, $uiMusicDetails | Where-Object { [string]$_.Tag -eq 'closing' })
    foreach ($c in $closing) { $c.Visibility = 'Collapsed' }
    $uiInner.Width = [double]::NaN
    $uiInner.Measure((New-Object System.Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)))
    $d = $uiInner.DesiredSize
    foreach ($c in $closing) { $c.Visibility = 'Visible' }
    $w = [math]::Ceiling([math]::Max(208, $d.Width)); $h = [math]::Ceiling($d.Height)
    # (content stretches with the host, so text and companion move with the pill's edges)
    $key = "$w,$h"
    if ($key -eq $script:sizeTarget) { return }
    $script:sizeTarget = $key
    $WP = [System.Windows.FrameworkElement]::WidthProperty
    $HP = [System.Windows.FrameworkElement]::HeightProperty
    $cw = $uiSizeHost.ActualWidth; $ch = $uiSizeHost.ActualHeight
    if (-not $script:shown -or $ms -le 0 -or $cw -le 0 -or $ch -le 0) {
        $uiSizeHost.BeginAnimation($WP, $null); $uiSizeHost.BeginAnimation($HP, $null)
        $uiSizeHost.Width = $w; $uiSizeHost.Height = $h
        return
    }
    $growing = ($w * $h) -gt ($cw * $ch)
    $delay = Get-SolidDelay $growing
    if ($delay -gt 0) {
        Solid-Pulse $delay $ms
        # hold the current size while the pill turns solid (the resize starts after that)
        $uiSizeHost.BeginAnimation($WP, $null); $uiSizeHost.BeginAnimation($HP, $null)
        $uiSizeHost.Width = $cw; $uiSizeHost.Height = $ch
    }
    if ($w -gt $cw + 0.5 -and $h -gt $ch + 0.5) {
        Phase-Anim $uiSizeHost $WP $cw $w $ms 1 $null $delay; Phase-Anim $uiSizeHost $HP $ch $h $ms 2 $null $delay
    } elseif ($w -lt $cw - 0.5 -and $h -lt $ch - 0.5) {
        Phase-Anim $uiSizeHost $HP $ch $h $ms 1 $null $delay; Phase-Anim $uiSizeHost $WP $cw $w $ms 2 $null $delay
    } else {
        Span-Anim $uiSizeHost $WP $cw $w $ms 0 1 $null $delay
        Span-Anim $uiSizeHost $HP $ch $h $ms 0 1 $null $delay
    }
}
# Changed text cross-fades: the old text fades out, then the new one fades in.
$script:textPending = @{}         # TextBlock name -> text waiting to be shown
$script:textFlags = @{ swapped = $false }
function Set-Text($tb, [string]$text) {
    $name = $tb.Name
    $ms = Get-Ms 'textMs'
    if ($script:textPending.ContainsKey($name)) { $script:textPending[$name] = $text; return }   # mid-fade: just update
    if ($tb.Text -eq $text) { return }
    if (-not $script:shown -or $ms -le 0 -or -not $tb.Text) {
        $tb.BeginAnimation($OpacityProp, $null); $tb.Opacity = 1; $tb.Text = $text; return
    }
    $script:textPending[$name] = $text
    $half = [math]::Max(1, [int]($ms / 2))
    $pend = $script:textPending; $flags = $script:textFlags; $target = $tb
    $out = New-Object System.Windows.Media.Animation.DoubleAnimation(0, (New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($half))))
    $out.Add_Completed({
        $target.Text = [string]$pend[$target.Name]
        [void]$pend.Remove($target.Name)
        $flags.swapped = $true
        $in = New-Object System.Windows.Media.Animation.DoubleAnimation(1, (New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($half))))
        $target.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $in)
    }.GetNewClosure())
    $tb.BeginAnimation($OpacityProp, $out)
}
function Get-WantText($tb) { if ($script:textPending.ContainsKey($tb.Name)) { [string]$script:textPending[$tb.Name] } else { [string]$tb.Text } }

# Swapping between the Claude and music views cross-fades instead of cutting.
$script:viewKind = ''
function Set-View($kind) {
    if ($script:viewKind -eq $kind) { return }
    $was = $script:viewKind
    $script:viewKind = $kind
    if ($script:shown -and $was) { Animate $uiInner $OpacityProp 1 ([math]::Max(1, (Get-Ms 'switchMs') * 0.6)) $null 0 }
}
function Fade-In($el) { Grow-In $el }
function Show-Pill {
    if ($script:shown) { return }
    $script:shown = $true
    try { Update-Glass } catch { }
    $uiPill.IsHitTestVisible = $true
    $back = New-Object System.Windows.Media.Animation.BackEase
    $back.Amplitude = 0.4; $back.EasingMode = 'EaseOut'
    $ms = Get-Ms 'showMs'
    Animate $scale $ScaleXProp 1 $ms $back 0.55
    Animate $scale $ScaleYProp 1 $ms $back 0.55
    Animate $uiPill $OpacityProp 1 ([math]::Min(200, $ms)) $null 0
    $win.Topmost = $false; $win.Topmost = $true
}
function Hide-Pill {
    if (-not $script:shown) { return }
    $script:shown = $false
    $script:hover = $false
    $uiDetails.Visibility = 'Collapsed'; $uiMusicDetails.Visibility = 'Collapsed'; $uiDetails.Tag = ''; $uiMusicDetails.Tag = ''
    $uiPill.IsHitTestVisible = $false
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseIn'
    $ms = Get-Ms 'hideMs'
    Animate $scale $ScaleXProp 0.8 $ms $ease
    Animate $scale $ScaleYProp 0.8 $ms $ease
    Animate $uiPill $OpacityProp 0 $ms $ease
    $script:look = ''
    $script:mood = ''
    $script:sizeTarget = ''; $script:viewKind = ''
}
function Bump-Pill {
    $back = New-Object System.Windows.Media.Animation.BackEase
    $back.Amplitude = 0.6; $back.EasingMode = 'EaseOut'
    $ms = Get-Ms 'switchMs'
    if ($ms -le 0) { return }
    Animate $scale $ScaleXProp 1 $ms $back 0.93
    Animate $scale $ScaleYProp 1 $ms $back 0.93
}

# ---- sound ---------------------------------------------------------------
function Play-Chime($kind) {
    if (-not $script:cfg.sound) { return }
    $names = if ($kind -eq 'done') { 'Windows Notify Calendar.wav', 'Windows Notify System Generic.wav', 'chimes.wav' }
             else { 'Windows Notify Messaging.wav', 'Windows Notify Email.wav', 'notify.wav' }
    foreach ($n in $names) {
        $p = Join-Path $env:WINDIR "Media\$n"
        if (Test-Path $p) {
            try { $script:player = New-Object System.Media.SoundPlayer $p; $script:player.Play() } catch { }
            return
        }
    }
    [System.Media.SystemSounds]::Asterisk.Play()
}

# ---- helpers --------------------------------------------------------------
function Format-Elapsed([double]$ms) {
    $t = [TimeSpan]::FromMilliseconds([math]::Max(0, $ms))
    if ($t.TotalHours -ge 1) { return ('{0}:{1:mm\:ss}' -f [int][math]::Floor($t.TotalHours), $t) }
    return ('{0:m\:ss}' -f $t)
}
function Get-Now { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Format-Tokens($n) {
    $n = [double]$n
    if ($n -ge 1000000) { return [string]::Format($INV, '{0:0.0}M tokens', $n / 1000000) }
    if ($n -ge 1000)    { return [string]::Format($INV, '{0:0.0}k tokens', $n / 1000) }
    if ($n -gt 0)       { return [string]::Format($INV, '{0} tokens', $n) }
    return ''
}
function Format-Cost($c) {
    $c = [double]$c
    if ($c -ge 0.01) { return [string]::Format($INV, '~${0:0.00}', $c) }
    return ''
}
function Get-SessionExtras($s) {
    $parts = @()
    if ($s.model)  { $parts += [string]$s.model }
    if ($s.tokens) { $parts += (Format-Tokens $s.tokens) }
    if ($s.cost)   { $parts += (Format-Cost $s.cost) }
    @($parts | Where-Object { $_ })
}

# ---- hover panel: every session at a glance --------------------------------
function Add-Row($color, $proj, $text, $time) {
    $dp = New-Object System.Windows.Controls.DockPanel
    $dp.Margin = New-Object System.Windows.Thickness(0, 3, 0, 3)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $time; $t.Foreground = New-Brush '#80FFFFFF'; $t.FontSize = 11.5
    $t.FontFamily = New-Object System.Windows.Media.FontFamily 'Cascadia Mono, Consolas'
    $t.Margin = New-Object System.Windows.Thickness(16, 0, 0, 0); $t.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($t, 'Right'); [void]$dp.Children.Add($t)
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = 7; $e.Height = 7; $e.Fill = New-Brush $color; $e.VerticalAlignment = 'Center'
    $e.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    [System.Windows.Controls.DockPanel]::SetDock($e, 'Left'); [void]$dp.Children.Add($e)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI Variable Text, Segoe UI'
    $tb.FontSize = 12; $tb.MaxWidth = 340; $tb.TextTrimming = 'CharacterEllipsis'; $tb.VerticalAlignment = 'Center'
    $r1 = New-Object System.Windows.Documents.Run ([string]$proj)
    $r1.Foreground = New-Brush '#FFFFFFFF'; $r1.FontWeight = [System.Windows.FontWeights]::SemiBold
    $r2 = New-Object System.Windows.Documents.Run ("   " + [string]$text)
    $r2.Foreground = New-Brush '#8CFFFFFF'
    $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
    [void]$dp.Children.Add($tb)
    [void]$uiRows.Children.Add($dp)
}
function Render-Details($sessions, $now) {
    $uiRows.Children.Clear()
    $list = @($sessions | Where-Object {
        ($_.state -eq 'needs'   -and ($now - [int64]$_.updated)  -lt 3600000) -or
        ($_.state -eq 'working' -and ($now - [int64]$_.updated)  -lt 3600000) -or
        ($_.state -eq 'done'    -and ($now - [int64]$_.finished) -lt 1800000)
    } | Sort-Object @{ Expression = { switch ($_.state) { 'needs' { 0 } 'working' { 1 } default { 2 } } } }, @{ Expression = { [int64]$_.updated }; Descending = $true })
    $list = @($list | Select-Object -First 6)
    foreach ($s in $list) {
        switch ($s.state) {
            'needs'   { Add-Row ([string]$script:cfg.needsColor) $s.project 'Needs your input' (Format-Elapsed ($now - [int64]$s.updated)) }
            'working' { $l = if ($s.label) { [string]$s.label } else { 'Thinking' + $ELL }
                        Add-Row ([string]$script:cfg.accent) $s.project $l (Format-Elapsed ($now - [int64]$s.started)) }
            'done'    { $extra = @('Done') + (Get-SessionExtras $s)
                        Add-Row ([string]$script:cfg.doneColor) $s.project ($extra -join "  $DOT  ") (Format-Elapsed ([int64]$s.finished - [int64]$s.started)) }
        }
    }
    $m = $script:music
    if ($m -and $m.playing) {
        $who = if ($m.artist) { [string]$m.artist } else { [string]$m.appName }
        Add-Row $script:artColor ([string]$m.title) $who ''
    }
    if ($uiRows.Children.Count -gt 0) { Grow-In $uiDetails } else { Shrink-Out $uiDetails }
}

# ---- now playing (Windows media controls) ---------------------------------
$script:musicOK  = $false
$script:music    = $null
$script:musicKey = ''
$script:pausedAt = 0
function Await-WinRT($op, [Type]$type, [int]$timeoutMs = 1500) {
    $task = $script:asTask.MakeGenericMethod($type).Invoke($null, @($op))
    if (-not $task.Wait($timeoutMs)) { return $null }
    return $task.Result
}
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.InputStreamOptions, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.IInputStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
    $script:asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    $script:mgr = Await-WinRT ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]) 5000
    if ($script:mgr) { $script:musicOK = $true }
} catch { Write-Log ("media controls unavailable: " + $_.Exception.Message) }

function Get-AppName($aumid) {
    $a = [string]$aumid
    if ($a -match '!') { $a = $a.Split('!')[-1] }
    $a = $a -replace '\.exe$', ''
    switch -Regex ($a) {
        'spotify'        { return 'Spotify' }
        'msedge|edge'    { return 'Microsoft Edge' }
        'chrome'         { return 'Chrome' }
        'firefox|308046B0AF4A39CB' { return 'Firefox' }
        'zune|music'     { return 'Media Player' }
        default          { return $a }
    }
}
function Get-ArtColor($bmp) {
    try {
        $sc = New-Object System.Windows.Media.ScaleTransform((8.0 / $bmp.PixelWidth), (8.0 / $bmp.PixelHeight))
        $tb = New-Object System.Windows.Media.Imaging.TransformedBitmap($bmp, $sc)
        $fc = New-Object System.Windows.Media.Imaging.FormatConvertedBitmap($tb, [System.Windows.Media.PixelFormats]::Bgra32, $null, 0)
        $w = $fc.PixelWidth; $h = $fc.PixelHeight; $stride = $w * 4
        $px = New-Object byte[] ($stride * $h)
        $fc.CopyPixels($px, $stride, 0)
        $r = 0.0; $g = 0.0; $b = 0.0; $wt = 0.0
        for ($i = 0; $i -lt $px.Length; $i += 4) {
            $B = [double]$px[$i]; $G = [double]$px[$i + 1]; $R = [double]$px[$i + 2]
            $mx = [math]::Max($R, [math]::Max($G, $B)); $mn = [math]::Min($R, [math]::Min($G, $B))
            $s = ($mx - $mn) / 255.0 + 0.04          # favor colorful pixels
            $r += $R * $s; $g += $G * $s; $b += $B * $s; $wt += $s
        }
        $r /= $wt; $g /= $wt; $b /= $wt
        $mx = [math]::Max(1, [math]::Max($r, [math]::Max($g, $b)))
        $k = [math]::Max(1, 235 / $mx)                 # brighten dark covers so the glow shows
        return ('#{0:X2}{1:X2}{2:X2}' -f [int][math]::Min(255, $r * $k), [int][math]::Min(255, $g * $k), [int][math]::Min(255, $b * $k))
    } catch { return '#8E8E93' }
}
function Clear-Art {
    $uiArt.Background = New-Brush '#2C2C30'
    $uiArtNote.Visibility = 'Visible'
    $script:artColor = '#8E8E93'
}
function Read-ArtBytes($ref) {
    $ras = Await-WinRT ($ref.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType]) 3000
    if (-not $ras) { throw 'thumbnail stream timed out' }
    # Windows hands the cover over as a raw COM stream, so pass it straight to the readers
    # (calling methods on it from PowerShell fails). Read until the stream ends: some
    # players report a size of 0 even though the image is there.
    $ms = New-Object System.IO.MemoryStream
    $errs = @()
    try {
        $b = [IslandNative]::ReadWinRtStream($ras)
        if ($b -and $b.Length) { $ms.Write($b, 0, $b.Length) }
    } catch { $errs += "com: " + $_.Exception.Message }
    if ($ms.Length -eq 0) {
        try {
            $ns = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead([Windows.Storage.Streams.IInputStream]$ras)
            $ns.CopyTo($ms)
        } catch { $errs += "stream: " + $_.Exception.Message }
    }
    if ($ms.Length -eq 0) {
        try {
            $reader = [Windows.Storage.Streams.DataReader]::new([Windows.Storage.Streams.IInputStream]$ras)
            $reader.InputStreamOptions = [Windows.Storage.Streams.InputStreamOptions]::Partial
            for ($i = 0; $i -lt 256; $i++) {
                $n = Await-WinRT ($reader.LoadAsync(65536)) ([uint32]) 3000
                if (-not $n) { break }
                $buf = New-Object byte[] $n
                $reader.ReadBytes($buf)
                $ms.Write($buf, 0, $n)
            }
        } catch { $errs += "reader: " + $_.Exception.Message }
    }
    if ($ms.Length -eq 0) {
        try {
            $ns = [System.IO.WindowsRuntimeStreamExtensions]::AsStream([Windows.Storage.Streams.IRandomAccessStream]$ras)
            $ns.CopyTo($ms)
        } catch { $errs += "random: " + $_.Exception.Message }
    }
    if ($ms.Length -eq 0) { throw ('no image data. ' + ($errs -join ' | ')) }
    return , $ms.ToArray()
}
function Load-Art($ref) {
    if (-not $ref) { return $false }
    try {
        $bytes = Read-ArtBytes $ref
        if (-not $bytes -or $bytes.Length -lt 16) { throw 'no image data' }
        $ms = New-Object System.IO.MemoryStream(, $bytes)
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.StreamSource = $ms; $bi.DecodePixelWidth = 120; $bi.EndInit(); $bi.Freeze()
        $brush = New-Object System.Windows.Media.ImageBrush $bi
        $brush.Stretch = 'UniformToFill'
        $uiArt.Background = $brush
        $uiArtNote.Visibility = 'Collapsed'
        $script:artColor = Get-ArtColor $bi
        return $true
    } catch {
        if (-not $script:artLogged) { $script:artLogged = $true; Write-Log ("album art: " + $_.Exception.Message) }
        return $false
    }
}
$script:artLoaded = $false; $script:artRefreshes = 0; $script:artTries = 0; $script:artLogged = $false
function Update-Music {
    if (-not $script:musicOK -or -not $script:cfg.music) { $script:music = $null; return }
    try {
        $s = $script:mgr.GetCurrentSession()
        if (-not $s) { $script:music = $null; return }
        $playing = ($s.GetPlaybackInfo().PlaybackStatus.ToString() -eq 'Playing')
        $props = Await-WinRT ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
        if (-not $props -or -not $props.Title) { $script:music = $null; return }
        $key = "$($s.SourceAppUserModelId)|$($props.Title)|$($props.Artist)"
        if ($key -ne $script:musicKey) {
            $script:musicKey = $key; Clear-Art
            Animate $uiMusicRow $OpacityProp 1 (Get-Ms 'musicTrackMs') $null 0   # fade the new song in
            $script:artLoaded = $false; $script:artRefreshes = 3; $script:artTries = 0; $script:artLogged = $false
        }
        # Apps often send the title before the cover (or the previous song's cover first),
        # so keep trying until one loads, and refresh it a few times after a track change.
        if ($props.Thumbnail -and $script:artTries -lt 20 -and (-not $script:artLoaded -or $script:artRefreshes -gt 0)) {
            if ($script:artRefreshes -gt 0) { $script:artRefreshes-- }
            $script:artTries++
            if (Load-Art $props.Thumbnail) { $script:artLoaded = $true }
        }
        $now = Get-Now
        if ($playing) { $script:pausedAt = 0 } elseif (-not $script:pausedAt) { $script:pausedAt = $now }
        $tl = $s.GetTimelineProperties()
        $stamp = $tl.LastUpdatedTime.ToUnixTimeMilliseconds()
        if ($stamp -lt ($now - 86400000) -or $stamp -gt $now) { $stamp = $now }
        $script:music = @{
            title = [string]$props.Title; artist = [string]$props.Artist; appName = (Get-AppName $s.SourceAppUserModelId)
            playing = $playing; pos = $tl.Position.TotalMilliseconds; dur = ($tl.EndTime - $tl.StartTime).TotalMilliseconds
            stamp = $stamp; session = $s
        }
    } catch { $script:music = $null }
}
function Music-Command($which) {
    $m = $script:music
    if (-not $m) { return }
    try {
        switch ($which) {
            'toggle' { [void]$m.session.TryTogglePlayPauseAsync(); $m.playing = -not $m.playing; if (-not $m.playing) { $script:pausedAt = Get-Now } }
            'next'   { [void]$m.session.TrySkipNextAsync() }
            'prev'   { [void]$m.session.TrySkipPreviousAsync() }
        }
    } catch { }
    Update-Island
}
foreach ($pair in @(@($uiBtnPrev, 'prev'), @($uiBtnPlay, 'toggle'), @($uiBtnNext, 'next'))) {
    $btn = $pair[0]
    $btn.Tag = $pair[1]
    $btn.Add_MouseEnter({ $this.Background = New-Brush '#1FFFFFFF' })
    $btn.Add_MouseLeave({ $this.Background = New-Brush '#01FFFFFF' })
    $btn.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Music-Command ([string]$s.Tag) })
}

function Show-Music($m, $now) {
    $uiClaudeRow.Visibility = 'Collapsed'; $uiMusicRow.Visibility = 'Visible'; $uiDetails.Visibility = 'Collapsed'; $uiDetails.Tag = ''
    Set-Look $(if ($m.playing) { 'music' } else { 'musicpaused' })
    Set-Text $uiMTitle ([string]$m.title)
    Set-Text $uiMArtist ([string]$(if ($m.artist) { $m.artist } else { $m.appName }))
    $uiPlayGlyph.Text = if ($m.playing) { $GLYPH_PAUSE } else { $GLYPH_PLAY }
    if ($script:hover) {
        Fade-In $uiMusicDetails
        if ($m.dur -gt 1000) {
            $pos = [double]$m.pos
            if ($m.playing) { $pos += ($now - [int64]$m.stamp) }
            $pos = [math]::Min([double]$m.dur, [math]::Max(0, $pos))
            $uiProgGrid.Visibility = 'Visible'; $uiTimeGrid.Visibility = 'Visible'
            $uiProgFill.Width = [math]::Max(0, $uiProgTrack.ActualWidth * ($pos / $m.dur))
            $uiPosText.Text = Format-Elapsed $pos
            $uiDurText.Text = '-' + (Format-Elapsed ($m.dur - $pos))
        } else {
            $uiProgGrid.Visibility = 'Collapsed'; $uiTimeGrid.Visibility = 'Collapsed'
        }
    } else {
        Shrink-Out $uiMusicDetails
    }
    $script:dismissKey = ''
    Set-View 'music'
    Sync-Size
    $key = "music|$($script:musicKey)"
    if ($script:shown -and $key -ne $script:lastKey) { Bump-Pill }
    $script:lastKey = $key
    Show-Pill
}

# ---- main loop ------------------------------------------------------------
$script:dismissed   = @{}
$script:announced   = @{}
$script:lastKey     = ''
$script:dismissKey  = ''
$script:firstTick   = $true

function Update-Island {
    try {
        $now = Get-Now
        $sessions = New-Object System.Collections.ArrayList
        foreach ($f in [IO.Directory]::GetFiles($SessDir, '*.json')) {
            try { $s = [IO.File]::ReadAllText($f) | ConvertFrom-Json } catch { continue }
            if (-not $s) { continue }
            if (($now - [int64]$s.updated) -gt 21600000) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue; continue }
            [void]$sessions.Add($s)
        }

        $hour = 3600000
        $needs = @($sessions | Where-Object { $_.state -eq 'needs' -and ($now - [int64]$_.updated) -lt $hour -and -not $script:dismissed.ContainsKey("$($_.id):n:$($_.updated)") } |
                   Sort-Object { [int64]$_.updated } -Descending)
        $doneWindow = if ($script:hover -and $uiClaudeRow.Visibility -eq 'Visible') { 1800000 } else { [int]$script:cfg.doneSeconds * 1000 }
        $done  = @($sessions | Where-Object { $_.state -eq 'done' -and ($now - [int64]$_.finished) -lt $doneWindow -and -not $script:dismissed.ContainsKey("$($_.id):d:$($_.finished)") } |
                   Sort-Object { [int64]$_.finished } -Descending)
        $work  = @($sessions | Where-Object { $_.state -eq 'working' -and ($now - [int64]$_.updated) -lt $hour } |
                   Sort-Object { [int64]$_.updated } -Descending)

        # chimes, once per event (silent on the first pass so restarts don't replay)
        foreach ($s in $needs) { $k = "$($s.id):n:$($s.updated)"; if (-not $script:announced.ContainsKey($k)) { $script:announced[$k] = 1; if (-not $script:firstTick) { Play-Chime 'needs' } } }
        foreach ($s in $done)  {
            $k = "$($s.id):d:$($s.finished)"
            if (-not $script:announced.ContainsKey($k)) {
                $script:announced[$k] = 1
                $secs = ([int64]$s.finished - [int64]$s.started) / 1000
                if (-not $script:firstTick -and $secs -ge [double]$script:cfg.chimeAfterSeconds) { Play-Chime 'done' }
            }
        }
        $script:firstTick = $false

        $pick = $null; $mode = $null
        if     ($needs.Count -gt 0) { $pick = $needs[0]; $mode = 'needs' }
        elseif ($done.Count  -gt 0) { $pick = $done[0];  $mode = 'done' }
        elseif ($work.Count  -gt 0 -and $script:cfg.showWorking) { $pick = $work[0]; $mode = 'working' }

        if (-not $pick) {
            $m = $script:music
            if ($m -and ($m.playing -or $script:hover -or ($script:pausedAt -and ($now - $script:pausedAt) -lt ([int]$script:cfg.musicPausedSeconds * 1000)))) {
                Show-Music $m $now
            } else {
                Hide-Pill; $script:lastKey = ''
            }
            return
        }

        $uiClaudeRow.Visibility = 'Visible'; $uiMusicRow.Visibility = 'Collapsed'; $uiMusicDetails.Visibility = 'Collapsed'; $uiMusicDetails.Tag = ''
        Set-Look $mode
        $proj = [string]$pick.project
        switch ($mode) {
            'working' {
                $label = [string]$pick.label
                if (-not $label) { $label = 'Thinking' + $ELL }
                Set-Text $uiTitleText $label
                Set-Text $uiSubText $proj
                $uiTimerText.Text = Format-Elapsed ($now - [int64]$pick.started)
                $script:dismissKey = ''
            }
            'needs' {
                Set-Text $uiTitleText 'Needs your input'
                $msg = ([string]$pick.message) -replace '^Claude needs your permission to use\s*', 'Allow '
                Set-Text $uiSubText ([string]$(if ($msg) { "$proj  $DOT  $msg" } else { $proj }))
                $uiTimerText.Text = ''
                $script:dismissKey = "$($pick.id):n:$($pick.updated)"
            }
            'done' {
                Set-Text $uiTitleText 'Task complete'
                Set-Text $uiSubText ((@($proj) + (Get-SessionExtras $pick) | Where-Object { $_ }) -join "  $DOT  ")
                $uiTimerText.Text = Format-Elapsed ([int64]$pick.finished - [int64]$pick.started)
                $script:dismissKey = "$($pick.id):d:$($pick.finished)"
            }
        }
        $uiSubText.Visibility = if (Get-WantText $uiSubText) { 'Visible' } else { 'Collapsed' }

        $active = $needs.Count + $work.Count
        $others = if ($mode -eq 'done') { $active } else { $active - 1 }
        if ($others -gt 0) { $uiBadgeText.Text = "+$others"; $uiBadge.Visibility = 'Visible' } else { $uiBadge.Visibility = 'Collapsed' }

        if ($script:hover) { Render-Details $sessions $now } else { Shrink-Out $uiDetails }

        Set-View 'claude'
        Sync-Size
        $key = "$mode|$($pick.id)|$(Get-WantText $uiTitleText)"
        if ($script:shown -and $key -ne $script:lastKey) { Bump-Pill }
        $script:lastKey = $key
        Show-Pill
    } catch {
        Write-Log $_.Exception.Message
    }
}

# Hover to expand. Decided from where the cursor really is compared to the pill on screen
# (not WPF enter/leave events), with a short delay in and a padded, slower way out, so the
# pill growing or re-centering under the cursor can't make it flicker.
$script:hoverIn = 0; $script:hoverOut = 0
# Click-through: WS_EX_TRANSPARENT lets clicks fall to the window underneath. Holding Ctrl
# turns it off so the pill can be hovered and clicked; otherwise it fades while you're over it.
$script:passThru = $false; $script:peek = $false
function Set-PassThru([bool]$on) {
    if ($on -eq $script:passThru -or -not $script:mainHwnd) { return }
    $ex = [IslandNative]::GetWindowLong($script:mainHwnd, -20)
    $ex = if ($on) { $ex -bor 0x20 } else { $ex -band (-bnot 0x20) }
    [void][IslandNative]::SetWindowLong($script:mainHwnd, -20, $ex)
    $script:passThru = $on
}
function Set-Peek([bool]$on) {
    if ($on -eq $script:peek) { return }
    $script:peek = $on
    $to = if ($on) { Clamp $script:cfg.peekOpacity 0 1 } else { 1 }
    Animate $uiRootGrid $OpacityProp $to 150
}
function Test-CursorOnPill([double]$padDip) {
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    if (-not $src -or $uiPill.ActualWidth -le 0) { return $false }
    $m = $src.CompositionTarget.TransformToDevice
    $r = $uiPill.TransformToAncestor($win).TransformBounds((New-Object System.Windows.Rect(0, 0, $uiPill.ActualWidth, $uiPill.ActualHeight)))
    $p = [System.Windows.Forms.Cursor]::Position
    $x1 = ($win.Left + $r.Left - $padDip) * $m.M11; $x2 = ($win.Left + $r.Right + $padDip) * $m.M11
    $y1 = ($win.Top + $r.Top - $padDip) * $m.M22;   $y2 = ($win.Top + $r.Bottom + $padDip) * $m.M22
    return ($p.X -ge $x1 -and $p.X -le $x2 -and $p.Y -ge $y1 -and $p.Y -le $y2)
}
$hoverTimer = New-Object System.Windows.Threading.DispatcherTimer
$hoverTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$hoverTimer.Add_Tick({
    try {
        if ($script:textFlags.swapped) { $script:textFlags.swapped = $false; if ($script:shown) { Sync-Size } }
        $ctrl = ([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) -ne 0
        $through = [bool]$script:cfg.clickThrough -and -not $ctrl
        Set-PassThru $through
        if (-not $script:shown -or $uiPill.Opacity -lt 0.9) { Set-Peek $false; $script:hoverIn = 0; $script:hoverOut = 0; return }
        if ($through) {
            Set-Peek (Test-CursorOnPill 0)
            $script:hoverIn = 0
            if ($script:hover) { $script:hover = $false; $script:hoverOut = 0; Update-Island }
            return
        }
        Set-Peek $false
        if ($script:hover) {
            if (Test-CursorOnPill 10) { $script:hoverOut = 0 }
            else {
                $script:hoverOut += 50
                if ($script:hoverOut -ge 250) { $script:hover = $false; $script:hoverOut = 0; Update-Island }
            }
        } else {
            if (Test-CursorOnPill 0) {
                $script:hoverIn += 50
                if ($script:hoverIn -ge 100) { $script:hover = $true; $script:hoverIn = 0; Update-Island }
            } else { $script:hoverIn = 0 }
        }
    } catch { }
})

# Click the pill to dismiss "Task complete" / "Needs your input"; click the mascot to say hi
$uiPill.Add_MouseLeftButtonUp({
    if ($script:dismissKey) { $script:dismissed[$script:dismissKey] = 1; Update-Island }
})
$uiMascot.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; Mascot-Hop 'celebrate' })

# ---- test run -------------------------------------------------------------
function Write-TestSession($state, $label, [int64]$started, [int64]$finished, $message = '') {
    $o = [ordered]@{ id = 'island-test'; state = $state; label = $label; project = 'MyUnityGame'; message = $message
                     started = $started; updated = (Get-Now); finished = $finished }
    if ($state -eq 'done') { $o.model = 'Opus 5.5'; $o.tokens = 48200; $o.cost = 0.87 }
    [IO.File]::WriteAllText((Join-Path $SessDir 'island-test.json'), ($o | ConvertTo-Json -Compress))
}
function Start-Test {
    $n = Get-Now
    $script:testStart = $n - 72000
    Write-TestSession 'working' 'Editing PlayerController.cs' $script:testStart 0
    $script:testStep = 0
    if ($script:testTimer) { $script:testTimer.Stop() }
    $script:testTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:testTimer.Interval = [TimeSpan]::FromSeconds(3.5)
    $script:testTimer.Add_Tick({
        $script:testStep++
        switch ($script:testStep) {
            1 { Write-TestSession 'needs' 'Running command' $script:testStart 0 'Claude needs your permission to use Bash' }
            2 { Write-TestSession 'working' 'Running command' $script:testStart 0 }
            3 { Write-TestSession 'done' '' $script:testStart (Get-Now); $script:testTimer.Stop() }
        }
        Update-Island
    })
    $script:testTimer.Start()
    Update-Island
}

# ---- tray icon ------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 11, 11, 13))), 1, 7, 30, 18)
$g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 217, 120, 87))), 6, 12, 8, 8)
$g.Dispose()

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$tray.Text = 'Claude Island'
$tray.Visible = $true

$script:toggles = @()
function New-Toggle($text, $key, $after = $null) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem $text
    $mi.CheckOnClick = $true; $mi.Checked = [bool]$script:cfg[$key]; $mi.Tag = $key
    $script:toggles += $mi
    $mi.Add_Click({ $script:cfg[[string]$this.Tag] = $this.Checked; Save-Config; Update-Music; Update-Island })
    $mi
}
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miTest = New-Object System.Windows.Forms.ToolStripMenuItem 'Play a test run'
$miTest.Add_Click({ Start-Test })
[void]$menu.Items.Add($miTest)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add((New-Toggle 'Sound' 'sound'))
[void]$menu.Items.Add((New-Toggle 'Show while Claude works' 'showWorking'))
[void]$menu.Items.Add((New-Toggle 'Now playing' 'music'))
[void]$menu.Items.Add((New-Toggle 'Click through (hold Ctrl to use)' 'clickThrough'))

function Set-Companion($name) {
    $script:cfg.mascot = [string]$name; Save-Config; Apply-Companion; Mascot-Hop 'perk'
}
$miMascot = New-Object System.Windows.Forms.ToolStripMenuItem 'Companion'
$miMascot.DropDownItems.Add('(loading)') | Out-Null
$miMascot.Add_DropDownOpening({
    # Rebuilt every time, so new companion folders show up without restarting
    $miMascot.DropDownItems.Clear()
    $cur = [string]$script:cfg.mascot
    $off = New-Object System.Windows.Forms.ToolStripMenuItem 'Off'
    $off.Checked = ($cur -eq 'off'); $off.Add_Click({ Set-Companion 'off' })
    [void]$miMascot.DropDownItems.Add($off)
    $blob = New-Object System.Windows.Forms.ToolStripMenuItem 'Blob'
    $blob.Checked = $script:mascotColors.Contains($cur)
    foreach ($n in $script:mascotColors.Keys) {
        $it = New-Object System.Windows.Forms.ToolStripMenuItem ((Get-Culture).TextInfo.ToTitleCase($n))
        $it.Tag = $n; $it.Checked = ($cur -eq $n)
        $it.Add_Click({ Set-Companion ([string]$this.Tag) })
        [void]$blob.DropDownItems.Add($it)
    }
    [void]$miMascot.DropDownItems.Add($blob)
    $list = Get-Companions
    if ($list.Count) { [void]$miMascot.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }
    foreach ($n in $list) {
        $it = New-Object System.Windows.Forms.ToolStripMenuItem $n
        $it.Tag = $n; $it.Checked = ($cur -eq $n)
        $it.Add_Click({ Set-Companion ([string]$this.Tag) })
        [void]$miMascot.DropDownItems.Add($it)
    }
    [void]$miMascot.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $open = New-Object System.Windows.Forms.ToolStripMenuItem 'Open companions folder'
    $open.Add_Click({ Start-Process explorer.exe "`"$CompDir`"" })
    [void]$miMascot.DropDownItems.Add($open)
})
[void]$menu.Items.Add($miMascot)

# Start with Windows: a shortcut in the user's Startup folder
$script:startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Island.lnk'
function Set-Autostart([bool]$on) {
    try {
        if ($on) {
            $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $self  = $script:SelfPath
            $ws  = New-Object -ComObject WScript.Shell
            $lnk = $ws.CreateShortcut($script:startupLnk)
            $lnk.TargetPath  = $psExe
            $lnk.Arguments   = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$self`""
            $lnk.WindowStyle = 7
            $lnk.Description = 'Claude Island overlay'
            $lnk.Save()
        } else {
            Remove-Item -LiteralPath $script:startupLnk -Force -ErrorAction SilentlyContinue
        }
    } catch { Write-Log ("autostart: " + $_.Exception.Message) }
}
$miStartup = New-Object System.Windows.Forms.ToolStripMenuItem 'Start with Windows'
$miStartup.CheckOnClick = $true
$miStartup.Checked = (Test-Path -LiteralPath $script:startupLnk)
$miStartup.Add_Click({ Set-Autostart $miStartup.Checked; $miStartup.Checked = (Test-Path -LiteralPath $script:startupLnk) })
[void]$menu.Items.Add($miStartup)

$miClear = New-Object System.Windows.Forms.ToolStripMenuItem 'Clear stuck sessions'
$miClear.Add_Click({ Get-ChildItem $SessDir -File | Remove-Item -Force -ErrorAction SilentlyContinue; Update-Island })
[void]$menu.Items.Add($miClear)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miFolder = New-Object System.Windows.Forms.ToolStripMenuItem 'Open island folder'
$miFolder.Add_Click({ Start-Process explorer.exe "`"$Root`"" })
[void]$menu.Items.Add($miFolder)
$miRestart = New-Object System.Windows.Forms.ToolStripMenuItem 'Restart'
$miRestart.Add_Click({ Restart-Island })
[void]$menu.Items.Add($miRestart)
$miQuit = New-Object System.Windows.Forms.ToolStripMenuItem 'Quit'
$miQuit.Add_Click({
    $timer.Stop(); $musicTimer.Stop(); $blinkTimer.Stop(); $watchTimer.Stop(); $compTimer.Stop(); $blurTimer.Stop(); $hoverTimer.Stop()
    $tray.Visible = $false; $tray.Dispose()
    $app.Shutdown()
})
[void]$menu.Items.Add($miQuit)
$tray.ContextMenuStrip = $menu
$tray.Add_DoubleClick({ Start-Test })

# ---- run ------------------------------------------------------------------
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnExplicitShutdown'

Apply-Appearance
Apply-Companion

# ---- live updates: settings.json edits, companion image edits, script updates ----
function Apply-Settings {
    Apply-Appearance
    foreach ($mi in $script:toggles) { $mi.Checked = [bool]$script:cfg[[string]$mi.Tag] }
    $script:look = ''
    Apply-Companion
    Update-Music
    Update-Island
}
function Restart-Island {
    try {
        foreach ($t in $timer, $musicTimer, $blinkTimer, $watchTimer, $compTimer, $blurTimer, $hoverTimer) { if ($t) { $t.Stop() } }
        $tray.Visible = $false; $tray.Dispose()
        try { $script:mutex.ReleaseMutex(); $script:mutex.Dispose() } catch { }
        $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:SelfPath`"" -WindowStyle Hidden
    } catch { Write-Log ("restart: " + $_.Exception.Message) }
    $app.Shutdown()
}
$script:selfStamp = (Get-Item -LiteralPath $script:SelfPath).LastWriteTimeUtc
$script:selfSeen  = $script:selfStamp
$script:badUpdate = $null
$watchTimer = New-Object System.Windows.Threading.DispatcherTimer
$watchTimer.Interval = [TimeSpan]::FromSeconds(1.5)
$watchTimer.Add_Tick({
    try {
        # settings.json edited by hand
        if (Test-Path $CfgPath) {
            $t = (Get-Item -LiteralPath $CfgPath).LastWriteTimeUtc
            if ($t -ne $script:cfgStamp) { if (Read-Config) { Apply-Settings } else { $script:cfgStamp = $t } }
        }
        # images in the current companion's folder changed
        if ($script:comp) {
            $sig = Get-CompSig $script:comp.dir
            if ($sig -ne $script:compSig) { Apply-Companion }
        }
        # this script was updated: wait until it stops changing, check it parses, then restart
        $t = (Get-Item -LiteralPath $script:SelfPath).LastWriteTimeUtc
        if ($t -ne $script:selfStamp) {
            if ($t -ne $script:selfSeen) { $script:selfSeen = $t; return }   # still being written
            if ($script:badUpdate -eq $t) { return }
            $tok = $null; $err = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($script:SelfPath, [ref]$tok, [ref]$err)
            if ($err.Count) { $script:badUpdate = $t; Write-Log ("update has errors, not restarting: " + $err[0].Message); return }
            Write-Log 'update found, restarting'
            Restart-Island
        }
    } catch { Write-Log ("watch: " + $_.Exception.Message) }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(300)
$timer.Add_Tick({ Update-Island })

$musicTimer = New-Object System.Windows.Threading.DispatcherTimer
$musicTimer.Interval = [TimeSpan]::FromSeconds(1)
$musicTimer.Add_Tick({ Update-Music })

$win.Show()
Place-Window
$blurTimer.Start()
$hoverTimer.Start()
Apply-Glass
Update-Music
Update-Island
$timer.Start()
$musicTimer.Start()
$blinkTimer.Start()
$watchTimer.Start()
Write-Log "started from $Root (animations at $($script:fps) fps)"
[void]$app.Run()
