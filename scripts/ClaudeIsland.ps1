# Copyright (C) 2026 the windows-notch authors. Licensed GPL-3.0-or-later, see LICENSE.
# Claude Island - a Dynamic-Island-style pill for Windows.
# Lives in <island folder>\scripts. Settings: <island folder>\settings.json (applied live).
# Companions: <island folder>\custom images\<name>\ (see docs\companions.md).
# Replacing this file (or the hook) is all an update needs: the island restarts itself.
#  * Claude Code status: working / needs your input / task complete (model, tokens, API value)
#  * Now playing: album art, title, artist, equalizer; hover for progress and controls
#  * A little mascot that blinks, glances around and hops when a task finishes
# Inspired by Vorssaint (https://github.com/vorssaint/vorssaint-utils): ideas, price table,
# mascot palette and pulse timing are adapted from it. GPL-3.0-or-later, see LICENSE.
#
# Draws its own window instead of using Windows notifications, so Focus / Do Not
# Disturb doesn't hide it and nothing lands in the notification center.

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$script:SelfPath = $PSCommandPath
$Root     = Split-Path $PSScriptRoot -Parent
$StateDir = Join-Path $Root 'state'
$SessDir  = Join-Path $StateDir 'sessions'
$CompDir  = Join-Path $Root 'custom images'
# Companions used to live in companions\: move any left there over (an existing one wins)
$oldComp  = Join-Path $Root 'companions'
if (Test-Path -LiteralPath $oldComp) {
    New-Item -ItemType Directory -Force -Path $CompDir | Out-Null
    foreach ($d in @(Get-ChildItem -LiteralPath $oldComp -Directory)) {
        if (-not (Test-Path -LiteralPath (Join-Path $CompDir $d.Name))) { try { Move-Item -LiteralPath $d.FullName $CompDir } catch { } }
    }
    if (-not @(Get-ChildItem -LiteralPath $oldComp -Recurse -File).Count) { Remove-Item -LiteralPath $oldComp -Recurse -Force -ErrorAction SilentlyContinue }
}
$CfgPath  = Join-Path $Root 'settings.json'
$oldCfg   = Join-Path $Root 'config.json'
if ((Test-Path $oldCfg) -and -not (Test-Path $CfgPath)) { try { Move-Item $oldCfg $CfgPath } catch { } }
$LogPath  = Join-Path $StateDir 'island.log'
$script:Version = try { ([IO.File]::ReadAllText((Join-Path $Root 'VERSION'))).Trim() } catch { '0.0.0' }
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
    fullscreenNotch    = $true      # while a fullscreen app is in front, swap the pill for a slim notch at the top edge
    expandedWidth      = 400        # size of the expanded island, so its buttons are always in the same place
    expandedHeight     = 0          # 0 = just tall enough for the tallest panel; set a number to make it taller
    expandedOpacity    = 0.92       # background darkness while expanded (0 to 1), so text stays readable
    fullscreenClock    = $true      # in fullscreen, the notch shows the time when nothing else is going on
    popups             = $true      # short notices in the island (and the fullscreen notch); each kind below can be turned off
    popupSeconds       = 3          # how long a notice stays
    popupDevices       = $true      # a device (headphones, mouse, keyboard, USB drive, camera) connected or removed
    popupVolume        = $true      # volume or brightness changed: a slim bar
    popupAudioOutput   = $true      # sound output switched (speakers, headphones, ...)
    popupLocks         = $true      # Caps Lock / Num Lock
    popupBattery       = $true      # charger plugged in or out, battery low (laptops)
    popupNetwork       = $true      # Wi-Fi / Ethernet connected or lost, VPN on or off
    popupScreenshots   = $true      # a screenshot was saved: a small preview, click it to open
    popupDownloads     = $true      # a download finished (Downloads folder): click to show it
    popupClipboard     = $true      # something was copied: a short preview (password managers' copies are skipped)
    popupFocus         = $true      # Do Not Disturb turned on or off
    popupGitHub        = $true      # your open pull requests: checks passed / failed, approved (needs the gh CLI, signed in)
    calendarIcsUrl     = ''         # your calendar's private iCal (.ics) link, for "meeting in 5 minutes"
    calendarMinutes    = 5          # how early to remind you of a meeting
    timerMinutes       = 25         # Pomodoro: focus length (tray menu > Timer)
    breakMinutes       = 5          # Pomodoro: break length
    sleepAfterMinutes  = 5          # the companion falls asleep after this long without mouse or keyboard (0 = never)
    weatherCity        = ''         # a city name (e.g. Istanbul) to show the weather in the stats; empty = off
    updateCheck        = $true      # once a day, look for a newer release on GitHub (you're asked before anything installs)
    updateRepo         = 'kilicaslanalper/windows-notch'   # where releases come from
    stats              = $true      # when nothing else is on, show system stats in the pill
    statsItems         = 'cpu,gpu,ram,net'   # any of cpu, gpu, ram, net, in the order you want them
    mascot             = 'Charlie'  # off, a blob color (pearl, lemon, peach, rose, lilac, sky, mint) or a folder name in custom images
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
// Core Audio: the default speakers' master volume and mute
[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IIslandEndpointVolume {
    int RegisterControlChangeNotify(IntPtr p); int UnregisterControlChangeNotify(IntPtr p);
    int GetChannelCount(out uint c);
    int SetMasterVolumeLevel(float l, ref Guid ctx); int SetMasterVolumeLevelScalar(float l, ref Guid ctx);
    int GetMasterVolumeLevel(out float l); int GetMasterVolumeLevelScalar(out float l);
    int SetChannelVolumeLevel(uint ch, float l, ref Guid ctx); int SetChannelVolumeLevelScalar(uint ch, float l, ref Guid ctx);
    int GetChannelVolumeLevel(uint ch, out float l); int GetChannelVolumeLevelScalar(uint ch, out float l);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, ref Guid ctx); int GetMute([MarshalAs(UnmanagedType.Bool)] out bool m);
}
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IIslandMMDevice {
    int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    int OpenPropertyStore(int access, out IIslandPropertyStore ps);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    int GetState(out int state);
}
[StructLayout(LayoutKind.Sequential)] struct IslandPKey { public Guid fmtid; public int pid; }
[StructLayout(LayoutKind.Explicit)] struct IslandPropVar { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr p2; }
[ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IIslandPropertyStore {
    int GetCount(out int c); int GetAt(int i, out IslandPKey k);
    int GetValue(ref IslandPKey k, out IslandPropVar v); int SetValue(ref IslandPKey k, ref IslandPropVar v); int Commit();
}
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IIslandMMDeviceEnumerator { int EnumAudioEndpoints(int flow, int mask, out IntPtr devs); int GetDefaultAudioEndpoint(int flow, int role, out IIslandMMDevice d); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class IslandMMDeviceEnumerator { }
public static class IslandAudio {
    // The enumerator and the speakers' volume control are kept, and only re-made when the
    // default output changes, so polling the volume a few times a second stays cheap.
    static IIslandMMDeviceEnumerator en; static IIslandEndpointVolume ep; static string epId;
    static IIslandMMDevice Default() {
        if (en == null) en = (IIslandMMDeviceEnumerator)new IslandMMDeviceEnumerator();
        IIslandMMDevice d; Marshal.ThrowExceptionForHR(en.GetDefaultAudioEndpoint(0, 1, out d));
        return d;
    }
    static IIslandEndpointVolume Endpoint() {
        var d = Default(); string id; d.GetId(out id);
        if (ep == null || id != epId) {
            Guid iid = typeof(IIslandEndpointVolume).GUID; object o;
            Marshal.ThrowExceptionForHR(d.Activate(ref iid, 23, IntPtr.Zero, out o));
            ep = (IIslandEndpointVolume)o; epId = id;
        }
        return ep;
    }
    public static string DefaultId() { string id; Default().GetId(out id); return id; }
    public static string DefaultName() {
        IIslandPropertyStore ps;
        if (Default().OpenPropertyStore(0, out ps) != 0) return null;
        var k = new IslandPKey { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };   // friendly name
        IslandPropVar v;
        if (ps.GetValue(ref k, out v) != 0 || v.vt != 31) return null;
        return Marshal.PtrToStringUni(v.p);
    }
    public static float GetVolume() { float v; Endpoint().GetMasterVolumeLevelScalar(out v); return v; }
    public static void SetVolume(float v) { Guid g = Guid.Empty; Endpoint().SetMasterVolumeLevelScalar(Math.Max(0f, Math.Min(1f, v)), ref g); }
    public static bool GetMute() { bool m; Endpoint().GetMute(out m); return m; }
    public static void SetMute(bool m) { Guid g = Guid.Empty; Endpoint().SetMute(m, ref g); }
}
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

    // System stats: total CPU time counters and memory load
    [DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [StructLayout(LayoutKind.Sequential)] public class MEMSTAT {
        public uint dwLength = 64; public uint dwMemoryLoad; public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile,
        ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual; }
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MEMSTAT m);
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO li);
    public static uint IdleMs() { var li = new LASTINPUTINFO(); li.cbSize = 8; return GetLastInputInfo(ref li) ? (uint)Environment.TickCount - li.dwTime : 0; }
    public static int MemoryLoad() { var m = new MEMSTAT(); return GlobalMemoryStatusEx(m) ? (int)m.dwMemoryLoad : -1; }
    public static double[] MemoryGB() {   // used, total
        var m = new MEMSTAT(); if (!GlobalMemoryStatusEx(m)) return null;
        return new[] { (m.ullTotalPhys - m.ullAvailPhys) / 1073741824.0, m.ullTotalPhys / 1073741824.0 };
    }

    // Fullscreen: the foreground window covers its whole monitor (and isn't the desktop or just
    // a maximized window with a title bar). Returns that monitor's rect in pixels, or null.
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
    public static int[] FullscreenRect(IntPtr self1, IntPtr self2) {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero || h == self1 || h == self2 || !IsWindowVisible(h)) return null;
        var cls = new System.Text.StringBuilder(64); GetClassName(h, cls, 64);
        switch (cls.ToString()) { case "Progman": case "WorkerW": case "Shell_TrayWnd": case "Shell_SecondaryTrayWnd": return null; }
        RECT r; if (!GetWindowRect(h, out r)) return null;
        var mi = new MONITORINFO(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref mi)) return null;
        var m = mi.rcMonitor;
        if (!(r.L <= m.L && r.T <= m.T && r.R >= m.R && r.B >= m.B)) return null;
        // Covering the monitor exactly is fullscreen (browsers' F11 and videos keep their title-bar
        // style, so that alone can't decide). Larger than the monitor is a maximized window's
        // invisible frame: only fullscreen if it has no title bar, or Windows says an app is fullscreen.
        bool exact = r.L == m.L && r.T == m.T && r.R == m.R && r.B == m.B;
        bool caption = (GetWindowLong(h, -16) & 0x00C00000) == 0x00C00000;
        int quns = 0; try { SHQueryUserNotificationState(out quns); } catch { }
        bool busy = quns == 2 || quns == 3 || quns == 4;   // busy / D3D fullscreen / presentation
        if (exact || !caption || !IsZoomed(h) || busy) return new[] { m.L, m.T, m.R, m.B };
        return null;
    }
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
    // Keep a window above everything, fullscreen apps included, without activating it
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public static void ForceTopmost(IntPtr h) { SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 | 0x0200); }

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
    <Grid x:Name="PeekHost">
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
        <DockPanel LastChildFill="True" MinHeight="34">

          <!-- Mascot (right end) -->
          <Grid x:Name="Mascot" DockPanel.Dock="Right" Margin="12,0,2,0" VerticalAlignment="Center" Background="Transparent">
            <Grid.RenderTransform>
              <TransformGroup><TranslateTransform/><TranslateTransform/></TransformGroup>
            </Grid.RenderTransform>
            <TextBlock x:Name="Zzz" Text="z" FontFamily="Segoe UI" FontSize="10" FontWeight="Bold" Foreground="#CCFFFFFF"
                       HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-8,-6,0" Opacity="0" IsHitTestVisible="False">
              <TextBlock.RenderTransform><TranslateTransform/></TextBlock.RenderTransform>
            </TextBlock>
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

            <!-- System stats row (filled in by Render-Stats) -->
            <StackPanel x:Name="StatsRow" Orientation="Horizontal" VerticalAlignment="Center" Margin="6,5,0,5" Visibility="Collapsed"/>

            <!-- Popup row: short notices (device, volume, screenshot, ...) -->
            <StackPanel x:Name="PopupRow" Orientation="Horizontal" VerticalAlignment="Center" Visibility="Collapsed">
              <Grid Width="28" Height="28" VerticalAlignment="Center">
                <Ellipse x:Name="PopDot" Width="26" Height="26" Fill="#33FFFFFF"/>
                <Path x:Name="PopRing" Width="28" Height="28" StrokeThickness="2.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                      Visibility="Collapsed"/>
                <TextBlock x:Name="PopGlyph" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="13" Foreground="#FFFFFFFF"
                           HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Grid>
              <Border x:Name="PopThumb" Width="50" Height="30" CornerRadius="5" Margin="8,0,0,0" ClipToBounds="True" Visibility="Collapsed">
                <Border.Background><ImageBrush x:Name="PopImg" Stretch="UniformToFill"/></Border.Background>
              </Border>
              <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                <TextBlock x:Name="PopTitle" Foreground="#FFFFFFFF" FontFamily="Segoe UI Variable Display, Segoe UI"
                           FontSize="13.5" FontWeight="SemiBold" MaxWidth="280" TextTrimming="CharacterEllipsis"/>
                <TextBlock x:Name="PopSub" Foreground="#99FFFFFF" FontFamily="Segoe UI Variable Text, Segoe UI"
                           FontSize="11.5" Margin="0,1,0,0" MaxWidth="280" TextTrimming="CharacterEllipsis"/>
              </StackPanel>
              <Grid x:Name="PopBarGrid" Width="140" Height="4" Margin="14,0,0,0" VerticalAlignment="Center" Visibility="Collapsed">
                <Border Background="#26FFFFFF" CornerRadius="2"/>
                <Border x:Name="PopBarFill" Background="#FFFFFFFF" CornerRadius="2" HorizontalAlignment="Left" Width="0"/>
              </Grid>
              <TextBlock x:Name="PopValue" Foreground="#CCFFFFFF" FontFamily="Cascadia Mono, Consolas" FontSize="12"
                         Margin="12,0,0,0" VerticalAlignment="Center"/>
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
          <!-- track info, only when the panel is opened from another view -->
          <StackPanel x:Name="MPanelInfo" Margin="0,0,0,10" Visibility="Collapsed">
            <TextBlock x:Name="MPanelTitle" Foreground="#FFFFFFFF" FontFamily="Segoe UI Variable Display, Segoe UI"
                       FontSize="13" FontWeight="SemiBold" MaxWidth="300" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="MPanelArtist" Foreground="#99FFFFFF" FontFamily="Segoe UI Variable Text, Segoe UI"
                       FontSize="11.5" Margin="0,1,0,0" MaxWidth="300" TextTrimming="CharacterEllipsis"/>
          </StackPanel>
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
          <!-- volume: speaker button mutes, the bar sets the level (click or drag) -->
          <DockPanel Margin="0,6,0,2">
            <Border x:Name="BtnMute" DockPanel.Dock="Left" Width="30" Height="26" CornerRadius="13" Background="#01FFFFFF">
              <TextBlock x:Name="MuteGlyph" Text="&#xE767;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14"
                         Foreground="#E6FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock x:Name="VolText" DockPanel.Dock="Right" Width="34" TextAlignment="Right" Foreground="#80FFFFFF"
                       FontFamily="Cascadia Mono, Consolas" FontSize="10.5" VerticalAlignment="Center"/>
            <Grid x:Name="VolGrid" Height="18" Margin="6,0,4,0" Background="#01FFFFFF" Cursor="Hand">
              <Border x:Name="VolTrack" Height="4" Background="#26FFFFFF" CornerRadius="2" VerticalAlignment="Center"/>
              <Border x:Name="VolFill" Height="4" Background="#E6FFFFFF" CornerRadius="2" VerticalAlignment="Center"
                      HorizontalAlignment="Left" Width="0"/>
            </Grid>
          </DockPanel>
        </StackPanel>
        </StackPanel>

        <!-- System stats (stats button) -->
        <StackPanel x:Name="StatsPanel" Visibility="Collapsed">
          <StackPanel Margin="2,12,2,0" MinWidth="250">
            <Border Height="1" Background="#1FFFFFFF" Margin="0,0,0,8"/>
            <StackPanel x:Name="StatLines"/>
          </StackPanel>
        </StackPanel>

        <!-- room for the panel buttons below -->
        <Border x:Name="ToolsSpace" Height="42" Visibility="Collapsed"/>
      </StackPanel>

      <!-- Panel buttons, shown while expanded: music on the left, stats on the right. Pinned to the
           bottom of the (fixed-size) expanded island, so they never move -->
      <Grid x:Name="Tools" Visibility="Collapsed" VerticalAlignment="Bottom" Margin="12,0,16,10">
        <Border x:Name="BtnMusicPanel" Width="30" Height="30" CornerRadius="15" Background="#1AFFFFFF"
                HorizontalAlignment="Left" Cursor="Hand" ToolTip="Music and volume">
          <TextBlock Text="&#xE8D6;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="13"
                     Foreground="#E6FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="BtnStatsPanel" Width="30" Height="30" CornerRadius="15" Background="#1AFFFFFF"
                HorizontalAlignment="Right" Cursor="Hand" ToolTip="System stats">
          <TextBlock Text="&#xE9D9;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="13"
                     Foreground="#E6FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </Grid>
      </Grid>
      </Grid>
    </Border>
    </Grid>
    <!-- Click-through hint, shown under the pill after hovering it for a while -->
    <Border x:Name="Hint" HorizontalAlignment="Center" VerticalAlignment="Top" Background="#E60B0B0D"
            CornerRadius="9" Padding="10,4,10,5" Opacity="0" IsHitTestVisible="False">
      <TextBlock Text="Ctrl+click to use the island" Foreground="#E6FFFFFF"
                 FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11.5"/>
    </Border>
  </Grid>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

