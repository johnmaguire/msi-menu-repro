using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace MsiMenuRepro
{
    public sealed class WindowSnapshot
    {
        public bool Valid { get; internal set; }
        public string Error { get; internal set; }
        public uint Pid { get; internal set; }
        public uint Tid { get; internal set; }
        public string ClassName { get; internal set; }
        public IntPtr Foreground { get; internal set; }
        public bool IsForeground { get; internal set; }
        public uint Flags { get; internal set; }
        public IntPtr MenuOwner { get; internal set; }
        public IntPtr Focus { get; internal set; }
    }

    public sealed class InputEventResult
    {
        public ushort VirtualKey { get; internal set; }
        public uint Flags { get; internal set; }
        public uint Injected { get; internal set; }
        public int LastError { get; internal set; }
    }

    public sealed class InputResult
    {
        internal readonly List<uint> Calls = new List<uint>();

        public bool Success { get; internal set; }
        public uint Attempted { get; internal set; }
        public uint Injected { get; internal set; }
        public int LastError { get; internal set; }
        public string Error { get; internal set; }
        public IntPtr ForegroundBefore { get; internal set; }
        public IntPtr ForegroundAfter { get; internal set; }
        public InputEventResult[] Events { get; internal set; }
        public uint[] Counts { get { return Calls.ToArray(); } }
    }

    public sealed class KeyState
    {
        public string Name { get; internal set; }
        public ushort VirtualKey { get; internal set; }
        public bool Down { get; internal set; }
        public bool Toggle { get; internal set; }
    }

    public sealed class KeyboardSnapshot
    {
        public uint ForegroundThreadId { get; internal set; }
        public string KeyboardLayout { get; internal set; }
        public KeyState[] Keys { get; internal set; }
    }

    public static class Native
    {
        public const uint GUI_INMENUMODE = 0x00000004;
        public const uint GUI_SYSTEMMENUMODE = 0x00000008;
        public const uint GUI_POPUPMENUMODE = 0x00000010;

        private const uint INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private static readonly ushort[] ModifierKeys =
        {
            0x12, 0xA4, 0xA5, 0x10, 0xA0, 0xA1,
            0x11, 0xA2, 0xA3, 0x5B, 0x5C, 0x2E
        };
        private static readonly string[] ModifierNames =
        {
            "Alt", "LeftAlt", "RightAlt", "Shift", "LeftShift", "RightShift",
            "Control", "LeftControl", "RightControl", "LeftWindows", "RightWindows", "Delete"
        };

        public static IntPtr FindDialog(uint pid, string className)
        {
            if (pid == 0)
                throw new ArgumentOutOfRangeException("pid");
            if (String.IsNullOrEmpty(className))
                throw new ArgumentException("A window class name is required.", "className");

            IntPtr found = IntPtr.Zero;
            EnumWindows(delegate(IntPtr window, IntPtr parameter)
            {
                uint owner;
                GetWindowThreadProcessId(window, out owner);
                if (owner == pid && IsWindowVisible(window) && String.Equals(ReadClassName(window), className, StringComparison.Ordinal))
                {
                    found = window;
                    return false;
                }
                return true;
            }, IntPtr.Zero);
            return found;
        }

        public static bool IsWindow(IntPtr window)
        {
            return window != IntPtr.Zero && NativeIsWindow(window);
        }

        public static WindowSnapshot Snapshot(IntPtr window)
        {
            WindowSnapshot result = new WindowSnapshot();
            result.Foreground = GetForegroundWindow();
            result.IsForeground = window != IntPtr.Zero && result.Foreground == window;
            if (!IsWindow(window))
            {
                result.Error = "The target window no longer exists.";
                return result;
            }

            uint owner;
            result.Tid = GetWindowThreadProcessId(window, out owner);
            result.Pid = owner;
            result.ClassName = ReadClassName(window);
            if (result.Tid == 0)
            {
                result.Error = "The target window has no thread.";
                return result;
            }

            GUITHREADINFO info = new GUITHREADINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(GUITHREADINFO));
            if (!GetGUIThreadInfo(result.Tid, ref info))
            {
                result.Error = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                return result;
            }

            result.Flags = info.flags;
            result.MenuOwner = info.hwndMenuOwner;
            result.Focus = info.hwndFocus;
            result.Valid = true;
            return result;
        }

        public static bool TryForeground(IntPtr window)
        {
            if (!IsWindow(window))
                return false;
            if (GetForegroundWindow() == window)
                return true;
            SetForegroundWindow(window);
            return GetForegroundWindow() == window;
        }

        public static KeyboardSnapshot KeyboardState()
        {
            IntPtr foreground = GetForegroundWindow();
            uint owner;
            uint thread = GetWindowThreadProcessId(foreground, out owner);
            List<KeyState> keys = new List<KeyState>();
            for (int i = 0; i < ModifierKeys.Length; i++)
            {
                ushort key = ModifierKeys[i];
                keys.Add(new KeyState
                {
                    Name = ModifierNames[i],
                    VirtualKey = key,
                    Down = (GetAsyncKeyState(key) & 0x8000) != 0,
                    Toggle = (GetKeyState(key) & 0x0001) != 0
                });
            }
            return new KeyboardSnapshot
            {
                ForegroundThreadId = thread,
                KeyboardLayout = "0x" + GetKeyboardLayout(thread).ToInt64().ToString("X16"),
                Keys = keys.ToArray()
            };
        }

        public static InputResult ResetModifiers(IntPtr expectedForeground)
        {
            InputResult result = BeginInput(expectedForeground);
            if (result.Error != null)
                return result;

            List<InputEventResult> events = new List<InputEventResult>();
            for (int i = 0; i < ModifierKeys.Length; i++)
            {
                if (!StillForeground(expectedForeground, result))
                    break;
                if (!SendOne(ModifierKeys[i], KEYEVENTF_KEYUP, result, events))
                    break;
            }
            return FinishInput(expectedForeground, result, events);
        }

        public static InputResult AltTap(IntPtr expectedForeground)
        {
            InputResult result = BeginInput(expectedForeground);
            if (result.Error != null)
                return result;

            List<InputEventResult> events = new List<InputEventResult>();
            if (SendOne(0x12, 0, result, events))
            {
                Thread.Sleep(40);
                // Release our keydown even if focus changes so Alt is not left pressed.
                StillForeground(expectedForeground, result);
                SendOne(0x12, KEYEVENTF_KEYUP, result, events);
            }
            return FinishInput(expectedForeground, result, events);
        }

        public static InputResult PressKey(IntPtr expectedForeground, ushort virtualKey)
        {
            InputResult result = BeginInput(expectedForeground);
            if (result.Error != null)
                return result;

            INPUT[] inputs = { MakeKey(virtualKey, 0), MakeKey(virtualKey, KEYEVENTF_KEYUP) };
            SetLastError(0);
            uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
            int error = Marshal.GetLastWin32Error();
            result.Calls.Add(sent);
            result.Attempted = (uint)inputs.Length;
            result.Injected = sent;
            List<InputEventResult> events = new List<InputEventResult>();
            events.Add(new InputEventResult { VirtualKey = virtualKey, Flags = 0, Injected = sent > 0 ? 1u : 0u, LastError = sent == 2 ? 0 : error });
            events.Add(new InputEventResult { VirtualKey = virtualKey, Flags = KEYEVENTF_KEYUP, Injected = sent > 1 ? 1u : 0u, LastError = sent == 2 ? 0 : error });
            if (sent != inputs.Length)
            {
                result.LastError = error;
                result.Error = InputError(error);
                // A partial batch must not leave a successfully injected keydown pressed.
                if (sent == 1)
                    SendOne(virtualKey, KEYEVENTF_KEYUP, result, events);
            }
            return FinishInput(expectedForeground, result, events);
        }

        private static InputResult BeginInput(IntPtr expectedForeground)
        {
            InputResult result = new InputResult();
            result.ForegroundBefore = GetForegroundWindow();
            result.ForegroundAfter = result.ForegroundBefore;
            result.Events = new InputEventResult[0];
            if (!IsWindow(expectedForeground))
                result.Error = "Input refused: the expected window does not exist.";
            else if (result.ForegroundBefore != expectedForeground)
                result.Error = "Input refused: the expected window is not foreground.";
            return result;
        }

        private static bool StillForeground(IntPtr expectedForeground, InputResult result)
        {
            if (GetForegroundWindow() == expectedForeground && IsWindow(expectedForeground))
                return true;
            if (result.Error == null)
                result.Error = "The foreground window changed during input injection.";
            return false;
        }

        private static InputResult FinishInput(IntPtr expectedForeground, InputResult result, List<InputEventResult> events)
        {
            StillForeground(expectedForeground, result);
            result.ForegroundAfter = GetForegroundWindow();
            result.Events = events.ToArray();
            result.Success = result.Error == null && result.Attempted > 0 && result.Attempted == result.Injected;
            return result;
        }

        private static bool SendOne(ushort virtualKey, uint flags, InputResult result, List<InputEventResult> events)
        {
            INPUT[] inputs = { MakeKey(virtualKey, flags) };
            SetLastError(0);
            uint sent = SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
            int error = Marshal.GetLastWin32Error();
            result.Calls.Add(sent);
            result.Attempted++;
            result.Injected += sent;
            events.Add(new InputEventResult
            {
                VirtualKey = virtualKey,
                Flags = flags,
                Injected = sent,
                LastError = sent == 1 ? 0 : error
            });
            if (sent == 1)
                return true;

            result.LastError = error;
            if (result.Error == null)
                result.Error = InputError(error);
            return false;
        }

        private static string InputError(int error)
        {
            if (error == 0)
                return "SendInput did not insert every event; Windows returned no error code. Integrity restrictions can cause this.";
            return "SendInput failed: " + new Win32Exception(error).Message + " (" + error + ").";
        }

        private static INPUT MakeKey(ushort virtualKey, uint flags)
        {
            INPUT input = new INPUT();
            input.type = INPUT_KEYBOARD;
            input.data.keyboard.wVk = virtualKey;
            input.data.keyboard.wScan = (ushort)MapVirtualKey(virtualKey, 0);
            input.data.keyboard.dwFlags = flags;
            return input;
        }

        private static string ReadClassName(IntPtr window)
        {
            StringBuilder name = new StringBuilder(256);
            return GetClassName(window, name, name.Capacity) > 0 ? name.ToString() : String.Empty;
        }

        private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public INPUTUNION data;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct INPUTUNION
        {
            [FieldOffset(0)] public MOUSEINPUT mouse;
            [FieldOffset(0)] public KEYBDINPUT keyboard;
            [FieldOffset(0)] public HARDWAREINPUT hardware;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HARDWAREINPUT
        {
            public uint uMsg;
            public ushort wParamL;
            public ushort wParamH;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int left;
            public int top;
            public int right;
            public int bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct GUITHREADINFO
        {
            public uint cbSize;
            public uint flags;
            public IntPtr hwndActive;
            public IntPtr hwndFocus;
            public IntPtr hwndCapture;
            public IntPtr hwndMenuOwner;
            public IntPtr hwndMoveSize;
            public IntPtr hwndCaret;
            public RECT rcCaret;
        }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

        [DllImport("user32.dll", EntryPoint = "IsWindow")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool NativeIsWindow(IntPtr window);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr window);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr window, StringBuilder className, int maxCount);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetForegroundWindow(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetGUIThreadInfo(uint threadId, ref GUITHREADINFO info);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint count, INPUT[] inputs, int size);

        [DllImport("user32.dll")]
        private static extern uint MapVirtualKey(uint code, uint mapType);

        [DllImport("user32.dll")]
        private static extern short GetAsyncKeyState(int virtualKey);

        [DllImport("user32.dll")]
        private static extern short GetKeyState(int virtualKey);

        [DllImport("user32.dll")]
        private static extern IntPtr GetKeyboardLayout(uint threadId);

        [DllImport("kernel32.dll")]
        private static extern void SetLastError(uint error);
    }
}
