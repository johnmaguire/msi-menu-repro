# Why the reset stalls only after an earlier Alt tap

The exact TightVNC reset does not stall a fresh Windows session, and it does stall the same session after one
ordinary Alt tap. The reason is a session-wide change in how Windows classifies an unpaired Alt release, combined
with how Windows Installer's full UI reacts to that classification. This page records the measurements behind that
statement; they were taken on 2026-09-10 with a plain-window harness ([`standin.ps1`](../standin.ps1)) and confirmed
with this repository's installer.

## Mechanism

Windows Installer's full UI (`msihnd.dll`) subclasses every dialog control. On `WM_SYSKEYUP` with `wParam ==
VK_MENU` it sends itself `WM_SYSCOMMAND` / `SC_KEYMENU`, which enters Windows menu mode and blocks the dialog thread
until a key or click arrives. That send has no other condition: it does not inspect `lParam`, `GetKeyState`, or
whether an Alt press was seen. There is no handler for `WM_KEYUP` at all. (Static analysis of `msihnd.dll` 5.0.26100
and 5.0.26200 with public symbols; the two builds are identical on this path.)

An unpaired Alt release, which is what the reset injects, is therefore only dangerous if Windows delivers it as
`WM_SYSKEYUP` rather than `WM_KEYUP`. The harness shows that this classification changes once per session:

| Session state | Injected `VK_MENU` release arrives as | `lParam` |
| --- | --- | --- |
| Fresh boot, no Alt pressed yet | `WM_KEYUP` (`0x101`) | `0x80380001` |
| After one clean Alt tap anywhere | `WM_SYSKEYUP` (`0x105`) | `0x80380001` |

The `lParam` is identical in both rows: bit 30 clear, meaning Windows had not seen the key go down. Only the message
id differs. The change is made when the message is posted to the window; a `WH_KEYBOARD_LL` hook reports `WM_KEYUP`
for the same event in both states, so a low-level hook cannot observe it.

Once a release arrives as `WM_SYSKEYUP`, a single release is enough; the three Alt releases in the reset are not
required.

## What primes the session

Tested by injecting a candidate, then probing with the reset on the same boot. A `WM_KEYUP` probe result shows the
session was still fresh, so several candidates could be chained on one boot; a `WM_SYSKEYUP` result ended the chain
and the VM was rebooted.

| Input | Primes? | Note |
| --- | --- | --- |
| Alt tap (Alt down, Alt up, nothing else) on a window with a system menu | Yes | Enters and leaves menu mode |
| Alt tap on a window without a system menu | Yes | No menu mode entered |
| Alt held during a mouse click, then released | Yes | |
| Alt tap on an unrelated application (Character Map) | Yes | Primed a process started afterwards and the installer |
| Alt+Tab, Alt+letter, Alt+F4 | No | Their own Alt release is delivered as `WM_KEYUP` |
| F10 tap (enters menu mode without Alt) | No | |
| A posted `SC_KEYMENU` with no key input | No | Enters menu mode fresh; menu mode itself is not the state |
| Unpaired Alt releases: one, three, or the twelve-release reset | No | They do not prime, they only reveal priming |

In short: any Alt release that Windows itself delivers as `WM_SYSKEYUP`, which is a clean tap with nothing pressed
during the hold, in any application. The `GetKeyState(VK_MENU)` toggle bit is not the state: a second tap clears
that bit and the release is still delivered as `WM_SYSKEYUP`.

## Scope and lifetime

The state is session-wide. It crossed every process boundary tested: a stand-in process started after the tap, a
second stand-in process, and the real installer. It survived at least 23 minutes and several installer processes in
an earlier investigation. It was cleared by a reboot. Logoff could not be tested on the VM used (autologon did not
re-logon).

## Confirmation with this installer

Two runs of the unmodified package on separate boots:

```powershell
.\repro.ps1 -Input TightVncReset -UI Full -Precondition None
```

In each, the only Alt input since boot was one Alt tap delivered to a different process (Character Map in one run,
the stand-in window in the other) before `repro.ps1` started. Both returned `Reproduced`: menu mode observed, the MSI
log quiet 29.0 s beyond the close timeout, progress after Escape, installation and cleanup exit 0. Against 0 of 3
fresh-boot runs on the same build in [alt-setup.md](alt-setup.md).

The basic UI was checked the same way. With the session verified as primed by the stand-in immediately before and
after, `repro.ps1 -Input TightVncReset -UI Passive -Precondition None` returned `TriggerNotReproduced`: all twelve
releases were accepted with msiexec's `#32770` progress dialog foreground, no menu mode was observed, and
installation and cleanup returned 0. A `/passive` run of the production installer described under Context in the README, under the same priming, also
completed its close action without a stall. This is expected from the mechanism: the basic UI has no equivalent of
the `msihnd.dll` send, and in the stand-in a `WM_SYSKEYUP` for an Alt press Windows never saw does not enter menu
mode through `DefWindowProc` alone (the emulation step is what raises `SC_KEYMENU`).