foreach ($n in 'Pill','Ring','Dot','IconBg','Check','Bang','TitleText','SubText','TimerText','Badge','BadgeText',
               'Details','Rows','ClaudeRow','MusicRow','Art','ArtNote','MTitle','MArtist','Eq','MusicDetails',
               'ProgGrid','ProgTrack','ProgFill','TimeGrid','PosText','DurText','BtnPrev','BtnPlay','BtnNext','PlayGlyph',
               'Mascot','MLight','MShade','Eyes','EyeL','EyeR','HappyL','HappyR','Blob','CompImg','RootGrid','RootScale','Inner','Glass','Tint','SizeHost','PeekHost','Hint','StatsRow',
               'MPanelInfo','MPanelTitle','MPanelArtist','BtnMute','MuteGlyph','VolText','VolGrid','VolTrack','VolFill',
               'StatsPanel','StatLines','Tools','ToolsSpace',
               'Zzz','PopupRow','PopDot','PopRing','PopGlyph','PopThumb','PopImg','PopTitle','PopSub','PopBarGrid','PopBarFill','PopValue','BtnMusicPanel','BtnStatsPanel') {
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
        $da = [byte][math]::Round(255 * [math]::Max((Clamp $script:cfg.expandedOpacity 0 1), (Clamp $script:cfg.backgroundOpacity 0 1)))
        $script:darkColor  = [System.Windows.Media.Color]::FromArgb($da, $c.R, $c.G, $c.B)
        $script:dark = $false
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

# ---- compact notch: shown instead of the pill while a fullscreen app is in front ----
# A slim black tab flush with the top edge: Claude's status icon on the left, the time on the right.
[xml]$notchXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Island Notch" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ShowActivated="False"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight" UseLayoutRounding="True">
  <!-- VerticalAlignment Top: Windows keeps windows at least ~39 px tall, so a centered
       28 px bar would float a few pixels below the screen edge -->
  <Border x:Name="NBar" Background="#000000" CornerRadius="0,0,11,11" Height="28" MinWidth="150" Padding="11,0,13,0"
          VerticalAlignment="Top">
    <DockPanel LastChildFill="False">
      <Grid DockPanel.Dock="Left" Width="14" Height="14" VerticalAlignment="Center">
        <Path x:Name="NIcon" Width="13" Height="13" Stretch="Uniform"
              Data="M6.5,0 L6.5,13 M0,6.5 L13,6.5 M1.9,1.9 L11.1,11.1 M11.1,1.9 L1.9,11.1"
              Stroke="#D97857" StrokeThickness="2.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
        <TextBlock x:Name="NGlyph" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Visibility="Collapsed"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Grid>
      <TextBlock x:Name="NText" DockPanel.Dock="Right" Margin="24,0,0,0" VerticalAlignment="Center"
                 Foreground="#D97857" FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="13" FontWeight="SemiBold"/>
      <Grid x:Name="NBarGrid" DockPanel.Dock="Right" Width="70" Height="4" Margin="12,0,0,0" VerticalAlignment="Center" Visibility="Collapsed">
        <Border Background="#33FFFFFF" CornerRadius="2"/>
        <Border x:Name="NBarFill" Background="#FFFFFFFF" CornerRadius="2" HorizontalAlignment="Left" Width="0"/>
      </Grid>
    </DockPanel>
  </Border>
</Window>
"@
$nwin  = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $notchXaml))
$uiNIcon = $nwin.FindName('NIcon'); $uiNText = $nwin.FindName('NText'); $uiNGlyph = $nwin.FindName('NGlyph')
$uiNBarGrid = $nwin.FindName('NBarGrid'); $uiNBarFill = $nwin.FindName('NBarFill')
$script:notchHwnd = [IntPtr]::Zero
$script:notchOn = $false; $script:notchMon = $null; $script:notchMode = ''
$nwin.Add_SourceInitialized({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper($nwin)).Handle
    $script:notchHwnd = $h
    $ex = [IslandNative]::GetWindowLong($h, -20)
    [void][IslandNative]::SetWindowLong($h, -20, ($ex -bor 0x20 -bor 0x80 -bor 0x08000000))  # TRANSPARENT | TOOLWINDOW | NOACTIVATE
})
function Place-Notch {
    $r = $script:notchMon
    if (-not $r -or $nwin.ActualWidth -le 0) { return }
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    $k = if ($src) { $src.CompositionTarget.TransformFromDevice.M11 } else { 1 }
    $nwin.Left = ($r[0] + ($r[2] - $r[0]) / 2) * $k - $nwin.ActualWidth / 2
    $nwin.Top  = $r[1] * $k
}
$nwin.Add_SizeChanged({ Place-Notch })
# The fullscreen monitor's rect in pixels, or $null when nothing fullscreen is in front
function Get-Fullscreen {
    if (-not $script:cfg.fullscreenNotch) { return $null }
    try { [IslandNative]::FullscreenRect($script:mainHwnd, $script:notchHwnd) } catch { $null }
}
# What the notch shows: Claude's icon (or a popup's glyph), a text, and optionally a slim bar
function Set-NotchContent($color, [string]$text, $glyph = $null, [bool]$pulse = $false, $bar = $null) {
    $b = New-Brush ([string]$color)
    $uiNText.Foreground = $b; $uiNText.Text = $text
    if ($glyph) { $uiNGlyph.Text = [string]$glyph; $uiNGlyph.Foreground = $b; $uiNGlyph.Visibility = 'Visible'; $uiNIcon.Visibility = 'Collapsed' }
    else { $uiNIcon.Stroke = $b; $uiNIcon.Visibility = 'Visible'; $uiNGlyph.Visibility = 'Collapsed' }
    if ($null -ne $bar) { $uiNBarGrid.Visibility = 'Visible'; $uiNBarFill.Width = 70 * (Clamp $bar 0 1); $uiNBarFill.Background = $b }
    else { $uiNBarGrid.Visibility = 'Collapsed' }
    $key = "$pulse|$glyph"
    if ($key -ne $script:notchMode) {
        $script:notchMode = $key
        if ($pulse) { Loop $uiNIcon $OpacityProp 1 0.35 900 $true (Sine) } else { Stop-Anim $uiNIcon $OpacityProp; $uiNIcon.Opacity = 1 }
    }
}
function Show-NotchAt($mon) {
    $script:notchMon = $mon
    if (-not $script:notchOn) {
        $script:notchOn = $true
        $nwin.Opacity = 0; $nwin.Show()
        Animate $nwin $OpacityProp 1 150
    }
    Place-Notch
    # fullscreen apps (and video players) can put themselves on top; stay above them
    if ($script:notchHwnd -ne [IntPtr]::Zero) { [IslandNative]::ForceTopmost($script:notchHwnd) }
}
function Show-Notch($mode, $pick, $now, $mon) {
    switch ($mode) {
        'working' { Set-NotchContent $script:cfg.accent (Format-Elapsed ($now - [int64]$pick.started)) $null $true }
        'needs'   { Set-NotchContent $script:cfg.needsColor 'Needs you' }
        'done'    { Set-NotchContent $script:cfg.doneColor (Format-Elapsed ([int64]$pick.finished - [int64]$pick.started)) }
    }
    Show-NotchAt $mon
}
function Hide-Notch {
    if (-not $script:notchOn) { return }
    $script:notchOn = $false; $script:notchMode = ''
    Stop-Anim $nwin $OpacityProp; $nwin.Hide()
}

