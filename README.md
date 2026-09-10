# Windows Installer menu-mode reproduction

A small WiX installer and input helper for investigating an installation stall triggered by Alt-key input. The helper can replay TightVNC 2.8.88's modifier-reset sequence, send a paired Alt tap as a separate control, or observe without injecting input. No VPN or TightVNC installation is needed for the synthetic tests.

The test looks for a specific sequence: the installer enters Windows menu mode, installation stops making progress beyond its application-close timeout, and progress resumes when the helper sends Escape. A slow installation or a menu-mode flag alone is not sufficient evidence.

## Run the reproduction

Use a disposable **64-bit Windows desktop** with an interactive, unlocked session. Download the `msi-menu-repro-windows-x64` artifact from a successful run in this repository's [GitHub Actions](https://github.com/johnmaguire/msi-menu-repro/actions), then extract the contained `msi-menu-repro.zip`. Builds are unsigned; the download includes a ZIP checksum and the package contains `SHA256SUMS` for its files.

Open **64-bit Windows PowerShell 5.1 as Administrator**, change to the extracted directory, and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\repro.ps1 -Input TightVncReset -UI Full
```

The exact reset only stalls a session in which Windows has already delivered one clean Alt tap (Alt down, Alt up, nothing else) to any application since boot; on a fresh boot it completes normally. The mechanism and measurements are in [docs/priming.md](docs/priming.md). To replay it after an explicit Alt/Escape setup, use:

```powershell
.\repro.ps1 -Input TightVncReset -UI Full -Precondition AltTapAndEscape
```

This first taps Alt, confirms menu mode, then sends Escape and confirms menu mode is clear before replaying the twelve releases. In a [comparison with a reboot before every run](docs/alt-setup.md), the reset stalled in 3/3 runs with this setup and 0/3 without it. The setup alone completed normally. The extra setup events are recorded separately from the reset. Because the setup runs inside the installer process, it also consumes `msihnd.dll`'s per-process toggle on Alt releases, so the stall in that mode is raised by the reset's second Alt release rather than its first; see [docs/priming.md](docs/priming.md). An Alt tap delivered to any other application before `repro.ps1` starts primes the session without that side effect.

Leave the keyboard and mouse alone while the test runs. The helper starts a windowless sleeper, launches the MSI, advances its setup UI, and injects input during the installer's ten-second application-close wait. It checks that the expected installer owns the foreground, records menu state and progress, and observes for up to 35 seconds after injection before attempting recovery with Escape. Observation ends early if installation completes. The helper then finishes the installer and removes its own test product.

To check whether a session is primed without involving the installer, or to reproduce the classification change directly, use [`standin.ps1`](standin.ps1), a plain-window harness that logs whether each injected Alt release arrives as `WM_KEYUP` or `WM_SYSKEYUP`; usage is in [docs/priming.md](docs/priming.md).

Run these controls separately in the same session:

```powershell
.\repro.ps1 -Input AltTap -UI Full
.\repro.ps1 -Input None -UI Full
.\repro.ps1 -Input None -UI Full -Precondition AltTapAndEscape
.\repro.ps1 -Input TightVncReset -UI Passive
.\repro.ps1 -Input AltTap -UI Passive
```

`Full` uses the authored setup wizard. `Passive` uses `msiexec /passive`, the basic progress UI. The helper defaults to `TightVncReset`, `Full`, and `-Precondition None`. The optional `AltTapAndEscape` setup requires full UI. Record run order; to compare the reset with and without setup independently of earlier test input, reboot before each run as described in the [setup experiment](docs/alt-setup.md).

To choose where evidence is written:

```powershell
.\repro.ps1 -Input AltTap -UI Full -OutputDirectory C:\repro-results\alt-full
```

Each run saves a JSON result, a verbose MSI log, timestamped events, and Windows/DLL version information. Keep results from every comparison, including runs that did not reproduce. Every run first removes an existing **MSI Menu Reproduction** installation to start fresh. `-KeepInstalled` skips removal after the run; the test product can subsequently be removed through Windows' installed-apps interface. Cleanup targets this test product and the helper's sleeper process; the package does not modify any network or VPN configuration.

The helper must run at an integrity level at least as high as the installer. Windows can reject `SendInput` across that boundary, and held keys can affect the injected sequence. A rejected input, unexpected foreground window, lost interactive session, or installer error is an invalid or inconclusive test, not evidence that a Windows build is unaffected. [Microsoft: SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput).

The result's verdict distinguishes these outcomes:

| Verdict | Interpretation |
| --- | --- |
| `Reproduced` | Menu mode and blocked progress were observed, followed by progress after recovery input |
| `TriggerNotReproduced` | The injected sequence did not enter menu mode in this run |
| `ControlCompleted` | The run with `-Input None` completed normally |
| `MenuModeWithoutStall` | Menu mode was observed but the measured stall was not |
| `StallNotReleased` | The suspected stall did not recover as expected; inspect the logs |
| `InvalidTest` | Test preconditions, injection, or installer execution failed; do not count this as a passing control |

The JSON also records `menuSeen`, `menuModeAtObservationEnd`, `completedBeforeRelease`, `releaseSent`, `progressedAfterRelease`, and installer/cleanup exit codes. These describe observation and recovery after the selected trigger. Optional setup input and its menu checks are recorded separately under `preconditioning`; the Escape used during setup is distinct from recovery after a stall.

## What is being tested

The MSI installs one harmless payload file and uses WiX's standard `util:CloseApplication` action to close the windowless sleeper. Because the sleeper has no window that can process a close message, the action waits for its timeout. That creates an injection interval inside the real action without adding a blocking test action to MSI's sequence. The sleeper runs outside the installed payload directory to avoid a FilesInUse prompt.

The input modes are deliberately separate:

| Input mode | Events | Purpose |
| --- | --- | --- |
| `TightVncReset` | Twelve unpaired key releases in TightVNC's order | Replay the cleanup sequence under investigation |
| `AltTap` | Alt down followed by Alt up | Control for Windows Installer's response to ordinary Alt input |
| `None` | No injected trigger | Measure normal progress through the same action |

The reset sequence is `Alt, Left Alt, Right Alt, Shift, Left Shift, Right Shift, Ctrl, Left Ctrl, Right Ctrl, Left Windows, Right Windows, Delete`, each with `KEYEVENTF_KEYUP`. It follows `InputInjector::resetModifiers` and `injectKeyEvent` in `win-system/InputInjector.cpp` from the [TightVNC 2.8.88 source archive](https://www.tightvnc.com/download/2.8.88/tightvnc-2.8.88-src-gpl.zip). The downloaded archive's SHA-256 is:

```text
8df7e0cefac173f0d87217a64d6972b03291d186dba827ca2cffb8e8954b1f21
```

This repository implements the Win32 input calls independently; it does not contain TightVNC source. Replaying those calls does not reproduce every detail of a live connection's teardown. The helper never substitutes an Alt tap when the reset sequence fails to trigger menu mode. The earlier Alt/Escape setup runs only when explicitly requested with `-Precondition AltTapAndEscape`.

In the original investigation, captured stacks showed this path:

```text
Alt release -> WM_SYSKEYUP -> WM_SYSCOMMAND / SC_KEYMENU
            -> installer UI thread enters Windows menu mode

