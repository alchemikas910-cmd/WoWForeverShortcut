# Starts WoW Forever without showing the Battle.net window: starts the launcher in the tray when it
# is closed, asks it to launch the game (product code WoWF) until the game runs, and hides the
# launcher's main window while it does (the launch command brings it up).
# Not hidden: any other window of the launcher (sign-in, errors). When the game has not started in
# 30 s (signed out, an update, an error) the launcher is shown again and left alone.
# Sign-in: when login.dat exists (written by the installer, encrypted for this Windows user) and the
# launcher's sign-in window shows up, the login and password are typed into it once - only while
# that window is the active one. The log never holds either of them.
$ErrorActionPreference = 'SilentlyContinue'
$here = $PSScriptRoot
$log = Join-Path $here 'launch.log'
function Write-Log($t) { Add-Content -Encoding UTF8 -Path $log -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $t) }

# one at a time: a second click stops the run still going and starts over. The mutex makes two
# runs started at the same moment take turns (the later one stops the earlier).
$pidFile = Join-Path $here 'launch.pid'
$mutex = New-Object Threading.Mutex($false, 'Local\WoWForeverLaunch')
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) {
    if (Test-Path $pidFile) {
        $old = [int]((Get-Content -Raw $pidFile).Trim())
        if ($old -and $old -ne $PID) {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $old"
            if ($proc -and $proc.CommandLine -like '*launch.ps1*') { Stop-Process -Id $old -Force }
        }
    }
    try { $owned = $mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { exit }
}
Set-Content -Path $pidFile -Value $PID
Set-Content -Encoding UTF8 -Path $log -Value ''

$bnet = $null
$cfgFile = Join-Path $here 'config.txt'
if (Test-Path $cfgFile) { $bnet = (Get-Content -Raw $cfgFile).Trim() }
if (-not $bnet -or -not (Test-Path $bnet)) { $bnet = 'C:\Program Files (x86)\Battle.net\Battle.net.exe' }
if (-not (Test-Path $bnet)) { Write-Log "Battle.net.exe not found: $bnet"; exit }

Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class BnetWin {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    public static List<IntPtr> Hidden = new List<IntPtr>();
    public static List<string> Seen = new List<string>();
    public static IntPtr Login = IntPtr.Zero;
    public static string Title(IntPtr h) { var s = new StringBuilder(256); GetWindowText(h, s, 256); return s.ToString(); }
    // hides the launcher's main window (title exactly "Battle.net"); notes every other title seen,
    // and the sign-in window when one shows (a title that speaks of signing in)
    public static int HideMain(uint[] pids, bool hide) {
        int n = 0;
        Login = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (Array.IndexOf(pids, pid) < 0 || !IsWindowVisible(h)) return true;
            string t = Title(h);
            if (t.Length == 0) return true;
            if (!Seen.Contains(t)) Seen.Add(t);
            if (t == "Battle.net") {
                if (hide) { ShowWindow(h, 0); n++; if (!Hidden.Contains(h)) Hidden.Add(h); }
            } else {
                string low = t.ToLowerInvariant();
                if (low.Contains("login") || low.Contains("log in") || low.Contains("sign in") || low.Contains("вход") || low.Contains("войти")) Login = h;
            }
            return true;
        }, IntPtr.Zero);
        return n;
    }
    public static void ShowHidden() { foreach (IntPtr h in Hidden) ShowWindow(h, 5); Hidden.Clear(); }
    public static bool IsActive(IntPtr h) { return h != IntPtr.Zero && GetForegroundWindow() == h; }

    // keyboard input through SendInput: text as Unicode characters (whatever the keyboard layout -
    // a Russian layout would turn Latin letters into Cyrillic ones), keys by their virtual codes
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTUNION u; }
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    const uint KEYUP = 0x0002, UNICODE = 0x0004;
    static INPUT Key(ushort vk, ushort scan, uint flags) {
        var i = new INPUT(); i.type = 1; i.u.ki.wVk = vk; i.u.ki.wScan = scan; i.u.ki.dwFlags = flags; return i;
    }
    static uint Send(INPUT[] keys) { return SendInput((uint)keys.Length, keys, Marshal.SizeOf(typeof(INPUT))); }
    // returns how many key events went through (0: Windows refused them)
    public static uint TypeText(string text) {
        uint sent = 0;
        foreach (char c in text) {
            sent += Send(new INPUT[] { Key(0, c, UNICODE), Key(0, c, UNICODE | KEYUP) });
            System.Threading.Thread.Sleep(15);
        }
        return sent;
    }
    public static uint Press(ushort vk) { return Send(new INPUT[] { Key(vk, 0, 0), Key(vk, 0, KEYUP) }); }
    // The page area of a Chromium window (Battle.net is one): Chromium shows the page's fields to
    // accessibility only once something has asked that area for its accessible object
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    public static List<IntPtr> PageAreas(IntPtr top) {
        var found = new List<IntPtr>();
        EnumChildWindows(top, (h, l) => {
            var s = new StringBuilder(128); GetClassName(h, s, 128);
            if (s.ToString().StartsWith("Chrome_RenderWidgetHostHWND")) found.Add(h);
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static void Wake(IntPtr area) {
        Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71"); object o;
        try { AccessibleObjectFromWindow(area, 0xFFFFFFFC, ref iid, out o); } catch { }
    }

    // a left click at a screen point; the mouse goes back where it was
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    public static uint Click(int x, int y) {
        POINT was; GetCursorPos(out was);
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(30);
        var down = new INPUT(); down.type = 0; down.u.mi.dwFlags = 0x0002;
        var up = new INPUT(); up.type = 0; up.u.mi.dwFlags = 0x0004;
        uint n = Send(new INPUT[] { down, up });
        System.Threading.Thread.Sleep(30);
        SetCursorPos(was.X, was.Y);
        return n;
    }
    public static uint CtrlA() { return Send(new INPUT[] { Key(0x11, 0, 0), Key(0x41, 0, 0), Key(0x41, 0, KEYUP), Key(0x11, 0, KEYUP) }); }
}
'@

function Get-BnetPids { [uint32[]]@(Get-Process -Name 'Battle.net' | ForEach-Object { $_.Id }) }
function Test-Wow { [bool](Get-Process -Name 'Wow') }
function Ask {
    Start-Process $bnet '--exec="launch WoWF"'
    Write-Log 'launch asked'
}

# the saved sign-in, if any
$cred = $null
$credFile = Join-Path $here 'login.dat'
if (Test-Path $credFile) {
    try {
        $lines = Get-Content $credFile
        $u = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR(($lines[0] | ConvertTo-SecureString)))
        $p = $lines[1] | ConvertTo-SecureString
        if ($u -and $p) { $cred = @{ User = $u; Pass = $p } }
        Write-Log 'saved sign-in: yes'
    } catch { Write-Log 'saved sign-in: cannot be read (made under another Windows user?)' }
} else { Write-Log 'saved sign-in: none' }
$typed = $false

# The sign-in window as a picture: the launcher's page shows nothing to accessibility, so its step
# is told by where its big blue button is. Measured on the launcher's sign-in window:
#   e-mail step:   field 0.35-0.41 of the height, "Continue" from 0.51
#   password step: field 0.39-0.44, "Log in" from 0.54, a blue eye at the field's right end
# The field is always about 0.128 of the height above the button's top.
Add-Type -ReferencedAssemblies System.Drawing @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class BnetShot {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    public static int X, Y, W, H;
    static bool Blue(Color c) { return c.B > 170 && c.R < 90 && c.G > 70 && c.G < 180; }
    // the top of the big blue button as a share of the window's height (-1: none); eye: a blue mark
    // at the field's right end
    public static double ButtonTop(IntPtr h, out bool eye) {
        eye = false;
        RECT r; if (!GetWindowRect(h, out r)) return -1;
        X = r.L; Y = r.T; W = r.R - r.L; H = r.B - r.T;
        if (W < 100 || H < 200) return -1;
        using (var bmp = new Bitmap(W, H)) {
            using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(X, Y, 0, 0, bmp.Size);
            int x1 = (int)(W * 0.70), x2 = (int)(W * 0.80);
            int run = 0, need = Math.Max(6, (int)(H * 0.03));
            for (int y = (int)(H * 0.30); y < (int)(H * 0.75); y++) {
                // a row of the button: blue across the right part (the links are thin text)
                bool all = true;
                for (int x = x1; x <= x2; x += 4) if (!Blue(bmp.GetPixel(x, y))) { all = false; break; }
                if (all) {
                    run++;
                    if (run >= need) {
                        int top = y - run + 1;
                        double t = (double)top / H;
                        // the eye of the password field: blue pixels near the right end of the field
                        int fy = top - (int)(H * 0.128);
                        for (int ex = (int)(W * 0.80); ex < (int)(W * 0.94) && !eye; ex++)
                            for (int ey = fy - (int)(H * 0.012); ey <= fy + (int)(H * 0.012) && !eye; ey++)
                                if (ey > 0 && Blue(bmp.GetPixel(ex, ey))) eye = true;
                        return t;
                    }
                } else run = 0;
            }
        }
        return -1;
    }
}
'@
[void][BnetShot]::SetProcessDPIAware()
function Type-Login {
    $h = [BnetWin]::Login
    if (-not $cred -or $script:typed -or $h -eq [IntPtr]::Zero) { return }
    $script:typed = $true
    Write-Log ('sign-in window: "' + [BnetWin]::Title($h) + '"')
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Pass)
    try {
        $pass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        # every key only while the sign-in window is the active one: never into another window.
        # Logged: the step and whether Windows took it - never what was typed, nor how long it was
        function Step($name, $action) {
            if (-not [BnetWin]::IsActive($h)) { Write-Log ('stopped before ' + $name + ': the sign-in window is not active'); return $false }
            $n = & $action
            Write-Log ($name + ' ' + $(if ($n -gt 0) { 'ok' } else { 'refused' }))
            Start-Sleep -Milliseconds 300
            return $true
        }
        function Fill($top, $name, $text) {
            $x = [BnetShot]::X + [int]([BnetShot]::W * 0.5)
            $y = [BnetShot]::Y + [int]([BnetShot]::H * ($top - 0.128))
            if (-not (Step ($name + ': click') { [BnetWin]::Click($x, $y) })) { return $false }
            if (-not (Step ($name + ': select') { [BnetWin]::CtrlA() })) { return $false }
            if (-not (Step ($name + ': type') { [BnetWin]::TypeText($text) })) { return $false }
            # Enter in the field presses the page's button ("Continue" / "Log in")
            if (-not (Step ($name + ': enter') { [BnetWin]::Press(0x0D) })) { return $false }
            return $true
        }
        # up to 40 s: the page loads, then its steps; the e-mail once, the password once
        $emailDone = $false
        $until = (Get-Date).AddSeconds(40)
        $seen = ''
        while ((Get-Date) -lt $until) {
            if (-not [BnetWin]::IsWindowVisible($h)) { Write-Log 'sign-in window closed'; return }
            [void][BnetWin]::SetForegroundWindow($h)
            Start-Sleep -Milliseconds 300
            $eye = $false
            $top = [BnetShot]::ButtonTop($h, [ref]$eye)
            $kind = if ($top -lt 0) { 'loading' } elseif ($eye -or $top -ge 0.526) { 'password' } else { 'e-mail' }
            $now = 'page: ' + $kind + $(if ($top -ge 0) { ' (button at {0:0.00})' -f $top } else { '' })
            if ($now -ne $seen) { Write-Log $now; $seen = $now }
            if ($kind -eq 'password') {
                if (Fill $top 'password' $pass) { Write-Log 'sign-in sent' }
                return
            }
            if ($kind -eq 'e-mail' -and -not $emailDone) {
                $emailDone = $true
                if (-not (Fill $top 'e-mail' $cred.User)) { return }
                Start-Sleep -Milliseconds 1500   # the next step of the page comes up
            }
            Start-Sleep -Milliseconds 500
        }
        Write-Log 'sign-in: no password step in 40 s - left to the player'
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        $pass = $null
    }
}