# ---- mascot -------------------------------------------------------------
$script:mood = 'normal'
# ---- companions -----------------------------------------------------------
# Built-in: the blob (any palette color). Custom: custom images\<Name>\ with images per state:
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
    foreach ($st in 'idle', 'working', 'needs', 'done', 'music', 'sleep') { $frames[$st] = @(Load-Frames $files $st) }
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
    switch ($mood) { 'focused' { 'working' } 'alert' { 'needs' } 'happy' { 'done' } 'groove' { 'music' } 'sleepy' { 'sleep' } default { 'idle' } }
}
function Show-CompState($state) {
    $c = $script:comp
    if (-not $c) { return }
    $fr = $c.frames[$state]
    if (-not $fr -or $fr.Count -eq 0) { $fr = if ($state -eq 'sleep') { @($c.frames.idle[0]) } else { $c.frames.idle } }   # asleep: hold still
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
    if ($script:mood -eq 'sleepy') {   # waking up
        Stop-Anim $uiZzz $OpacityProp; $uiZzz.Opacity = 0; Stop-Anim $uiZzz.RenderTransform $TransYProp
        Stop-Anim $eyeBlink $ScaleYProp; $eyeBlink.ScaleY = 1
        if ($script:comp) { Stop-Anim $compScale $ScaleYProp; $compScale.ScaleY = 1 }
    }
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
        'sleepy' {
            # eyes shut, slow breathing and a little "z" drifting up
            $eyeBlink.BeginAnimation($ScaleYProp, $null); $eyeBlink.ScaleY = 0.12
            if ($script:comp -and -not ($script:comp.frames.sleep.Count)) { Loop $compScale $ScaleYProp 1.0 0.95 1800 $true (Sine) }
            if (-not ($script:comp -and $script:comp.frames.sleep.Count)) {   # a companion's own sleep frames draw their own z
                Loop $uiZzz $OpacityProp 0 0.9 1400 $true (Sine)
                Loop $uiZzz.RenderTransform $TransYProp 2 -4 2800 $false
            }
        }
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
    if ($script:mood -eq 'happy' -or $script:mood -eq 'groove' -or $script:mood -eq 'sleepy') { return }
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
    $key = "$mode|$($script:artColor)|$($script:popColor)"
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
        'stats' {
            $glow.Color = New-Color '#8E8E93'; $glow.Opacity = 0.2 * $script:glowK
            Mascot-Mood 'normal'
        }
        'popup' {
            $glow.Color = New-Color $script:popColor; $glow.Opacity = 0.45 * $script:glowK
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
    [void]$k.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearColorKeyFrame((Get-TintTarget), $KT::FromPercent(1))))
    $b.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $k)
}
# Expanded, the background turns darker so the text reads well over anything behind it
$script:dark = $false
function Get-TintTarget { if ($script:dark) { $script:darkColor } else { $script:tintColor } }
function Set-Dark([bool]$on) {
    if ($on -eq $script:dark -or -not $script:darkColor) { return }
    $script:dark = $on
    $b = $uiTint.Fill
    if (-not ($b -is [System.Windows.Media.SolidColorBrush])) { return }
    if ($b.IsFrozen) { $b = $b.Clone(); $uiTint.Fill = $b }
    $a = New-Object System.Windows.Media.Animation.ColorAnimation((Get-TintTarget), (Dur 200))
    $b.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $a)
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
# Expanded height: the header plus the tallest of the music and stats panels (filled or not),
# so switching panels or data arriving never resizes the island.
function Get-FixedHeight {
    if (-not $script:statLines) { Fill-StatsPanel }
    $els = @($uiDetails, $uiMusicDetails, $uiStatsPanel, $uiMPanelInfo, $uiProgGrid, $uiTimeGrid)
    $was = @($els | ForEach-Object { $_.Visibility })
    $inf = New-Object System.Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)
    $uiDetails.Visibility = 'Collapsed'; $uiStatsPanel.Visibility = 'Collapsed'
    foreach ($e in $uiMusicDetails, $uiProgGrid, $uiTimeGrid) { $e.Visibility = 'Visible' }
    $uiMPanelInfo.Visibility = if ($script:viewKind -eq 'music') { 'Collapsed' } else { 'Visible' }
    $uiInner.Measure($inf); $h1 = $uiInner.DesiredSize.Height
    $uiMusicDetails.Visibility = 'Collapsed'; $uiStatsPanel.Visibility = 'Visible'
    $uiInner.Measure($inf); $h2 = $uiInner.DesiredSize.Height
    for ($i = 0; $i -lt $els.Count; $i++) { $els[$i].Visibility = $was[$i] }
    [math]::Ceiling([math]::Max($h1, $h2))
}
function Sync-Size {
    $hoverChanged = ($script:hover -ne $script:sizeHover)
    $script:sizeHover = $script:hover
    $ms = if ($hoverChanged) { Get-Ms 'expandMs' } else { Get-Ms 'resizeMs' }
    # Measure the natural size, counting panels that are on their way out as already gone
    $closing = @($uiDetails, $uiMusicDetails, $uiStatsPanel, $uiTools | Where-Object { [string]$_.Tag -eq 'closing' })
    foreach ($c in $closing) { $c.Visibility = 'Collapsed' }
    $uiInner.Width = [double]::NaN
    $uiInner.Measure((New-Object System.Windows.Size([double]::PositiveInfinity, [double]::PositiveInfinity)))
    $d = $uiInner.DesiredSize
    foreach ($c in $closing) { $c.Visibility = 'Visible' }
    $w = [math]::Ceiling([math]::Max(208, $d.Width)); $h = [math]::Ceiling($d.Height)
    if ($script:hover) {
        # expanded: one fixed size (grown only if something doesn't fit), so the buttons stay put
        $w = [math]::Max($w, [math]::Ceiling((Clamp $script:cfg.expandedWidth 208 800)))
        $h = [math]::Max($h, [math]::Max((Get-FixedHeight), [math]::Ceiling((Clamp $script:cfg.expandedHeight 0 800))))
    }
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
    foreach ($p in $uiDetails, $uiMusicDetails, $uiStatsPanel, $uiTools) { $p.Visibility = 'Collapsed'; $p.Tag = '' }
    $script:panel = ''; Set-Dark $false
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
    $uiClaudeRow.Visibility = 'Collapsed'; $uiMusicRow.Visibility = 'Visible'; $uiStatsRow.Visibility = 'Collapsed'; $uiPopupRow.Visibility = 'Collapsed'; $uiDetails.Visibility = 'Collapsed'; $uiDetails.Tag = ''
    Set-Look $(if ($m.playing) { 'music' } else { 'musicpaused' })
    Set-Text $uiMTitle ([string]$m.title)
    Set-Text $uiMArtist ([string]$(if ($m.artist) { $m.artist } else { $m.appName }))
    Update-Panels 'music' $null $now
    $script:dismissKey = ''
    Set-View 'music'
    Sync-Size
    $key = "music|$($script:musicKey)"
    if ($script:shown -and $key -ne $script:lastKey) { Bump-Pill }
    $script:lastKey = $key
    Show-Pill
}

# ---- popups ---------------------------------------------------------------
# Short notices (a device connected, the volume changed, a screenshot was saved, ...) that take
# over the pill, or the fullscreen notch, for a few seconds. The newest wins; one with the same
# key (like the volume bar) updates in place. They wait while the island is expanded.
$script:popup = $null; $script:popColor = '#FFFFFF'
$script:events = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
function Show-Popup([string]$key, $glyph, [string]$title, [string]$sub = '', [string]$color = '#FFFFFF',
                    [double]$seconds = 0, $bar = $null, [string]$value = '', $image = $null, $open = $null) {
    if (-not $script:cfg.popups) { return }
    if ($seconds -le 0) { $seconds = Clamp $script:cfg.popupSeconds 1 30 }
    $now = Get-Now
    $same = $script:popup -and $script:popup.key -eq $key
    $script:popup = @{ key = $key; glyph = [string]$(if ($glyph -is [int]) { [char]$glyph } else { $glyph }); title = $title; sub = $sub
                       color = $color; until = $now + [int]($seconds * 1000); bar = $bar; value = $value; image = $image; open = $open
                       at = $(if ($same) { $script:popup.at } else { $now }) }
    if (-not $same -and @('volume', 'brightness') -notcontains $key) { Mascot-Hop 'perk' }
}
function Get-Popup($now) {
    $p = $script:popup
    if ($p -and $now -lt $p.until) { return $p }
    $script:popup = $null; $null
}
function Show-PopupView($p, $now) {
    $uiClaudeRow.Visibility = 'Collapsed'; $uiMusicRow.Visibility = 'Collapsed'; $uiStatsRow.Visibility = 'Collapsed'; $uiPopupRow.Visibility = 'Visible'
    $script:popColor = [string]$p.color
    Set-Look 'popup'
    $c = New-Color ([string]$p.color)
    $uiPopDot.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(56, $c.R, $c.G, $c.B))
    $uiPopGlyph.Text = $p.glyph; $uiPopGlyph.Foreground = New-Brush ([string]$p.color)
    if ($null -ne $p.ring) { Set-Ring $p.ring ([string]$p.color); $uiPopRing.Visibility = 'Visible' } else { $uiPopRing.Visibility = 'Collapsed' }
    $uiPopDot.Parent.Visibility = if ($p.image) { 'Collapsed' } else { 'Visible' }
    if ($p.image) { $uiPopImg.ImageSource = $p.image; $uiPopThumb.Visibility = 'Visible' } else { $uiPopThumb.Visibility = 'Collapsed' }
    $uiPopTitle.Text = $p.title
    $uiPopSub.Text = $p.sub; $uiPopSub.Visibility = if ($p.sub) { 'Visible' } else { 'Collapsed' }
    if ($null -ne $p.bar) { $uiPopBarGrid.Visibility = 'Visible'; $uiPopBarFill.Width = 140 * (Clamp $p.bar 0 1) } else { $uiPopBarGrid.Visibility = 'Collapsed' }
    $uiPopValue.Text = $p.value; $uiPopValue.Visibility = if ($p.value) { 'Visible' } else { 'Collapsed' }
    Update-Panels 'popup' $null $now
    $script:dismissKey = ''
    Set-View 'popup'
    Sync-Size
    $key = "popup|$($p.key)|$($p.at)"
    if ($script:shown -and $key -ne $script:lastKey) { Bump-Pill }
    $script:lastKey = $key
    Show-Pill
}
# A progress ring around the popup's icon (the timer), starting at 12 o'clock
function Set-Ring([double]$frac, [string]$color) {
    $f = Clamp $frac 0 0.9999
    $a = 2 * [math]::PI * $f - [math]::PI / 2
    $x = 14 + 12.5 * [math]::Cos($a); $y = 14 + 12.5 * [math]::Sin($a)
    $uiPopRing.Data = [System.Windows.Media.Geometry]::Parse(('M14,1.5 A12.5,12.5 0 {0} 1 {1},{2}' -f $(if ($f -gt 0.5) { 1 } else { 0 }), $x.ToString($INV), $y.ToString($INV)))
    $uiPopRing.Stroke = New-Brush $color
}
function Show-PopupNotch($p, $mon) {
    $t = [string]$p.title; if ($p.value) { $t = "$t  $($p.value)" } elseif ($p.sub) { $t = "$t  $DOT  $($p.sub)" }
    if ($t.Length -gt 48) { $t = $t.Substring(0, 47) + $ELL }
    Set-NotchContent $p.color $t $p.glyph $false $p.bar
    Show-NotchAt $mon
}