installer notification -> MsiUIMessageContext::Invoke
                       -> waits for the UI thread
```

The helper observes `GUI_INMENUMODE` through `GetGUIThreadInfo`; it does not capture or decode stacks. Combine that observation with the MSI log and progress after Escape when assessing a new run. [Microsoft: GUITHREADINFO](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-guithreadinfo).

## Evidence and limits

The [initial standalone validation](docs/validation.md) and [follow-up setup experiment](docs/alt-setup.md) used Windows 11 build `26100.9445`, with `msi.dll` at `5.0.26100.9444` and `msihnd.dll` at `5.0.26100.7920`.

In the initial validation, the paired Alt tap reproduced the stall. The exact TightVNC reset completed normally before that control, then reproduced the stall when tested again afterward in the same desktop session. Both stalls resumed after Escape.

The follow-up comparison rebooted before each run and held reset timing constant. The exact reset reproduced in all three runs after an explicit Alt/Escape setup and none of three runs without it. One setup-only control also completed normally. This supports the earlier setup as the reason for the changed behavior in that experiment.

The [priming measurements](docs/priming.md) then identified the mechanism on the same build. `msihnd.dll` sends `SC_KEYMENU` on every `WM_SYSKEYUP` for the Alt key with no other check and has no `WM_KEYUP` handler. On a fresh boot Windows delivers an unpaired Alt release as `WM_KEYUP`; after one clean Alt tap anywhere in the session it delivers the same event, with the same `lParam`, as `WM_SYSKEYUP`, and keeps doing so until reboot. The state is session-wide: an Alt tap on an unrelated application primed the installer in two further runs of this package with `-Precondition None`. Alt+Tab, Alt+letter, Alt+F4, F10, and unpaired releases do not prime. The Windows variable holding the state was not identified; no kernel trace was taken.

In the initial `/passive` validation, both input sequences completed installation and removal without entering menu mode or needing Escape. A further `/passive` reset run in a session verified as primed immediately before and after also completed without menu mode. The basic UI has no equivalent of the `msihnd.dll` send, and a `WM_SYSKEYUP` whose Alt press Windows never saw does not enter menu mode through `DefWindowProc` alone. A live TightVNC disconnect during a production upgrade was not tested here.

A subsequent [actual VPN-carried TightVNC disconnect comparison](docs/live-disconnect.md) used stock DNClient upgrades and macOS Screen Sharing. Both full and passive UI completed after the real cleanup burst, without an Alt/Escape setup. This reproduced the disconnect but did not reproduce the original live hang. Those sessions were fresh boots driven with Enter only, which the priming measurements identify as the non-stalling condition; a live disconnect test should be repeated in a session that has received a clean Alt tap.

Record test order, reboot history, setup option, input mode, foreground validation, menu state, and progress before and after recovery. Preserve runs where the trigger did not reproduce alongside successful reproductions.

## Optional live TightVNC test

This is an additional, unvalidated procedure; it is harder to time than the synthetic replay.

1. Use a Windows VM with TightVNC Server and an independent local or hypervisor console. Record the server and viewer versions and ensure there is only one viewer connected.
2. Decide whether the session should be primed and record it. A fresh boot with no Alt input is expected not to stall; to test the primed case, tap Alt once on any application (Notepad is enough) through the viewer before starting, and confirm with `standin.ps1 -Steps burst,esc` where the console allows it.
3. Through the viewer, start `repro.ps1 -Input None -UI Full` and let the installer reach its application-close wait.
4. Disconnect the viewer during that wait. Do not send an extra click or key to the remote Windows desktop while disconnecting.
5. Observe through the independent console without clicking, changing focus, or pressing a key in Windows until the helper's observation period ends. The helper handles recovery afterward.
6. Preserve the output and repeat with `-UI Passive`.

No VPN interruption is needed: the event under test is the last viewer disconnecting while the installer owns the foreground. A result from this procedure should be labeled **live disconnect**, with its timing and connection setup recorded, rather than labeled as synthetic `TightVncReset` input.

## Build

The Windows GitHub Actions workflow builds the MSI with WiX 6.0.2 and matching extensions, and compiles the C# helper and sleeper using .NET Framework. Its ZIP contains `MsiMenuRepro.msi`, `Repro.Native.dll`, `msi-menu-repro-sleeper.exe`, `repro.ps1`, `standin.ps1`, and documentation. CI builds the binaries and smoke-tests quiet installation/removal; it does not exercise the interactive stall.

To build locally on Windows, install the .NET 8 SDK and use Windows PowerShell 5.1:

```powershell
.\build.ps1
```

The build creates `dist\msi-menu-repro.zip`, its checksum, and the unpacked package in `dist\msi-menu-repro`. A source checkout's `repro.ps1` also looks in that unpacked directory for its artifacts.

## Report a result

Use [the report template](docs/report-template.md) to preserve the tested input and build provenance. Attach the JSON result, events, and MSI log for both the reproduction and controls. Review logs before publishing because MSI logs can include local usernames and paths.

For TightVNC, [the upstream reporting instructions](https://www.tightvnc.com/bugs.php) point to its SourceForge bug tracker and ask reporters to search for an existing issue first. Frame the report as an interaction between modifier cleanup and Windows Installer, with a possible mitigation to evaluate. An Alt-only reproduction establishes Windows Installer behavior; it does not independently establish that a particular TightVNC disconnect supplied that input.
