# Windows helper

Build with the existing .NET Framework compiler from 64-bit Windows PowerShell:

```powershell
.\helper\build.ps1 -OutputDirectory .\out
Add-Type -Path .\out\Repro.Native.dll
```

The DLL targets x64 and uses C# syntax supported by .NET Framework 4's compiler.
The sleeper is a Windows application with no console or windows. It exits after
180 seconds if the installer or runner has not already stopped it.

`MsiMenuRepro.Native` exposes:

| Method | Result |
| --- | --- |
| `FindDialog(uint pid, string className)` | First visible top-level window matching both fields, or `IntPtr.Zero`. |
| `Snapshot(IntPtr hwnd)` | `Valid`, `Error`, `Pid`, `Tid`, `ClassName`, `Foreground`, `IsForeground`, `Flags`, `MenuOwner`, `Focus`. |
| `TryForeground(IntPtr hwnd)` | Calls `SetForegroundWindow`; returns whether the expected window is foreground. |
| `IsWindow(IntPtr hwnd)` | Whether the handle still identifies a window. |
| `ResetModifiers(IntPtr expectedForeground)` | Input result for the 12 unpaired key releases below. |
| `AltTap(IntPtr expectedForeground)` | Input result for Alt down, 40 ms delay, Alt up. |
| `PressKey(IntPtr expectedForeground, ushort virtualKey)` | Input result for a balanced down/up batch. |
| `KeyboardState()` | Foreground thread ID, its keyboard layout as hex, and modifier/Delete key states. `Down` uses `GetAsyncKeyState`; `Toggle` uses the caller's `GetKeyState`. |

Input results contain `Success`, `Attempted`, `Injected`, `LastError`, `Error`,
`ForegroundBefore`, `ForegroundAfter`, and an `Events` array of `VirtualKey`,
`Flags`, `Injected`, and `LastError`. `Counts` records each `SendInput` return
value in call order. `Injected` counts events accepted by
`SendInput`; it does not prove that the installer processed them.

Injection refuses an invalid or non-foreground target. The reset also checks the
foreground before each event. A changed foreground is reported as failure. An
Alt keydown accepted before a focus change is still released to avoid leaving
the key pressed. A partially accepted down/up batch similarly attempts its
missing keyup, and preserves the original failure.

The reset uses these virtual keys, in this order:

```text
12 A4 A5 10 A0 A1 11 A2 A3 5B 5C 2E
```

Each release uses one `SendInput` call, `wScan = MapVirtualKey(vk, 0)`, and flags
`KEYEVENTF_KEYUP` only. There is no key-state priming, inter-event logging, or
inter-event sleep. Per-event results are returned after the burst.

`Snapshot.Flags & GUI_INMENUMODE` (`0x4`) observes menu mode.
`GUI_SYSTEMMENUMODE` is `0x8`; `GUI_POPUPMENUMODE` is `0x10`.
The helper neither attaches input queues nor installs hooks, sends messages to
other processes, or changes process privileges. The runner must start the
correct interactive session and pass the expected installer window explicitly.