if (Test-Wow) { Write-Log 'game already running'; exit }

if (-not (Get-Process -Name 'Battle.net')) {
    Write-Log 'launcher closed: starting it as on autostart'
    Start-Process $bnet '--autostarted'
}

# 1. quiet: ask every 5 s, hide the main window, for up to 30 s (a sign-in gives 60 s more)
$sent = [datetime]::MinValue
$until = (Get-Date).AddSeconds(30)
$hidden = 0
while ((Get-Date) -lt $until -and -not (Test-Wow)) {
    if (((Get-Date) - $sent).TotalSeconds -ge 5 -and (Get-Process -Name 'Battle.net')) { Ask; $sent = Get-Date }
    $hidden += [BnetWin]::HideMain((Get-BnetPids), $true)
    if ([BnetWin]::Login -ne [IntPtr]::Zero -and $cred -and -not $typed) {
        Type-Login
        $until = (Get-Date).AddSeconds(60)
    }
    Start-Sleep -Milliseconds 100
}

# 2. no game yet: signed out, an update or an error - the launcher is shown and left to the player;
#    the game is still asked for now and then, for up to 10 minutes
if (-not (Test-Wow)) {
    [BnetWin]::ShowHidden()
    Write-Log ('no game yet: launcher shown. Windows seen: ' + ([BnetWin]::Seen -join ' | '))
    $until = (Get-Date).AddMinutes(10)
    while ((Get-Date) -lt $until -and -not (Test-Wow)) {
        if (((Get-Date) - $sent).TotalSeconds -ge 15 -and (Get-Process -Name 'Battle.net')) { Ask; $sent = Get-Date }
        # a sign-in window that came late still gets the saved login (once)
        [void][BnetWin]::HideMain((Get-BnetPids), $false)
        if ([BnetWin]::Login -ne [IntPtr]::Zero -and $cred -and -not $typed) { Type-Login }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-Wow)) { Write-Log 'game did not start in 10 minutes'; exit }
}
Write-Log 'game started'

# 3. the launcher may bring its main window up again while the game starts
$until = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $until) {
    $hidden += [BnetWin]::HideMain((Get-BnetPids), $true)
    Start-Sleep -Milliseconds 200
}
Write-Log ("launcher main window hidden: $hidden. Windows seen: " + ([BnetWin]::Seen -join ' | '))