# Event sources. Cheap checks run here on every refresh (the audio objects are cached);
# slow ones (devices, network, brightness) run on background threads and queue events.
$script:ownVolUntil = 0; $script:audioId = $null; $script:volSig = $null
$script:locks = $null; $script:power = $null; $script:powerAt = 0
$script:shotDirs = @(@((Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots'),
                       (Join-Path $env:USERPROFILE 'Pictures\Screenshots')) | Select-Object -Unique)
$script:shotStamp = @{}; $script:shotAt = 0
$script:dlDir = try { (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { Join-Path $env:USERPROFILE 'Downloads' }
$script:dlStamp = $null; $script:dlAt = 0; $script:dlSeen = @{}
$script:clipSeq = $null; $script:dnd = $null; $script:dndAt = 0; $script:meetingSeen = @{}
$script:inboxDir = Join-Path $StateDir 'inbox'; $script:inboxAt = 0
New-Item -ItemType Directory -Force -Path $script:inboxDir | Out-Null

# ---- timer / Pomodoro (tray menu > Timer) -----------------------------------
$script:countdown = $null
function Start-Timer([double]$minutes, [string]$label, [string]$phase = '') {
    $now = Get-Now
    $script:countdown = @{ start = $now; end = $now + [int64]($minutes * 60000); label = $label; phase = $phase }
    Update-Island
}
function Stop-Timer { $script:countdown = $null; Update-Island }
# The running timer as a popup-shaped view (no time limit), or $null; handles it running out
function Get-TimerView($now) {
    $tm = $script:countdown
    if (-not $tm) { return $null }
    if ($now -ge $tm.end) {
        $script:countdown = $null
        Play-Chime 'done'
        if ($tm.phase -eq 'focus') {
            Show-Popup 'timer' 0xE916 'Focus done' "Break for $($script:cfg.breakMinutes) min" '#34C759' 6
            Start-Timer ([double]$script:cfg.breakMinutes) 'Break' 'break'
        } elseif ($tm.phase -eq 'break') { Show-Popup 'timer' 0xE916 'Break over' 'Back to it' '#D97857' 6 }
        else { Show-Popup 'timer' 0xE916 "Time's up" $tm.label '#D97857' 6 }
        return $null
    }
    $left = $tm.end - $now
    $color = if ($tm.phase -eq 'break') { '#34C759' } else { [string]$script:cfg.accent }
    @{ key = 'timer'; glyph = [string][char]0xE916; title = $tm.label; sub = ''; color = $color; bar = $null
       value = (Format-Elapsed $left); image = $null; open = $null; at = $tm.start; ring = 1 - $left / ($tm.end - $tm.start) }
}
function Poll-Events($now) {
    $c = $script:cfg
    if (-not $c.popups) { return }
    # sound: output device, volume and mute
    try {
        $id = [IslandAudio]::DefaultId()
        if ($script:audioId -and $id -ne $script:audioId -and $c.popupAudioOutput) {
            Show-Popup 'audio' 0xE7F5 'Sound output' ([string][IslandAudio]::DefaultName()) '#8AB4FF'
            $script:volSig = $null
        }
        $script:audioId = $id
        $v = [int][math]::Round([IslandAudio]::GetVolume() * 100); $mu = [IslandAudio]::GetMute()
        $sig = "$id|$v|$mu"
        if ($script:volSig -and $sig -ne $script:volSig -and $c.popupVolume -and $now -gt $script:ownVolUntil) {
            if ($mu) { Show-Popup 'volume' 0xE74F 'Muted' '' '#FFFFFF' 1.6 0 '' }
            else { Show-Popup 'volume' $(if ($v -eq 0) { 0xE992 } elseif ($v -lt 34) { 0xE993 } elseif ($v -lt 67) { 0xE994 } else { 0xE995 }) 'Volume' '' '#FFFFFF' 1.6 ($v / 100) "$v%" }
        }
        $script:volSig = $sig
    } catch { }
    # Caps Lock / Num Lock
    $caps = [System.Windows.Forms.Control]::IsKeyLocked('CapsLock'); $num = [System.Windows.Forms.Control]::IsKeyLocked('NumLock')
    if ($script:locks -and $c.popupLocks) {
        if ($caps -ne $script:locks[0]) { Show-Popup 'caps' 0xE765 'Caps Lock' '' '#FFFFFF' 1.5 $null $(if ($caps) { 'ON' } else { 'OFF' }) }
        if ($num -ne $script:locks[1])  { Show-Popup 'num' 0xE765 'Num Lock' '' '#FFFFFF' 1.5 $null $(if ($num) { 'ON' } else { 'OFF' }) }
    }
    $script:locks = @($caps, $num)
    # battery and charger (laptops; a desktop has no battery and never shows these)
    if ($now - $script:powerAt -gt 4000) {
        $script:powerAt = $now
        try {
            $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
            if (-not ([int]$ps.BatteryChargeStatus -band 128)) {
                $pct = [int][math]::Round($ps.BatteryLifePercent * 100); $plugged = [string]$ps.PowerLineStatus -eq 'Online'
                $was = $script:power
                if ($was -and $c.popupBattery) {
                    if ($plugged -ne $was.plugged) {
                        if ($plugged) { Show-Popup 'power' 0xE83E 'Charging' '' '#34C759' 0 ($pct / 100) "$pct%" }
                        else { Show-Popup 'power' 0xE850 'On battery' '' '#FFFFFF' 0 ($pct / 100) "$pct%" }
                    } elseif (-not $plugged) {
                        foreach ($lvl in 20, 10, 5) {
                            if ($pct -le $lvl -and $was.pct -gt $lvl) { Show-Popup 'power' 0xE850 'Battery low' 'Plug in your charger' $(if ($lvl -le 10) { '#FF453A' } else { '#FFB340' }) 6 ($pct / 100) "$pct%"; break }
                        }
                    }
                }
                $script:power = @{ pct = $pct; plugged = $plugged }
            }
        } catch { }
    }
    # screenshots: a new image in Pictures\Screenshots (checked once a second, by folder time)
    if ($c.popupScreenshots -and $now - $script:shotAt -gt 1000) {
        $script:shotAt = $now
        foreach ($d in $script:shotDirs) {
            try {
                if (-not [IO.Directory]::Exists($d)) { continue }
                $stamp = [IO.Directory]::GetLastWriteTimeUtc($d)
                $was = $script:shotStamp[$d]; $script:shotStamp[$d] = $stamp
                if (-not $was -or $stamp -le $was) { continue }
                $f = Get-ChildItem -LiteralPath $d -File | Where-Object { $_.Extension -match '^\.(png|jpe?g)$' -and $_.LastWriteTimeUtc -gt $was.AddSeconds(-1) } |
                     Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                if (-not $f) { continue }
                $img = $null
                try {
                    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
                    $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.DecodePixelWidth = 160; $bi.UriSource = New-Object System.Uri $f.FullName; $bi.EndInit(); $bi.Freeze()
                    $img = $bi
                } catch { }
                Show-Popup 'shot' 0xE722 'Screenshot saved' 'Click to open' '#FFFFFF' 5 $null '' $img $f.FullName
            } catch { }
        }
    }
    # downloads: a new finished file in Downloads (browsers rename the partial file when done)
    if ($c.popupDownloads -and $script:dlDir -and $now - $script:dlAt -gt 1000) {
        $script:dlAt = $now
        try {
            $stamp = [IO.Directory]::GetLastWriteTimeUtc($script:dlDir)
            $was = $script:dlStamp; $script:dlStamp = $stamp
            if ($was -and $stamp -gt $was) {
                $f = Get-ChildItem -LiteralPath $script:dlDir -File | Where-Object {
                        $_.Extension -notmatch '^\.(crdownload|part|partial|tmp|download|opdownload)$' -and $_.LastWriteTimeUtc -gt $was.AddSeconds(-2) -and -not $script:dlSeen.ContainsKey($_.FullName) } |
                     Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                if ($f) {
                    $script:dlSeen[$f.FullName] = 1
                    Show-Popup 'download' 0xE896 'Download finished' $f.Name '#34C759' 5 $null '' $null @('explorer.exe', "/select,`"$($f.FullName)`"")
                }
            }
        } catch { }
    }
    # clipboard: Windows bumps a counter on every copy; password managers mark theirs as private
    $seq = [IslandNative]::GetClipboardSequenceNumber()
    if ($null -ne $script:clipSeq -and $seq -ne $script:clipSeq -and $c.popupClipboard) {
        try {
            $cb = [System.Windows.Clipboard]::GetDataObject()
            $fmts = @($cb.GetFormats())
            if ($fmts -contains 'ExcludeClipboardContentFromMonitorProcessing' -or $fmts -contains 'Clipboard Viewer Ignore') { }
            elseif ([System.Windows.Clipboard]::ContainsText()) {
                $txt = ([System.Windows.Clipboard]::GetText() -replace '\s+', ' ').Trim()
                if ($txt) { Show-Popup 'clip' 0xE8C8 'Copied' $(if ($txt.Length -gt 70) { $txt.Substring(0, 69) + $ELL } else { $txt }) '#FFFFFF' 2.5 }
            } elseif ([System.Windows.Clipboard]::ContainsImage()) {
                Show-Popup 'clip' 0xE8C8 'Image copied' '' '#FFFFFF' 2.5 $null '' ([System.Windows.Clipboard]::GetImage())
            } elseif ([System.Windows.Clipboard]::ContainsFileDropList()) {
                $l = [System.Windows.Clipboard]::GetFileDropList()
                Show-Popup 'clip' 0xE8C8 $(if ($l.Count -eq 1) { 'File copied' } else { "$($l.Count) files copied" }) ([IO.Path]::GetFileName($l[0])) '#FFFFFF' 2.5
            }
        } catch { }
    }
    $script:clipSeq = $seq
    # Do Not Disturb (Windows 11 keeps it as "toasts disabled")
    if ($now - $script:dndAt -gt 2000) {
        $script:dndAt = $now
        try {
            $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' -Name NOC_GLOBAL_SETTING_TOASTS_ENABLED -ErrorAction Stop).NOC_GLOBAL_SETTING_TOASTS_ENABLED
            $dnd = ($v -eq 0)
        } catch { $dnd = $false }
        if ($null -ne $script:dnd -and $dnd -ne $script:dnd -and $c.popupFocus) {
            Show-Popup 'dnd' 0xE708 $(if ($dnd) { 'Do not disturb on' } else { 'Do not disturb off' }) '' $(if ($dnd) { '#BF5AF2' } else { '#8E8E93' })
        }
        $script:dnd = $dnd
    }
    # calendar: a meeting starting soon (from the iCal link, fetched in the background)
    $script:stats.icsUrl = [string]$c.calendarIcsUrl
    $script:stats.github = [bool]$c.popupGitHub; $script:stats.inbox = $script:inboxDir
    $script:stats.weatherCity = [string]$c.weatherCity
    $soon = [int](Clamp $c.calendarMinutes 1 120) * 60000
    foreach ($ev in @($script:stats.meetings)) {
        if (-not $ev) { continue }
        $left = [int64]$ev.start - $now
        $k = "$($ev.start)|$($ev.title)"
        if ($left -gt 0 -and $left -le $soon -and -not $script:meetingSeen.ContainsKey($k)) {
            $script:meetingSeen[$k] = 1
            Show-Popup 'meeting' 0xE787 $ev.title ('Starts in {0} min' -f [math]::Max(1, [math]::Round($left / 60000))) '#FFB340' 10
            Play-Chime 'needs'
        }
    }
    # notices sent with notch.cmd / scripts\notch.ps1 (builds, tests, your own scripts)
    if ($now - $script:inboxAt -gt 400) {
        $script:inboxAt = $now
        try {
            foreach ($f in [IO.Directory]::GetFiles($script:inboxDir, '*.json')) {
                try { $n = [IO.File]::ReadAllText($f) | ConvertFrom-Json } catch { $n = $null }
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
                if (-not $n) { continue }
                switch ([string]$n.kind) {
                    'success' { Show-Popup 'notch' 0xE73E ([string]$n.title) ([string]$n.text) '#34C759' 6; Mascot-Hop 'celebrate' }
                    'fail'    { Show-Popup 'notch' 0xE711 ([string]$n.title) ([string]$n.text) '#FF453A' 8; Play-Chime 'needs' }
                    'timer'   { Start-Timer ([double]$n.minutes) ([string]$n.title) }
                    'github'  { Show-Popup 'github' 0xE8A7 ([string]$n.title) ([string]$n.text) $(if ($n.ok) { '#34C759' } else { '#FF453A' }) 8 $null '' $null ([string]$n.url) }
                    default   { Show-Popup 'notch' 0xE946 ([string]$n.title) ([string]$n.text) '#FFFFFF' 5 }
                }
            }
        } catch { }
    }
    # queued from the background threads
    while ($script:events.Count) {
        $e = $script:events.Dequeue()
        try {
            switch ($e.kind) {
                'device' {
                    if (-not $c.popupDevices) { break }
                    $names = @($e.names)
                    $best = @($names | Where-Object { $_ -like 'AudioEndpoint|*' }) + @($names | Where-Object { $_ -notlike 'AudioEndpoint|*' })
                    $cls, $name = ([string]$best[0]) -split '\|', 2
                    $glyph = switch ($cls) { 'AudioEndpoint' { 0xE7F6 } 'Mouse' { 0xE962 } 'Keyboard' { 0xE765 } 'DiskDrive' { 0xE88E } 'WPD' { 0xE8EA } { $_ -in 'Camera', 'Image' } { 0xE722 } default { 0xE772 } }
                    $more = if ($names.Count -gt 1 -and $cls -ne 'AudioEndpoint') { " (+$($names.Count - 1))" } else { '' }
                    if ($e.on) { Show-Popup 'device' $glyph 'Connected' "$name$more" '#34C759'; Mascot-Hop 'celebrate' }
                    else { Show-Popup 'device' $glyph 'Disconnected' "$name$more" '#8E8E93' }
                }
                'net' { if ($c.popupNetwork) { Show-Popup 'net' $e.glyph $e.title $e.sub $e.color } }
                'update' {
                    $script:update = $e
                    $miUpdate.Text = "Install update v$($e.version)"; $miUpdate.Visible = $true
                    Show-Popup 'update' 0xE896 "Update available: v$($e.version)" 'Click to install, or tray menu > Install update' '#8AB4FF' 12 $null '' $null '::update'
                }
                'uptodate' { Show-Popup 'update' 0xE73E 'Up to date' "v$($e.version) is the latest" '#34C759' }
                'updateerr' { Show-Popup 'update' 0xE783 "Couldn't check for updates" $e.text '#FFB340' 6 }
                'brightness' { if ($c.popupVolume) { Show-Popup 'brightness' 0xE706 'Brightness' '' '#FFFFFF' 1.6 ($e.value / 100) "$($e.value)%" } }
            }
        } catch { }
    }
}

# Devices: Windows signals any device change (no polling); then the present headphones, mice,
# keyboards, drives, phones and cameras are compared with the last look to name what changed.
$devPs = [PowerShell]::Create()
[void]$devPs.AddScript({
    param($st, $q)
    Add-Type -AssemblyName System.Management
    $filter = "Present = TRUE AND (PNPClass = 'AudioEndpoint' OR PNPClass = 'Mouse' OR PNPClass = 'Keyboard' OR PNPClass = 'DiskDrive' OR PNPClass = 'WPD' OR PNPClass = 'Camera' OR PNPClass = 'Image')"
    function Snap { $h = @{}; foreach ($d in @(Get-CimInstance Win32_PnPEntity -Filter $filter -ErrorAction SilentlyContinue)) { if ($d.Name) { $h[[string]$d.DeviceID] = "$($d.PNPClass)|$($d.Name)" } }; $h }
    $prev = Snap
    $w = New-Object System.Management.ManagementEventWatcher 'SELECT * FROM Win32_DeviceChangeEvent'
    $w.Options.Timeout = [TimeSpan]::FromSeconds(1)
    while ($st.on) {
        try { [void]$w.WaitForNextEvent() } catch { continue }   # timeout: just check $st.on again
        Start-Sleep -Milliseconds 800                              # one plug-in fires a burst of changes
        $now = Snap
        $added = @($now.Keys | Where-Object { -not $prev.ContainsKey($_) } | ForEach-Object { $now[$_] })
        $removed = @($prev.Keys | Where-Object { -not $now.ContainsKey($_) } | ForEach-Object { $prev[$_] })
        $prev = $now
        if ($added.Count) { $q.Enqueue(@{ kind = 'device'; on = $true; names = $added }) }
        if ($removed.Count) { $q.Enqueue(@{ kind = 'device'; on = $false; names = $removed }) }
    }
    $w.Stop(); $w.Dispose()
})

# ---- expanded panels ------------------------------------------------------
# While expanded, round buttons open a panel: music and volume (left), system stats (right).
# Without a choice, each view opens its own: Claude shows sessions, music shows its controls.
# Like Vorssaint's notch shelf buttons. $script:panel is '', 'none', 'music' or 'stats'.
$script:panel = ''; $script:holdUntil = 0; $script:lastWant = $null; $script:switchAt = 0
function Get-WantPanel($view) {
    if ($script:panel -eq 'none') { return '' }
    if ($script:panel) { return $script:panel }
    switch ($view) { 'music' { 'music' } 'claude' { 'sessions' } default { '' } }
}
# Switching panels while expanded swaps them in place (the island keeps its size): the old one
# goes at once and the new one fades in where it stands, instead of sliding up from below.
function Show-Now($el) {
    $el.Tag = 'open'; $el.Visibility = 'Visible'
    Animate $el $OpacityProp 1 120 $null 0
}
function Hide-Now($el) { $el.BeginAnimation($OpacityProp, $null); $el.Visibility = 'Collapsed'; $el.Tag = '' }
function Update-Panels($view, $sessions, $now) {
    if (-not $script:hover) { $script:panel = '' }
    Set-Dark $script:hover
    $want = Get-WantPanel $view
    $swap = $script:hover -and $null -ne $script:lastWant -and $want -ne $script:lastWant
    $script:lastWant = if ($script:hover) { $want } else { $null }
    $panels = [ordered]@{ sessions = $uiDetails; music = $uiMusicDetails; stats = $uiStatsPanel }
    if ($swap) { foreach ($k in $panels.Keys) { if ($k -ne $want) { Hide-Now $panels[$k] } } }
    if ($script:hover -and $want -eq 'sessions') { Render-Details $sessions $now } elseif (-not $swap) { Shrink-Out $uiDetails }
    if ($script:hover -and $want -eq 'music') { Fill-MusicPanel $view $now; if (-not $swap) { Grow-In $uiMusicDetails } } elseif (-not $swap) { Shrink-Out $uiMusicDetails }
    if ($script:hover -and $want -eq 'stats') { Fill-StatsPanel; if (-not $swap) { Grow-In $uiStatsPanel } } elseif (-not $swap) { Shrink-Out $uiStatsPanel }
    if ($swap -and $want -and ($want -ne 'sessions' -or $uiRows.Children.Count)) { Show-Now $panels[$want] }
    if ($script:hover) { Grow-In $uiTools } else { Shrink-Out $uiTools }
    $uiToolsSpace.Visibility = if ($script:hover) { 'Visible' } else { 'Collapsed' }
    $uiBtnMusicPanel.Background = New-Brush $(if ($want -eq 'music') { '#4DFFFFFF' } else { '#1AFFFFFF' })
    $uiBtnStatsPanel.Background = New-Brush $(if ($want -eq 'stats') { '#4DFFFFFF' } else { '#1AFFFFFF' })
}
# A button opens its panel; pressing the open panel's button again does nothing, and clicks
# while a switch is still settling are ignored.
function Open-Panel($which) {
    $now = Get-Now
    if ((Get-WantPanel $script:viewKind) -eq $which -or $now -lt $script:switchAt + 300) { return }
    $script:panel = $which
    $script:switchAt = $now
    $script:holdUntil = $now + 1500   # don't treat anything moving under the cursor as leaving
    Update-Island
}
$uiBtnMusicPanel.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; try { Open-Panel 'music' } catch { Write-Log ("panel: " + $_.Exception.Message) } })
$uiBtnStatsPanel.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; try { Open-Panel 'stats' } catch { Write-Log ("panel: " + $_.Exception.Message) } })

function Fill-MusicPanel($view, $now) {
    $m = $script:music
    $uiMPanelInfo.Visibility = if ($view -ne 'music') { 'Visible' } else { 'Collapsed' }
    if ($m) {
        $uiMPanelTitle.Text = [string]$m.title
        $uiMPanelArtist.Text = [string]$(if ($m.artist) { $m.artist } else { $m.appName })
    } else { $uiMPanelTitle.Text = 'Nothing playing'; $uiMPanelArtist.Text = '' }
    $uiPlayGlyph.Text = if ($m -and $m.playing) { $GLYPH_PAUSE } else { $GLYPH_PLAY }
    if ($m -and $m.dur -gt 1000) {
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
    Update-Volume
}
function Update-Volume {
    try { $v = [IslandAudio]::GetVolume(); $mute = [IslandAudio]::GetMute() } catch { $uiVolText.Text = '--'; return }
    $uiVolFill.Width = [math]::Max(0, $uiVolTrack.ActualWidth * $v)
    $uiVolFill.Background = New-Brush $(if ($mute) { '#59FFFFFF' } else { '#E6FFFFFF' })
    $uiVolText.Text = '{0}%' -f [int][math]::Round($v * 100)
    $uiMuteGlyph.Text = [string][char]$(if ($mute) { 0xE74F } else { 0xE767 })
}
function Set-Volume([double]$v) {
    $script:ownVolUntil = (Get-Now) + 1500   # the panel already shows it; no volume popup
    try { [IslandAudio]::SetVolume([float](Clamp $v 0 1)); if ([IslandAudio]::GetMute()) { [IslandAudio]::SetMute($false) } } catch { }
    Update-Volume
}
function Set-VolFromMouse($e) {
    $w = $uiVolGrid.ActualWidth
    if ($w -gt 0) { Set-Volume ($e.GetPosition($uiVolGrid).X / $w) }
}
$uiVolGrid.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; [void]$uiVolGrid.CaptureMouse(); Set-VolFromMouse $e })
$uiVolGrid.Add_MouseMove({ param($s, $e) if ($uiVolGrid.IsMouseCaptured) { Set-VolFromMouse $e } })
$uiVolGrid.Add_MouseLeftButtonUp({ param($s, $e) $e.Handled = $true; $uiVolGrid.ReleaseMouseCapture() })
$uiMusicDetails.Add_MouseWheel({
    param($s, $e) $e.Handled = $true
    try { Set-Volume ([IslandAudio]::GetVolume() + [math]::Sign($e.Delta) * 0.02) } catch { }
})
$uiBtnMute.Add_MouseEnter({ $this.Background = New-Brush '#1FFFFFFF' })
$uiBtnMute.Add_MouseLeave({ $this.Background = New-Brush '#01FFFFFF' })
$uiBtnMute.Add_MouseLeftButtonUp({
    param($s, $e) $e.Handled = $true
    $script:ownVolUntil = (Get-Now) + 1500
    try { [IslandAudio]::SetMute(-not [IslandAudio]::GetMute()) } catch { }
    Update-Volume
})

# Compact 2 x 2 grid (CPU, GPU / RAM, NET), so the stats panel is no taller than the music one
$script:statLines = $null
function New-StatCell($label, $col, $row) {
    $cell = New-Object System.Windows.Controls.StackPanel
    $cell.Margin = New-Object System.Windows.Thickness($(if ($col) { 10 } else { 0 }), 0, $(if ($col) { 0 } else { 10 }), 8)
    [System.Windows.Controls.Grid]::SetColumn($cell, $col); [System.Windows.Controls.Grid]::SetRow($cell, $row)
    $top = New-Object System.Windows.Controls.DockPanel
    $l = New-Object System.Windows.Controls.TextBlock
    $l.Text = $label; $l.Foreground = New-Brush '#80FFFFFF'; $l.FontSize = 11; $l.FontWeight = 'SemiBold'; $l.VerticalAlignment = 'Center'
    $l.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI Variable Text, Segoe UI'
    $v = New-Object System.Windows.Controls.TextBlock
    $v.Foreground = New-Brush '#FFFFFFFF'; $v.FontSize = 12; $v.VerticalAlignment = 'Center'; $v.TextAlignment = 'Right'
    $v.FontFamily = New-Object System.Windows.Media.FontFamily 'Cascadia Mono, Consolas'
    [void]$top.Children.Add($l); [void]$top.Children.Add($v)
    [System.Windows.Controls.DockPanel]::SetDock($l, 'Left')
    $bar = New-Object System.Windows.Controls.Grid
    $bar.Height = 4; $bar.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
    $track = New-Object System.Windows.Controls.Border; $track.Background = New-Brush '#26FFFFFF'; $track.CornerRadius = 2
    $fill = New-Object System.Windows.Controls.Border; $fill.Background = New-Brush '#E6FFFFFF'; $fill.CornerRadius = 2
    $fill.RenderTransformOrigin = New-Object System.Windows.Point(0, 0.5)
    $fill.RenderTransform = New-Object System.Windows.Media.ScaleTransform(0, 1)
    [void]$bar.Children.Add($track); [void]$bar.Children.Add($fill)
    [void]$cell.Children.Add($top); [void]$cell.Children.Add($bar)
    [void]$script:statGrid.Children.Add($cell)
    @{ cell = $cell; bar = $bar; fill = $fill; value = $v }
}
function Set-StatLine($line, $frac, [string]$text) {
    if ($null -eq $frac) { $line.bar.Visibility = 'Hidden' }      # keeps its height, so rows stay aligned
    else { $line.bar.Visibility = 'Visible'; $line.fill.RenderTransform.ScaleX = Clamp $frac 0 1 }
    $line.value.Text = $text
}
function Get-WeatherText([int]$code) {   # WMO weather codes, as Open-Meteo reports them
    switch ($code) {
        0 { 'Clear' } { $_ -in 1, 2 } { 'Partly cloudy' } 3 { 'Cloudy' } { $_ -in 45, 48 } { 'Fog' }
        { $_ -ge 51 -and $_ -le 57 } { 'Drizzle' } { $_ -ge 61 -and $_ -le 67 } { 'Rain' } { $_ -ge 71 -and $_ -le 77 } { 'Snow' }
        { $_ -ge 80 -and $_ -le 82 } { 'Showers' } { $_ -in 85, 86 } { 'Snow showers' } { $_ -ge 95 } { 'Thunderstorm' } default { '' }
    }
}
function Fill-StatsPanel {
    if (-not $script:statLines) {
        $script:statGrid = New-Object System.Windows.Controls.Grid
        foreach ($i in 0, 1) {
            $script:statGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $script:statGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        }
        [void]$uiStatLines.Children.Add($script:statGrid)
        $script:statLines = [ordered]@{
            cpu = New-StatCell 'CPU' 0 0; gpu = New-StatCell 'GPU' 1 0
            ram = New-StatCell 'RAM' 0 1; net = New-StatCell 'NET' 1 1
        }
        $script:statGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $script:wxText = New-Object System.Windows.Controls.TextBlock
        $script:wxText.Foreground = New-Brush '#CCFFFFFF'; $script:wxText.FontSize = 12; $script:wxText.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
        $script:wxText.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI Variable Text, Segoe UI'; $script:wxText.ToolTip = 'Weather data by Open-Meteo.com (CC BY 4.0)'
        [System.Windows.Controls.Grid]::SetRow($script:wxText, 2); [System.Windows.Controls.Grid]::SetColumnSpan($script:wxText, 2)
        [void]$script:statGrid.Children.Add($script:wxText)
    }
    $st = $script:stats; $L = $script:statLines; $deg = [string][char]0x00B0
    $t = if ($null -ne $st.cpu) { "$($st.cpu)%" } else { '--' }; if ($null -ne $st.cpuTemp) { $t += " $($st.cpuTemp)$deg" }
    Set-StatLine $L.cpu $(if ($null -ne $st.cpu) { $st.cpu / 100 }) $t
    $L.cpu.cell.ToolTip = if ($null -eq $st.cpuTemp) { 'CPU temperature needs LibreHardwareMonitor running' } else { $null }
    $t = if ($null -ne $st.gpu) { "$($st.gpu)%" } else { '--' }; if ($null -ne $st.gpuTemp) { $t += " $($st.gpuTemp)$deg" }
    Set-StatLine $L.gpu $(if ($null -ne $st.gpu) { $st.gpu / 100 }) $t
    $gb = $st.ramGB
    $t = if ($gb) { '{0}/{1} GB' -f $gb[0].ToString('0.0', $INV), $gb[1].ToString('0', $INV) } else { '--' }
    Set-StatLine $L.ram $(if ($null -ne $st.ram -and $st.ram -ge 0) { $st.ram / 100 }) $t
    Set-StatLine $L.net $null ([string][char]0x2193 + (Format-Rate $st.down) + ' ' + [char]0x2191 + (Format-Rate $st.up))
    $wx = $st.weather
    $script:wxText.Visibility = if ($script:cfg.weatherCity) { 'Visible' } else { 'Collapsed' }
    $script:wxText.Text = if (-not $wx) { 'Weather' + $ELL } elseif ($null -eq $wx.temp) { $wx.city } else { "$($wx.temp)$([char]0x00B0)  $(Get-WeatherText $wx.code)  $DOT  $($wx.city)" }
}
# ---- system stats ---------------------------------------------------------
# Collected on a background runspace every 2 s, so slow sources (performance counters,
# WMI) never stall the animations. CPU and RAM come from Windows directly, GPU load from
# the "GPU Engine" counters (Task Manager's GPU column). Temperatures need
# LibreHardwareMonitor (or OpenHardwareMonitor) running; NVIDIA GPU temps also come from
# nvidia-smi when it's installed. Anything unavailable is simply left out.
$script:stats = [hashtable]::Synchronized(@{ on = $true; want = [bool]$script:cfg.stats; q = $script:events })
$statsPs = [PowerShell]::Create()
[void]$statsPs.AddScript({
    param($st)
    $prev = $null; $netPrev = $null; $gpu = @{}; $tick = 0; $lhmNs = $null; $conn = $null; $bright = $null; $brightOK = $true; $icsUrlWas = $null; $gh = $null; $ghPrev = $null; $wxCity = $null; $wxGeo = $null; $updAt = [DateTime]::UtcNow.AddMinutes(-1439)
    $smi = $null; try { $smi = (Get-Command nvidia-smi.exe -ErrorAction Stop).Source } catch { }
    while ($st.on) {
        try {
            if (-not $st.want) { throw 'stats off' }
            $i = 0L; $k = 0L; $u = 0L
            if ([IslandNative]::GetSystemTimes([ref]$i, [ref]$k, [ref]$u)) {
                if ($prev) {
                    $tot = ($k - $prev[1]) + ($u - $prev[2])   # kernel time includes idle
                    if ($tot -gt 0) { $st.cpu = [int][math]::Max(0, [math]::Round(100 * (1 - ($i - $prev[0]) / $tot))) }
                }
                $prev = @($i, $k, $u)
            }
            $st.ram = [IslandNative]::MemoryLoad()
            $st.ramGB = [IslandNative]::MemoryGB()
        } catch { }
        try {
            $rx = 0L; $tx = 0L
            $wifi = $false; $eth = $false; $vpn = @()
            foreach ($n in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
                if ($n.OperationalStatus -ne 'Up' -or @('Loopback', 'Tunnel') -contains [string]$n.NetworkInterfaceType) { continue }
                $s = $n.GetIPStatistics(); $rx += $s.BytesReceived; $tx += $s.BytesSent
                $d = [string]$n.Description
                if ($d -match 'VPN|WireGuard|OpenVPN|TAP-Windows|Tailscale|ZeroTier|WARP|NordLynx|Wintun|AnyConnect|FortiClient|GlobalProtect' -or [string]$n.NetworkInterfaceType -eq 'Ppp') { $vpn += [string]$n.Name }
                elseif ([string]$n.NetworkInterfaceType -eq 'Wireless80211') { $wifi = $true }
                elseif ([string]$n.NetworkInterfaceType -match 'Ethernet' -and $d -notmatch 'Hyper-V|VirtualBox|VMware|vEthernet|Virtual|Bluetooth') { $eth = $true }
            }
            # connection changes, for the network popup
            $now = @{ wifi = $wifi; eth = $eth; vpn = ($vpn | Sort-Object) -join ', ' }
            if ($conn) {
                if ($wifi -ne $conn.wifi) {
                    $ssid = ''
                    if ($wifi) { try { $ssid = ((netsh wlan show interfaces) -match '^\s+SSID\s+:' | Select-Object -First 1) -replace '^\s+SSID\s+:\s*', '' } catch { } }
                    $st.q.Enqueue(@{ kind = 'net'; glyph = $(if ($wifi) { 0xE701 } else { 0xEB5E }); title = $(if ($wifi) { 'Wi-Fi connected' } else { 'Wi-Fi disconnected' }); sub = [string]$ssid; color = $(if ($wifi) { '#34C759' } else { '#FFB340' }) })
                }
                if ($eth -ne $conn.eth) {
                    $st.q.Enqueue(@{ kind = 'net'; glyph = 0xE839; title = $(if ($eth) { 'Ethernet connected' } else { 'Ethernet disconnected' }); sub = ''; color = $(if ($eth) { '#34C759' } else { '#FFB340' }) })
                }
                if ($now.vpn -ne $conn.vpn) {
                    $on = [bool]$now.vpn
                    $st.q.Enqueue(@{ kind = 'net'; glyph = 0xE705; title = $(if ($on) { 'VPN on' } else { 'VPN off' }); sub = $(if ($on) { $now.vpn } else { $conn.vpn }); color = $(if ($on) { '#8AB4FF' } else { '#8E8E93' }) })
                }
            }
            $conn = $now
            $t = [Environment]::TickCount
            if ($netPrev) {
                $dt = ($t - $netPrev[2]) / 1000.0
                if ($dt -gt 0) { $st.down = [math]::Max(0, ($rx - $netPrev[0]) / $dt); $st.up = [math]::Max(0, ($tx - $netPrev[1]) / $dt) }
            }
            $netPrev = @($rx, $tx, $t)
        } catch { }
        # calendar: fetch the iCal link every 5 minutes and keep the next day's events
        $url = [string]$st.icsUrl
        if ($url -and ($url -ne $icsUrlWas -or $tick % 150 -eq 0)) {
            $icsUrlWas = $url
            try {
                $wc = New-Object System.Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8
                $ics = $wc.DownloadString(($url -replace '^webcal://', 'https://'))
                $lines = ($ics -replace "`r?`n[ `t]", '') -split "`r?`n"   # unfold continued lines
                $list = @(); $ev = $null
                $nowUtc = [DateTime]::UtcNow
                foreach ($l in $lines) {
                    if ($l -eq 'BEGIN:VEVENT') { $ev = @{} }
                    elseif ($l -eq 'END:VEVENT' -and $ev) {
                        if ($ev.start -and $ev.start -gt $nowUtc -and $ev.start -lt $nowUtc.AddDays(1)) {
                            $list += @{ start = [DateTimeOffset]::new($ev.start).ToUnixTimeMilliseconds(); title = [string]$ev.title }
                        }
                        $ev = $null
                    } elseif ($ev -and $l -match '^SUMMARY[^:]*:(.*)$') { $ev.title = $Matches[1] -replace '\\,', ',' -replace '\\n', ' ' }
                    elseif ($ev -and $l -match '^DTSTART([^:]*):(\d{8}T\d{6})(Z?)$') {
                        $d = [DateTime]::ParseExact($Matches[2], 'yyyyMMddTHHmmss', [Globalization.CultureInfo]::InvariantCulture)
                        $ev.start = if ($Matches[3] -eq 'Z') { [DateTime]::SpecifyKind($d, 'Utc') } else { [DateTime]::SpecifyKind($d, 'Local').ToUniversalTime() }
                    }
                }
                $st.meetings = $list
            } catch { }
        } elseif (-not $url) { $st.meetings = @() }
        # updates: the latest release on GitHub, once a day (first look a minute after start) or when asked
        if (($st.updateCheck -and [DateTime]::UtcNow -gt $updAt.AddDays(1)) -or $st.checkNow) {
            $manual = [bool]$st.checkNow; $st.checkNow = $false; $updAt = [DateTime]::UtcNow
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $wc = New-Object System.Net.WebClient; $wc.Headers.Add('User-Agent', 'windows-notch'); $wc.Encoding = [Text.Encoding]::UTF8
                $rel = $wc.DownloadString("https://api.github.com/repos/$($st.updateRepo)/releases/latest") | ConvertFrom-Json
                $latest = ([string]$rel.tag_name).TrimStart('v', 'V')
                $asset = @($rel.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
                $url = if ($asset) { [string]$asset.browser_download_url } else { [string]$rel.zipball_url }
                if ([version]$latest -gt [version]$st.version) { $st.q.Enqueue(@{ kind = 'update'; version = $latest; url = $url; notes = [string]$rel.name }) }
                elseif ($manual) { $st.q.Enqueue(@{ kind = 'uptodate'; version = $st.version }) }
            } catch {
                if ($manual) { $st.q.Enqueue(@{ kind = 'updateerr'; text = 'No releases found (is the repo public?)' }) }
            }
        }
        # weather (Open-Meteo, free and keyless): look the city up once, then every 15 minutes
        $city = [string]$st.weatherCity
        if (-not $city) { $st.weather = $null }
        elseif ($city -ne $wxCity -or $tick % 450 -eq 7) {
            try {
                $wc = New-Object System.Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8
                if ($city -ne $wxCity -or -not $wxGeo) {
                    $g = ($wc.DownloadString('https://geocoding-api.open-meteo.com/v1/search?count=1&name=' + [Uri]::EscapeDataString($city)) | ConvertFrom-Json).results[0]
                    $wxGeo = if ($g) { @{ lat = [double]$g.latitude; lon = [double]$g.longitude; name = [string]$g.name } } else { $null }
                    $wxCity = $city
                }
                if ($wxGeo) {
                    $inv = [Globalization.CultureInfo]::InvariantCulture
                    $url = 'https://api.open-meteo.com/v1/forecast?current=temperature_2m,weather_code&latitude=' + $wxGeo.lat.ToString($inv) + '&longitude=' + $wxGeo.lon.ToString($inv)
                    $cur = ($wc.DownloadString($url) | ConvertFrom-Json).current
                    $st.weather = @{ temp = [int][math]::Round([double]$cur.temperature_2m); code = [int]$cur.weather_code; city = $wxGeo.name }
                } else { $st.weather = @{ temp = $null; code = -1; city = "$city (not found)" } }
            } catch { }
        }
        # GitHub: your open pull requests' checks and reviews, every 2 minutes (needs the gh CLI, signed in)
        if ($st.github -and $tick % 60 -eq 5) {
            if (-not $gh) { try { $gh = (Get-Command gh.exe -ErrorAction Stop).Source } catch { } }
            if ($gh) {
                try {
                    $query = 'query{viewer{pullRequests(states:OPEN,last:20){nodes{number title url repository{nameWithOwner} reviewDecision commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}}'
                    $res = (& $gh api graphql -f "query=$query" 2>$null) -join "`n" | ConvertFrom-Json
                    $cur = @{}
                    foreach ($pr in @($res.data.viewer.pullRequests.nodes)) {
                        $ci = [string]$pr.commits.nodes[0].commit.statusCheckRollup.state
                        $cur[[string]$pr.url] = @{ ci = $ci; review = [string]$pr.reviewDecision; name = "$($pr.repository.nameWithOwner)#$($pr.number) $($pr.title)" }
                    }
                    if ($ghPrev) {
                        foreach ($k in $cur.Keys) {
                            $a = $cur[$k]; $b = $ghPrev[$k]
                            if (-not $b) { continue }
                            $msg = $null
                            if ($a.ci -ne $b.ci -and $a.ci -eq 'SUCCESS') { $msg = @{ title = 'Checks passed'; ok = $true } }
                            elseif ($a.ci -ne $b.ci -and @('FAILURE', 'ERROR') -contains $a.ci) { $msg = @{ title = 'Checks failed'; ok = $false } }
                            elseif ($a.review -ne $b.review -and $a.review -eq 'APPROVED') { $msg = @{ title = 'PR approved'; ok = $true } }
                            elseif ($a.review -ne $b.review -and $a.review -eq 'CHANGES_REQUESTED') { $msg = @{ title = 'Changes requested'; ok = $false } }
                            if ($msg) {
                                $msg.kind = 'github'; $msg.text = $a.name; $msg.url = $k
                                $id = [guid]::NewGuid().ToString('N')
                                [IO.File]::WriteAllText((Join-Path $st.inbox "$id.json"), ($msg | ConvertTo-Json -Compress))
                            }
                        }
                    }
                    $ghPrev = $cur
                } catch { }
            }
        }
        # screen brightness (laptop screens; external monitors don't report it to Windows)
        if ($brightOK) {
            try {
                $b = [int](@(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop)[0].CurrentBrightness)
                if ($null -ne $bright -and $b -ne $bright) { $st.q.Enqueue(@{ kind = 'brightness'; value = $b }) }
                $bright = $b
            } catch { $brightOK = $false }
        }
        if (-not $st.want) { $tick++; Start-Sleep -Seconds 2; continue }   # the rest is only for the stats
        try {
            $cat = New-Object System.Diagnostics.PerformanceCounterCategory 'GPU Engine'
            $sum = 0.0; $seen = @{}
            foreach ($n in $cat.GetInstanceNames()) {
                if ($n -notlike '*engtype_3D') { continue }
                $seen[$n] = 1
                if ($gpu.ContainsKey($n)) { $sum += $gpu[$n].NextValue() }
                else { $gpu[$n] = New-Object System.Diagnostics.PerformanceCounter('GPU Engine', 'Utilization Percentage', $n, $true); [void]$gpu[$n].NextValue() }
            }
            foreach ($n in @($gpu.Keys)) { if (-not $seen.ContainsKey($n)) { $gpu[$n].Dispose(); $gpu.Remove($n) } }
            $st.gpu = [int][math]::Min(100, [math]::Round($sum))
        } catch { $st.gpu = $null }
        $lhmGpu = $null
        if ($lhmNs -or $tick % 15 -eq 0) {
            $sens = $null; $lhmNs = $null
            foreach ($ns in 'root/LibreHardwareMonitor', 'root/OpenHardwareMonitor') {
                try { $sens = @(Get-CimInstance -Namespace $ns -ClassName Sensor -Filter "SensorType='Temperature'" -ErrorAction Stop); $lhmNs = $ns; break } catch { }
            }
            $cpuT = $null
            if ($lhmNs) {
                $c = @($sens | Where-Object { $_.Identifier -match '/(amd|intel)cpu/' })
                $p = @($c | Where-Object { $_.Name -match '^(CPU Package|Core \(Tctl)' })
                $pick = if ($p.Count) { $p } else { $c }
                if ($pick.Count) { $cpuT = [int][math]::Round(($pick | ForEach-Object { [double]$_.Value } | Measure-Object -Maximum).Maximum) }
                $g = @($sens | Where-Object { $_.Identifier -match '/gpu' })
                $gc = @($g | Where-Object { $_.Name -eq 'GPU Core' })
                $pick = if ($gc.Count) { $gc } else { $g }
                if ($pick.Count) { $lhmGpu = [int][math]::Round(($pick | ForEach-Object { [double]$_.Value } | Measure-Object -Maximum).Maximum) }
            }
            $st.cpuTemp = $cpuT
        }
        if ($null -ne $lhmGpu) { $st.gpuTemp = $lhmGpu }
        elseif ($smi -and $tick % 3 -eq 0) {
            try {
                $o = & $smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
                $st.gpuTemp = if ("$o" -match '^\s*(\d+)') { [int]$Matches[1] } else { $null }
            } catch { $st.gpuTemp = $null }
        } elseif (-not $smi) { $st.gpuTemp = $null }
        $tick++
        Start-Sleep -Seconds 2
    }
}).AddArgument($script:stats)
$script:statsJob = $statsPs.BeginInvoke()
[void]$devPs.AddArgument($script:stats).AddArgument($script:events)
$script:devJob = $devPs.BeginInvoke()

$script:statKeys = ''; $script:statVals = @{}
function Format-Rate($b) {
    $b = [double]$b
    if ($b -ge 1MB) { $v = $b / 1MB; return $(if ($v -lt 10) { $v.ToString('0.0', $INV) } else { [math]::Round($v).ToString($INV) }) + 'M' }
    ([math]::Round($b / 1KB)).ToString($INV) + 'K'
}
function Stat-Value($key) {
    $st = $script:stats
    switch ($key) {
        'cpu' { $v = if ($null -ne $st.cpu) { '{0,3}%' -f $st.cpu } else { ' --' }; if ($null -ne $st.cpuTemp) { $v += (' {0,3}' -f $st.cpuTemp) + [char]0x00B0 }; $v }
        'gpu' { $v = if ($null -ne $st.gpu) { '{0,3}%' -f $st.gpu } else { ' --' }; if ($null -ne $st.gpuTemp) { $v += (' {0,3}' -f $st.gpuTemp) + [char]0x00B0 }; $v }
        'ram' { if ($null -ne $st.ram -and $st.ram -ge 0) { '{0,3}%' -f $st.ram } else { ' --' } }
        'net' { [string][char]0x2193 + (Format-Rate $st.down).PadLeft(5) + ' ' + [char]0x2191 + (Format-Rate $st.up).PadLeft(5) }
    }
}
function Render-Stats {
    $keys = @(([string]$script:cfg.statsItems).ToLower() -split '[,\s]+' | Where-Object { @('cpu', 'gpu', 'ram', 'net') -contains $_ })
    $sig = $keys -join ','
    if ($sig -ne $script:statKeys) {
        $script:statKeys = $sig; $uiStatsRow.Children.Clear(); $script:statVals = @{}
        foreach ($k in $keys) {
            $l = New-Object System.Windows.Controls.TextBlock
            $l.Text = $k.ToUpper(); $l.Foreground = New-Brush '#80FFFFFF'; $l.FontSize = 11; $l.FontWeight = 'SemiBold'
            $l.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI Variable Text, Segoe UI'
            $l.VerticalAlignment = 'Center'
            $l.Margin = New-Object System.Windows.Thickness($(if ($uiStatsRow.Children.Count) { 14 } else { 0 }), 0, 5, 0)
            $v = New-Object System.Windows.Controls.TextBlock
            $v.Foreground = New-Brush '#FFFFFFFF'; $v.FontSize = 12; $v.VerticalAlignment = 'Center'
            $v.FontFamily = New-Object System.Windows.Media.FontFamily 'Cascadia Mono, Consolas'
            [void]$uiStatsRow.Children.Add($l); [void]$uiStatsRow.Children.Add($v)
            $script:statVals[$k] = $v
        }
    }
    foreach ($k in $keys) { $script:statVals[$k].Text = Stat-Value $k }
}
function Show-Stats {
    $uiClaudeRow.Visibility = 'Collapsed'; $uiMusicRow.Visibility = 'Collapsed'; $uiStatsRow.Visibility = 'Visible'; $uiPopupRow.Visibility = 'Collapsed'
    Set-Look 'stats'
    $sleep = [double]$script:cfg.sleepAfterMinutes
    if ($sleep -gt 0 -and [IslandNative]::IdleMs() -gt $sleep * 60000) { Mascot-Mood 'sleepy' }
    elseif ($script:mood -eq 'sleepy') { Mascot-Mood 'normal' }
    Render-Stats
    Update-Panels 'stats' $null (Get-Now)
    $script:dismissKey = ''
    Set-View 'stats'
    Sync-Size
    $script:lastKey = 'stats'
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
        $script:stats.want = [bool]$script:cfg.stats; $script:stats.weatherCity = [string]$script:cfg.weatherCity
        $script:stats.updateCheck = [bool]$script:cfg.updateCheck; $script:stats.updateRepo = [string]$script:cfg.updateRepo; $script:stats.version = $script:Version
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

        Poll-Events $now
        $tv = Get-TimerView $now   # also notices when it runs out, whatever is showing
        $pop = Get-Popup $now

        $fs = Get-Fullscreen
        if ($fs) {
            Hide-Pill; $script:lastKey = ''
            if ($mode -eq 'needs') { Show-Notch $mode $pick $now $fs }
            elseif ($pop) { Show-PopupNotch $pop $fs }
            elseif ($pick) { Show-Notch $mode $pick $now $fs }
            elseif ($tv) { Set-NotchContent $tv.color "$($tv.title)  $($tv.value)" $tv.glyph; Show-NotchAt $fs }
            elseif ($script:cfg.fullscreenClock) { Set-NotchContent '#E6FFFFFF' ((Get-Date).ToShortTimeString()) ([char]0xE823); Show-NotchAt $fs }
            else { Hide-Notch }
            return
        }
        Hide-Notch

        # a notice takes over for a few seconds (but never over "needs you", or while expanded)
        if ($pop -and $mode -ne 'needs' -and -not $script:hover) { Show-PopupView $pop $now; return }
        if (-not $pick -and $tv) { Show-PopupView $tv $now; return }

        if (-not $pick) {
            $m = $script:music
            if ($m -and ($m.playing -or $script:hover -or ($script:pausedAt -and ($now - $script:pausedAt) -lt ([int]$script:cfg.musicPausedSeconds * 1000)))) {
                Show-Music $m $now
            } elseif ($script:cfg.stats) {
                Show-Stats
            } else {
                Hide-Pill; $script:lastKey = ''
            }
            return
        }

        $uiClaudeRow.Visibility = 'Visible'; $uiMusicRow.Visibility = 'Collapsed'; $uiStatsRow.Visibility = 'Collapsed'; $uiPopupRow.Visibility = 'Collapsed'
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

        Update-Panels 'claude' $sessions $now

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
    Animate $uiPeekHost $OpacityProp $to 150
}
# After hovering the see-through pill for a few seconds, a hint says how to use it
$script:hintMs = 0; $script:hintOn = $false
function Set-Hint([bool]$on) {
    if ($on -eq $script:hintOn) { return }
    $script:hintOn = $on
    if ($on) { $uiHint.Margin = New-Object System.Windows.Thickness(0, ($uiPill.ActualHeight + 8), 0, 0) }
    Animate $uiHint $OpacityProp $(if ($on) { 1 } else { 0 }) $(if ($on) { 200 } else { 150 })
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
        $through = [bool]$script:cfg.clickThrough -and -not $ctrl -and -not $script:sticky
        Set-PassThru $through
        if (-not $script:shown -or $uiPill.Opacity -lt 0.9) { $script:sticky = $false; Set-Peek $false; Set-Hint $false; $script:hintMs = 0; $script:hoverIn = 0; $script:hoverOut = 0; return }
        if ($through) {
            $over = Test-CursorOnPill 0
            Set-Peek $over
            if ($over) { $script:hintMs += 50; if ($script:hintMs -ge 3000) { Set-Hint $true } }
            else { $script:hintMs = 0; Set-Hint $false }
            $script:hoverIn = 0
            if ($script:hover) { $script:hover = $false; $script:hoverOut = 0; Update-Island }
            return
        }
        Set-Peek $false; Set-Hint $false; $script:hintMs = 0
        if ($script:hover) {
            if ((Test-CursorOnPill 10) -or $uiVolGrid.IsMouseCaptured -or (Get-Now) -lt $script:holdUntil) { $script:hoverOut = 0 }
            else {
                $script:hoverOut += 50
                # back to neutral: click-through resumes (see $script:sticky)
                if ($script:hoverOut -ge 250) { $script:hover = $false; $script:hoverOut = 0; $script:sticky = $false; Update-Island }
            }
        } else {
            if (Test-CursorOnPill 0) {
                $script:hoverIn += 50
                if ($script:hoverIn -ge 100) { $script:hover = $true; $script:hoverIn = 0; Update-Island }
            } else { $script:hoverIn = 0; $script:sticky = $false }
        }
    } catch { }
})

# One Ctrl+click is enough: the island then stays clickable until it collapses back
$script:sticky = $false
$uiPill.Add_PreviewMouseLeftButtonDown({ if ($script:cfg.clickThrough) { $script:sticky = $true } })

# Click the pill to dismiss "Task complete" / "Needs your input"; click the mascot to say hi
$uiPill.Add_MouseLeftButtonUp({
    $p = $script:popup
    if ($p -and $p.open) {   # e.g. a screenshot notice: open the file
        try {
            if ($p.open -eq '::update') { Start-Update }
            elseif ($p.open -is [array]) { Start-Process -FilePath ([string]$p.open[0]) -ArgumentList ([string]$p.open[1]) }
            else { Start-Process -FilePath ([string]$p.open) }
        } catch { Write-Log ("open: " + $_.Exception.Message) }
        $script:popup = $null; Update-Island; return
    }
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
[void]$menu.Items.Add((New-Toggle 'Compact notch in fullscreen' 'fullscreenNotch'))
[void]$menu.Items.Add((New-Toggle 'System stats when idle' 'stats'))
$miPopups = New-Object System.Windows.Forms.ToolStripMenuItem 'Popups'
foreach ($pair in @(@('Show popups', 'popups'), @('Devices', 'popupDevices'), @('Volume and brightness', 'popupVolume'),
                    @('Sound output', 'popupAudioOutput'), @('Caps Lock / Num Lock', 'popupLocks'), @('Battery and charger', 'popupBattery'),
                    @('Network and VPN', 'popupNetwork'), @('Screenshots', 'popupScreenshots'), @('Clock in fullscreen', 'fullscreenClock'))) {
    [void]$miPopups.DropDownItems.Add((New-Toggle $pair[0] $pair[1]))
}
$miPopups.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
foreach ($pair in @(@('Downloads', 'popupDownloads'), @('Clipboard', 'popupClipboard'), @('Do Not Disturb', 'popupFocus'), @('GitHub pull requests', 'popupGitHub'))) {
    [void]$miPopups.DropDownItems.Add((New-Toggle $pair[0] $pair[1]))
}
[void]$menu.Items.Add($miPopups)
$miTimer = New-Object System.Windows.Forms.ToolStripMenuItem 'Timer'
foreach ($m in 5, 10, 15, 30) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem "$m minutes"; $it.Tag = $m
    $it.Add_Click({ Start-Timer ([double]$this.Tag) "$($this.Tag) min timer" }); [void]$miTimer.DropDownItems.Add($it)
}
$itPomo = New-Object System.Windows.Forms.ToolStripMenuItem 'Pomodoro (focus, then a break)'
$itPomo.Add_Click({ Start-Timer ([double]$script:cfg.timerMinutes) 'Focus' 'focus' }); [void]$miTimer.DropDownItems.Add($itPomo)
$itStop = New-Object System.Windows.Forms.ToolStripMenuItem 'Stop timer'
$itStop.Add_Click({ Stop-Timer }); [void]$miTimer.DropDownItems.Add($itStop)
[void]$menu.Items.Add($miTimer)

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
    $open = New-Object System.Windows.Forms.ToolStripMenuItem 'Open custom images folder'
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

# Updates: check now, and install once one is found (the updater runs on its own and restarts the island)
$script:update = $null
function Start-Update {
    $u = $script:update
    if (-not $u) { return }
    $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $upd = Join-Path $PSScriptRoot 'update.ps1'
    Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$upd`" -Url `"$($u.url)`" -Version `"$($u.version)`"" -WindowStyle Hidden
    Show-Popup 'update' 0xE896 "Updating to v$($u.version)$ELL" 'The island restarts when it''s done' '#8AB4FF' 30
}
$miCheck = New-Object System.Windows.Forms.ToolStripMenuItem "Check for updates (v$script:Version)"
$miCheck.Add_Click({ $script:stats.checkNow = $true })
[void]$menu.Items.Add($miCheck)
$miUpdate = New-Object System.Windows.Forms.ToolStripMenuItem 'Install update'
$miUpdate.Visible = $false
$miUpdate.Add_Click({ Start-Update })
[void]$menu.Items.Add($miUpdate)

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
    $script:stats.on = $false
    $tray.Visible = $false; $tray.Dispose()
    $app.Shutdown()
})
[void]$menu.Items.Add($miQuit)
$tray.ContextMenuStrip = $menu
$tray.Add_DoubleClick({ Start-Test })

# After an update, say so once
$verFile = Join-Path $StateDir 'version'
$prevVer = try { ([IO.File]::ReadAllText($verFile)).Trim() } catch { '' }
if ($prevVer -and $prevVer -ne $script:Version) { Show-Popup 'update' 0xE73E "Updated to v$script:Version" '' '#34C759' 6 }
try { [IO.File]::WriteAllText($verFile, $script:Version) } catch { }

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
    # Cleanup can fail without stopping the relaunch, so the island never just disappears
    try { foreach ($t in $timer, $musicTimer, $blinkTimer, $watchTimer, $compTimer, $blurTimer, $hoverTimer) { if ($t -is [System.Windows.Threading.DispatcherTimer]) { $t.Stop() } } } catch { }
    try { $script:stats.on = $false; $tray.Visible = $false; $tray.Dispose() } catch { }
    try {
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