A separate, one-shot path was seen after Alt+Tab away and back: the next release still arrived as `WM_KEYUP`, but
the kernel's own `DefWindowProc` handling raised `SC_KEYMENU` because the window's queue held an unmatched Alt press.
It engaged once in the stand-in and was gone by the next reset. It was not tested against the installer dialog, whose
focus is on a child control; the one Alt+Tab trial with the installer in [alt-setup.md](alt-setup.md) did not stall.

## The `-Precondition AltTapAndEscape` option, revisited

The setup option primes the session in the same way. Inside the installer process it also has a second effect:
`msihnd.dll` keeps a per-process toggle on `WM_SYSKEYUP VK_MENU` and swallows every second one. The setup tap's
release consumes the first, so during the following reset the first Alt release is swallowed and the second (`Left
Alt`, also reported as `VK_MENU`) sends `SC_KEYMENU`. A single unpaired release after that setup would not stall in
the same process. Priming from another process, as in the confirmation runs above, leaves the installer's toggle at
zero and the first release fires.

## Environment

Windows 11 24H2 build `26100.9445` x64; `msi.dll` `5.0.26100.9444`, `msihnd.dll` `5.0.26100.7920`, `user32.dll`
`10.0.26100.8117`. Stand-in runs in the interactive session as the logged-on user via a scheduled task; installer
runs from the same task launcher with `-Precondition None`. Only this build was measured; the `msihnd` analysis also
covered `5.0.26200`. No kernel-side trace was taken, so the Windows variable holding the state is not named.

## Running the stand-in

`standin.ps1` needs the same interactive, unlocked, elevated session as `repro.ps1`. It creates its own window,
injects the requested steps, and writes `main.log` (every keyboard and menu message, with `GetGUIThreadInfo` flags)
and `result.json` under `standin-results\<RunName>\`.

```powershell
.\standin.ps1 -RunName fresh -Steps burst,esc
.\standin.ps1 -RunName primed -Steps alttap,esc,burst,esc
```

Steps: `burst` (the twelve releases), `altup` (one Alt release), `lalt3` (Alt, Left Alt, Right Alt releases),
`alttap`, `f10tap`, `alttab`, `altclick`, `altletter`, `altf4`, `esc`, `enter`, `click`, `sckeymenu` (post
`SC_KEYMENU`, no input), `nosys` (switch to a window without a system menu), `win2` (second window, same process),
`main` (back to the first window), `peer` (window in a second process), `charmap` (Character Map), `sleepN`.
`-Hook` adds a `WH_KEYBOARD_LL` log; `-MsihndToggle` reproduces the installer's per-process toggle. On every
`WM_SYSKEYUP VK_MENU` the window does what `msihnd.dll` does and sends itself `SC_KEYMENU`, so a stalled step shows
`menu=True` until the following `esc`. Read the classification of each release from the `WM_KEYUP` / `WM_SYSKEYUP`
lines with `wParam=0x12`.

A step whose window was not foreground is recorded with `valid=False` and must not be counted.
