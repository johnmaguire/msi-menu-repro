# Stand-in window harness for the Alt-release menu-mode priming experiments.
# Creates plain Win32 windows in this process, injects the input under test with
# SendInput (same method as TightVNC and the MSI harness), and logs every keyboard
# and menu message the window receives plus GetGUIThreadInfo after each step.
# Run it in the same interactive, unlocked, elevated session that repro.ps1 needs.
param(
    [string]$Steps = '',
    [string]$RunName = 'smoke',
    [ValidateSet('main','peer')][string]$Role = 'main',
    [switch]$Hook,
    [switch]$MsihndToggle,
    [string]$OutRoot = (Join-Path $PSScriptRoot 'standin-results')
)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $OutRoot $RunName
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$src = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class Standin
{
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public POINT pt; }
    [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO { public int cbSize; public uint flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }
    [StructLayout(LayoutKind.Sequential)] public struct KBDLLHOOKSTRUCT { public uint vkCode; public uint scanCode; public uint flags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct WNDCLASSEX { public int cbSize; public uint style; public IntPtr lpfnWndProc; public int cbClsExtra; public int cbWndExtra; public IntPtr hInstance; public IntPtr hIcon; public IntPtr hCursor; public IntPtr hbrBackground; public string lpszMenuName; public string lpszClassName; public IntPtr hIconSm; }

    public delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    public delegate IntPtr HookProcDelegate(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO gti);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern short GetKeyState(int vk);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern ushort RegisterClassEx(ref WNDCLASSEX wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr CreateWindowEx(uint exStyle, string cls, string title, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr DefWindowProc(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    public static bool IsWindowAlive(IntPtr h) { return IsWindow(h); }
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool UpdateWindow(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetMessage(out MSG msg, IntPtr h, uint min, uint max);
    [DllImport("user32.dll")] public static extern bool TranslateMessage(ref MSG msg);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr DispatchMessage(ref MSG msg);
    [DllImport("user32.dll")] public static extern bool PostThreadMessage(uint tid, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern void PostQuitMessage(int code);
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetWindowsHookEx(int id, HookProcDelegate proc, IntPtr mod, uint tid);
    [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr LoadCursor(IntPtr inst, int name);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr GetModuleHandle(string name);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    const uint WM_APP = 0x8000;
    const uint REQ_CREATE = WM_APP + 1, REQ_KEYSTATE = WM_APP + 2, REQ_QUIT = WM_APP + 3;

    static StreamWriter logw; static object lk = new object();
    static WndProcDelegate wndProcKeep; static HookProcDelegate hookKeep; static IntPtr hook = IntPtr.Zero;
    static Thread uiThread; static uint uiTid; static ManualResetEvent ready = new ManualResetEvent(false);
    static AutoResetEvent reqDone = new AutoResetEvent(false);
    static IntPtr reqResult; static bool reqSysMenu; static string reqTitle; static string reqKeyState;
    public static IntPtr Primary = IntPtr.Zero;
    public static string LastError = "";
    public static bool MsihndToggle = false; static int toggle = 0;

    public static void OpenLog(string path) { logw = new StreamWriter(path, true, new UTF8Encoding(false)); logw.AutoFlush = true; }
    public static void Log(string m) { lock (lk) { logw.WriteLine(DateTime.UtcNow.ToString("HH:mm:ss.ffffff") + " " + m); } }

    static string MsgName(uint m)
    {
        switch (m)
        {
            case 0x0100: return "WM_KEYDOWN"; case 0x0101: return "WM_KEYUP"; case 0x0104: return "WM_SYSKEYDOWN"; case 0x0105: return "WM_SYSKEYUP";
            case 0x0112: return "WM_SYSCOMMAND"; case 0x0211: return "WM_ENTERMENULOOP"; case 0x0212: return "WM_EXITMENULOOP";
            case 0x0116: return "WM_INITMENU"; case 0x0117: return "WM_INITMENUPOPUP"; case 0x011F: return "WM_MENUSELECT";
            case 0x0006: return "WM_ACTIVATE"; case 0x0007: return "WM_SETFOCUS"; case 0x0008: return "WM_KILLFOCUS"; case 0x001C: return "WM_ACTIVATEAPP";
            case 0x0102: return "WM_CHAR"; case 0x0106: return "WM_SYSCHAR"; case 0x0201: return "WM_LBUTTONDOWN"; case 0x0202: return "WM_LBUTTONUP";
            case 0x00A1: return "WM_NCLBUTTONDOWN"; case 0x0021: return "WM_MOUSEACTIVATE"; case 0x0286: return "WM_IME_CHAR"; case 0x0281: return "WM_IME_SETCONTEXT";
            case 0x0010: return "WM_CLOSE";
        }
        return null;
    }

    static uint OwnFlags()
    {
        var g = new GUITHREADINFO(); g.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        GetGUIThreadInfo(GetCurrentThreadId(), ref g); return g.flags;
    }

    static IntPtr WndProc(IntPtr h, uint m, IntPtr w, IntPtr l)
    {
        string n = MsgName(m);
        if (n != null)
        {
            Log(string.Format("WNDPROC hwnd=0x{0:X} {1} wParam=0x{2:X} lParam=0x{3:X8} flagsBefore=0x{4:X} ksMenu=0x{5:X4}", h.ToInt64(), n, w.ToInt64(), (uint)l.ToInt64(), OwnFlags(), (ushort)GetKeyState(0x12)));
        }
        if (m == 0x0010) { DestroyWindow(h); return IntPtr.Zero; }
        if (m == 0x0105 && w.ToInt64() == 0x12)
        {
            // msihnd CMsiControl::SysKeyUp: SendMessage(self, WM_SYSCOMMAND, SC_KEYMENU, 0) on every WM_SYSKEYUP VK_MENU,
            // optionally with its per-process odd/even toggle. Synchronous on this thread, like msihnd.
            bool send = true;
            if (MsihndToggle) { if (toggle != 0) { toggle = 0; send = false; } else { toggle = 1; } }
            Log(string.Format("MSIHND-EMU hwnd=0x{0:X} WM_SYSKEYUP VK_MENU -> SC_KEYMENU send={1} toggle={2}", h.ToInt64(), send, toggle));
            if (send)
            {
                SendMessage(h, 0x0112, (IntPtr)0xF100, IntPtr.Zero);
                Log(string.Format("MSIHND-EMU hwnd=0x{0:X} SC_KEYMENU returned flagsAfter=0x{1:X}", h.ToInt64(), OwnFlags()));
            }
        }
        IntPtr r = DefWindowProc(h, m, w, l);
        if (m == 0x0112 || m == 0x0105 || m == 0x0101)
        {
            Log(string.Format("WNDPROC hwnd=0x{0:X} {1} returned flagsAfter=0x{2:X}", h.ToInt64(), n, OwnFlags()));
        }
        return r;
    }

    static IntPtr HookProc(int code, IntPtr w, IntPtr l)
    {
        if (code >= 0)
        {
            var k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(l, typeof(KBDLLHOOKSTRUCT));
            Log(string.Format("LLHOOK msg=0x{0:X} vk=0x{1:X2} scan=0x{2:X2} flags=0x{3:X} injected={4} altdown={5}", w.ToInt64(), k.vkCode, k.scanCode, k.flags, (k.flags & 0x10) != 0, (k.flags & 0x20) != 0));
        }
        return CallNextHookEx(hook, code, w, l);
    }

    static IntPtr MakeWindow(bool sysMenu, string title)
    {
        uint style = sysMenu ? 0x00CF0000u : 0x80C00000u; // WS_OVERLAPPEDWINDOW : WS_POPUP|WS_CAPTION
        style |= 0x10000000u; // WS_VISIBLE
        IntPtr h = CreateWindowEx(0, "StandinWnd", title, style, 120, 120, 420, 300, IntPtr.Zero, IntPtr.Zero, GetModuleHandle(null), IntPtr.Zero);
        if (h == IntPtr.Zero) { Log("CreateWindowEx failed err=" + Marshal.GetLastWin32Error()); return h; }
        ShowWindow(h, 5); UpdateWindow(h);
        Log(string.Format("CREATED hwnd=0x{0:X} sysMenu={1} title='{2}' tid={3}", h.ToInt64(), sysMenu, title, GetCurrentThreadId()));
        return h;
    }

    static void UiMain(object arg)
    {
        bool withHook = (bool)arg;
        uiTid = GetCurrentThreadId();
        wndProcKeep = new WndProcDelegate(WndProc);
        var wc = new WNDCLASSEX(); wc.cbSize = Marshal.SizeOf(typeof(WNDCLASSEX));
        wc.lpfnWndProc = Marshal.GetFunctionPointerForDelegate(wndProcKeep);
        wc.hInstance = GetModuleHandle(null); wc.hCursor = LoadCursor(IntPtr.Zero, 32512); wc.hbrBackground = (IntPtr)6;
        wc.lpszClassName = "StandinWnd";
        if (RegisterClassEx(ref wc) == 0) { Log("RegisterClassEx failed err=" + Marshal.GetLastWin32Error()); ready.Set(); return; }
        if (withHook)
        {
            hookKeep = new HookProcDelegate(HookProc);
            hook = SetWindowsHookEx(13, hookKeep, GetModuleHandle(null), 0);
            Log(string.Format("LLHOOK installed={0} err={1}", hook != IntPtr.Zero, Marshal.GetLastWin32Error()));
        }
        Primary = MakeWindow(true, "Standin Main");
        ready.Set();
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
        {
            if (msg.hwnd == IntPtr.Zero && msg.message == REQ_CREATE) { reqResult = MakeWindow(reqSysMenu, reqTitle); reqDone.Set(); continue; }
            if (msg.hwnd == IntPtr.Zero && msg.message == REQ_KEYSTATE)
            {
                reqKeyState = string.Format("uiThread ksMenu=0x{0:X4} ksLMenu=0x{1:X4} ksRMenu=0x{2:X4} ksF10=0x{3:X4} ksEsc=0x{4:X4} flags=0x{5:X}", (ushort)GetKeyState(0x12), (ushort)GetKeyState(0xA4), (ushort)GetKeyState(0xA5), (ushort)GetKeyState(0x79), (ushort)GetKeyState(0x1B), OwnFlags());
                reqDone.Set(); continue;
            }
            if (msg.hwnd == IntPtr.Zero && msg.message == REQ_QUIT) { PostQuitMessage(0); continue; }
            TranslateMessage(ref msg); DispatchMessage(ref msg);
        }
        if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
        Log("ui loop exited");
    }

    public static bool StartUi(bool withHook)
    {
        uiThread = new Thread(UiMain); uiThread.IsBackground = true; uiThread.Start(withHook);
        return ready.WaitOne(5000) && Primary != IntPtr.Zero;
    }
    public static IntPtr CreateWin(bool sysMenu, string title)
    {
        reqSysMenu = sysMenu; reqTitle = title; reqResult = IntPtr.Zero;
        PostThreadMessage(uiTid, REQ_CREATE, IntPtr.Zero, IntPtr.Zero);
        if (!reqDone.WaitOne(3000)) { Log("CreateWin: ui thread did not answer"); return IntPtr.Zero; }
        return reqResult;
    }
    public static string UiKeyState()
    {
        reqKeyState = null;
        PostThreadMessage(uiTid, REQ_KEYSTATE, IntPtr.Zero, IntPtr.Zero);
        if (!reqDone.WaitOne(700)) return "uiThread no-answer (busy/modal)";
        return reqKeyState;
    }
    public static void StopUi() { PostThreadMessage(uiTid, REQ_QUIT, IntPtr.Zero, IntPtr.Zero); uiThread.Join(3000); }

    public static uint Key(ushort vk, bool up)
    {
        var i = new INPUT[1]; i[0].type = 1; i[0].u.ki.wVk = vk; i[0].u.ki.wScan = (ushort)MapVirtualKey(vk, 0); i[0].u.ki.dwFlags = up ? 2u : 0u;
        uint r = SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
        if (r == 0) LastError = Marshal.GetLastWin32Error().ToString(); else LastError = "";
        return r;
    }
    public static uint Click()
    {
        var i = new INPUT[2]; i[0].type = 0; i[0].u.mi.dwFlags = 2; i[1].type = 0; i[1].u.mi.dwFlags = 4;
        return SendInput(2, i, Marshal.SizeOf(typeof(INPUT)));
    }
    public static uint MouseDown() { var i = new INPUT[1]; i[0].type = 0; i[0].u.mi.dwFlags = 2; return SendInput(1, i, Marshal.SizeOf(typeof(INPUT))); }
    public static uint MouseUp() { var i = new INPUT[1]; i[0].type = 0; i[0].u.mi.dwFlags = 4; return SendInput(1, i, Marshal.SizeOf(typeof(INPUT))); }
    public static string Describe(IntPtr h)
    {
        var cls = new StringBuilder(256); var title = new StringBuilder(256); uint pid;
        GetClassName(h, cls, 256); GetWindowText(h, title, 256); uint tid = GetWindowThreadProcessId(h, out pid);
        return string.Format("hwnd=0x{0:X} pid={1} tid={2} class='{3}' title='{4}'", h.ToInt64(), pid, tid, cls, title);
    }
    public static uint Tid(IntPtr h) { uint pid; return GetWindowThreadProcessId(h, out pid); }
    public static uint Flags(IntPtr h)
    {
        uint pid; uint tid = GetWindowThreadProcessId(h, out pid);
        var g = new GUITHREADINFO(); g.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        GetGUIThreadInfo(tid, ref g); return g.flags;
    }
    public static string Sample(IntPtr h)
    {
        uint pid; uint tid = GetWindowThreadProcessId(h, out pid);
        var g = new GUITHREADINFO(); g.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        bool ok = GetGUIThreadInfo(tid, ref g);
        return string.Format("target=0x{0:X} tid={1} ok={2} flags=0x{3:X} menu={4} menuOwner=0x{5:X} active=0x{6:X} focus=0x{7:X} fg=0x{8:X} asyncMenu=0x{9:X4} asyncLMenu=0x{10:X4} asyncRMenu=0x{11:X4}",
            h.ToInt64(), tid, ok, g.flags, (g.flags & 0x4) != 0, g.hwndMenuOwner.ToInt64(), g.hwndActive.ToInt64(), g.hwndFocus.ToInt64(), GetForegroundWindow().ToInt64(),
            (ushort)GetAsyncKeyState(0x12), (ushort)GetAsyncKeyState(0xA4), (ushort)GetAsyncKeyState(0xA5));
    }
    public static string KeyBits()
    {
        var sb = new StringBuilder();
        foreach (int vk in new int[] { 0x12, 0xA4, 0xA5, 0x79 })
            sb.AppendFormat("vk{0:X2}:async=0x{1:X4},ks=0x{2:X4} ", vk, (ushort)GetAsyncKeyState(vk), (ushort)GetKeyState(vk));
        return sb.ToString();
    }
    public static bool CenterCursor(IntPtr h)
    {
        RECT r; if (!GetWindowRect(h, out r)) return false;
        return SetCursorPos((r.Left + r.Right) / 2, (r.Top + r.Bottom) / 2);
    }
}
'@
if (-not ('Standin' -as [type])) { Add-Type -TypeDefinition $src -Language CSharp }

$logPath = Join-Path $OutDir ("{0}.log" -f $Role)
[Standin]::OpenLog($logPath)
function Log([string]$m) { [Standin]::Log($m) }
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
Log ("START role={0} run={1} hook={2} user={3} session={4} pid={5} boot={6} steps='{7}'" -f $Role, $RunName, [bool]$Hook, $env:USERNAME, (Get-Process -Id $PID).SessionId, $PID, $boot, $Steps)

[Standin]::MsihndToggle = [bool]$MsihndToggle
if (-not [Standin]::StartUi([bool]$Hook)) { Log 'FATAL ui thread failed'; exit 2 }
$primary = [Standin]::Primary
Start-Sleep -Milliseconds 300

if ($Role -eq 'peer') {
    [void][Standin]::SetForegroundWindow($primary); Start-Sleep -Milliseconds 200
    Log ('PEER ' + [Standin]::Sample($primary))
    Set-Content -LiteralPath (Join-Path $OutDir 'peer.hwnd') -Value ('{0}' -f $primary.ToInt64())
    $stop = Join-Path $OutDir 'peer.stop'; $deadline = (Get-Date).AddSeconds(180)
    while (-not (Test-Path $stop) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    Log ('PEER end ' + [Standin]::Sample($primary))
    [Standin]::StopUi(); exit 0
}

$results = New-Object System.Collections.ArrayList
$target = $primary
$peerProc = $null; $charmap = $null

function Ensure-Foreground([IntPtr]$h) {
    $fg = [Standin]::GetForegroundWindow()
    $tries = 0
    while ($fg -ne $h -and $tries -lt 6) {
        [void][Standin]::SetForegroundWindow($h); Start-Sleep -Milliseconds 300
        $fg = [Standin]::GetForegroundWindow(); $tries++
    }
    $ok = ($fg -eq $h)
    Log ('FG ok={0} want=0x{1:X} have {2}' -f $ok, $h.ToInt64(), [Standin]::Describe($fg))
    return $ok
}
function Send-Key([int]$vk, [bool]$up) {
    $r = [Standin]::Key([uint16]$vk, $up)
    Log ('INJECT vk=0x{0:X2} scan=0x{1:X2} up={2} sent={3} err={4}' -f $vk, [Standin]::MapVirtualKey($vk, 0), $up, $r, [Standin]::LastError)
    return $r
}
function Tap([int]$vk, [int]$gapMs = 40) { [void](Send-Key $vk $false); Start-Sleep -Milliseconds $gapMs; [void](Send-Key $vk $true) }
function Wait-Window([string]$cls, [string]$title, [int]$sec = 10) {
    $deadline = (Get-Date).AddSeconds($sec)
    do { $h = [Standin]::FindWindow($cls, $title); if ($h -ne [IntPtr]::Zero) { return $h }; Start-Sleep -Milliseconds 150 } while ((Get-Date) -lt $deadline)
    return [IntPtr]::Zero
}
function Record([string]$step, [bool]$valid, [string]$note) {
    Start-Sleep -Milliseconds 60
    $flags = [Standin]::Flags($target)
    $s = [Standin]::Sample($target)
    $ks = if (($flags -band 4) -ne 0) { 'skipped (menu mode)' } elseif ([Standin]::Tid($target) -eq [Standin]::Tid($primary)) { [Standin]::UiKeyState() } else { 'n/a (foreign thread)' }
    Log ('RESULT step={0} valid={1} flagsAfter=0x{2:X} menu={3} note="{4}" | {5} | {6}' -f $step, $valid, $flags, (($flags -band 4) -ne 0), $note, $s, $ks)
    [void]$results.Add([ordered]@{ step = $step; valid = $valid; flagsAfter = ('0x{0:X}' -f $flags); menu = (($flags -band 4) -ne 0); note = $note; sample = $s; uiKeyState = $ks; target = ('0x{0:X}' -f $target.ToInt64()) })
}

Log ('INIT ' + [Standin]::Describe($primary) + ' msihndToggle=' + [bool]$MsihndToggle)
$fgok = Ensure-Foreground $primary
Record 'init' $fgok ''

$burst = 0x12,0xA4,0xA5,0x10,0xA0,0xA1,0x11,0xA2,0xA3,0x5B,0x5C,0x2E
foreach ($raw in ($Steps -split '[,\s]+' | Where-Object { $_ })) {
    $step = $raw.ToLowerInvariant()
    $uks = if (([Standin]::Flags($target) -band 4) -ne 0) { 'skipped (menu mode)' } else { [Standin]::UiKeyState() }
    Log ("STEP {0} | worker {1}| {2}" -f $step, [Standin]::KeyBits(), $uks)
    $note = ''
    if ($step -like 'sleep*') { $ms = [int]($step -replace 'sleep', ''); Start-Sleep -Milliseconds $ms; Record $step $true ''; continue }
    switch -Regex ($step) {
        '^(burst|altup|lalt3|alttap|f10tap|alttab|altclick|altletter|altf4|esc|click|enter)$' {
            $valid = Ensure-Foreground $target
            $before = [Standin]::Flags($target); $note = ('flagsBefore=0x{0:X}' -f $before)
            switch ($step) {
                'burst'  { foreach ($vk in $burst) { [void](Send-Key $vk $true) } }
                'altup'  { [void](Send-Key 0x12 $true) }
                'lalt3'  { foreach ($vk in 0x12,0xA4,0xA5) { [void](Send-Key $vk $true) } }
                'alttap' { Tap 0x12 }
                'f10tap' { Tap 0x79 }
                'alttab' {
                    # away and back, like the earlier manual trial
                    [void](Send-Key 0x12 $false); Start-Sleep -Milliseconds 40; Tap 0x09; Start-Sleep -Milliseconds 40; [void](Send-Key 0x12 $true)
                    Start-Sleep -Milliseconds 400; Log ('ALTTAB away: fg ' + [Standin]::Describe([Standin]::GetForegroundWindow()))
                    [void](Send-Key 0x12 $false); Start-Sleep -Milliseconds 40; Tap 0x09; Start-Sleep -Milliseconds 40; [void](Send-Key 0x12 $true)
                    Start-Sleep -Milliseconds 400; Log ('ALTTAB back: fg ' + [Standin]::Describe([Standin]::GetForegroundWindow()))
                    $valid = $valid -and ([Standin]::GetForegroundWindow() -eq $target)
                }
                'altclick' { [void][Standin]::CenterCursor($target); [void](Send-Key 0x12 $false); Start-Sleep -Milliseconds 40; [void][Standin]::Click(); Start-Sleep -Milliseconds 40; [void](Send-Key 0x12 $true) }
                'altletter' { [void](Send-Key 0x12 $false); Start-Sleep -Milliseconds 40; Tap 0x53; Start-Sleep -Milliseconds 40; [void](Send-Key 0x12 $true) }
                'altf4' {
                    # Alt+F4 on a throwaway second window of this process, then return to the current target
                    $tmp = [Standin]::CreateWin($true, 'Standin Throwaway'); Start-Sleep -Milliseconds 200
                    $valid = $valid -and (Ensure-Foreground $tmp)
                    [void](Send-Key 0x12 $false); Start-Sleep -Milliseconds 40; Tap 0x73; Start-Sleep -Milliseconds 40; [void](Send-Key 0x12 $true)
                    Start-Sleep -Milliseconds 400; Log ('ALTF4 throwaway alive={0} fg {1}' -f [Standin]::IsWindowAlive($tmp), [Standin]::Describe([Standin]::GetForegroundWindow()))
                    $valid = $valid -and (Ensure-Foreground $target)
                }
                'esc'    { Tap 0x1B 20 }
                'enter'  { Tap 0x0D 20 }
                'click'  { [void][Standin]::CenterCursor($target); Start-Sleep -Milliseconds 50; $r = [Standin]::Click(); Log ('INJECT click sent=' + $r) }
            }
            Record $step $valid $note
        }
        '^sckeymenu$' {
            $valid = Ensure-Foreground $target
            $r = [Standin]::PostMessage($target, 0x0112, [IntPtr]0xF100, [IntPtr]::Zero); Log ('POST WM_SYSCOMMAND SC_KEYMENU to 0x{0:X} ok={1}' -f $target.ToInt64(), $r)
            Record $step $valid 'posted SC_KEYMENU, no key input'
        }
        '^nosys$' {
            $target = [Standin]::CreateWin($false, 'Standin NoSysMenu'); Start-Sleep -Milliseconds 200
            $valid = ($target -ne [IntPtr]::Zero) -and (Ensure-Foreground $target)
            Record $step $valid ('created ' + [Standin]::Describe($target))
        }
        '^win2$' {
            $target = [Standin]::CreateWin($true, 'Standin Second'); Start-Sleep -Milliseconds 200
            $valid = ($target -ne [IntPtr]::Zero) -and (Ensure-Foreground $target)
            Record $step $valid ('created ' + [Standin]::Describe($target))
        }
        '^main$' { $target = $primary; $valid = Ensure-Foreground $target; Record $step $valid '' }
        '^peer$' {
            Remove-Item -LiteralPath (Join-Path $OutDir 'peer.hwnd'), (Join-Path $OutDir 'peer.stop') -Force -ErrorAction SilentlyContinue
            $peerProc = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Role peer -RunName "{1}" -OutRoot "{2}"' -f $PSCommandPath, $RunName, $OutRoot) -PassThru
            $deadline = (Get-Date).AddSeconds(20); $ph = [IntPtr]::Zero
            while ((Get-Date) -lt $deadline) { $f = Join-Path $OutDir 'peer.hwnd'; if (Test-Path $f) { $ph = [IntPtr]([int64](Get-Content $f)); break }; Start-Sleep -Milliseconds 150 }
            $target = $ph; Start-Sleep -Milliseconds 200
            $valid = ($ph -ne [IntPtr]::Zero) -and (Ensure-Foreground $target)
            Record $step $valid ('peer pid={0} {1}' -f $peerProc.Id, [Standin]::Describe($target))
        }
        '^charmap$' {
            $charmap = Start-Process -FilePath 'C:\Windows\System32\charmap.exe' -PassThru
            $h = Wait-Window '#32770' 'Character Map' 10; Start-Sleep -Milliseconds 300
            $target = $h
            $valid = ($h -ne [IntPtr]::Zero) -and (Ensure-Foreground $target)
            Record $step $valid ('charmap ' + [Standin]::Describe($target))
        }
        default { Log ("UNKNOWN step {0}" -f $step); Record $step $false 'unknown step' }
    }
}

Log ('END ' + [Standin]::Sample($primary))
if ($peerProc) { Set-Content -LiteralPath (Join-Path $OutDir 'peer.stop') -Value 'stop'; Start-Sleep -Milliseconds 500 }
if ($charmap) { Stop-Process -Id $charmap.Id -Force -ErrorAction SilentlyContinue }
[Standin]::StopUi()
$summary = [ordered]@{ run = $RunName; role = $Role; hook = [bool]$Hook; boot = $boot; user = $env:USERNAME; session = (Get-Process -Id $PID).SessionId; steps = $Steps; results = $results }
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
Log 'DONE'
