# Modifier reset can leave Windows Installer in menu mode and stall installation

<!-- Replace placeholders with measurements. Remove untested rows rather than implying they passed. -->

## Summary

While Windows Installer's full progress UI owns the foreground, [the exact TightVNC modifier-reset replay / a paired Alt tap / a live TightVNC disconnect] causes [observed result]. Installation [does / does not] resume after Escape. The corresponding passive-UI test [observed result / was not tested].

The standalone reproduction installs a harmless payload and uses a windowless sleeper to create a ten-second wait in WiX's ordinary `CloseApplication` action. It does not require networking software or a VPN.

## Build and environment

- Reproduction repository: <https://github.com/johnmaguire/msi-menu-repro>
- Commit SHA:
- GitHub Actions run or release URL:
- ZIP SHA-256:
- MSI SHA-256:
- Windows edition, version, build, and architecture:
- `msi.dll` version:
- `msihnd.dll` version:
- Windows PowerShell version:
- Console/session type and elevation:
- Test order, reboot/session boundaries, and any earlier Alt input:
- Session primed before the run (a clean Alt tap on any application since boot; see docs/priming.md), and how that was verified (for example `standin.ps1 -Steps burst,esc` reporting `WM_SYSKEYUP`):
- Explicit `-Precondition` option, including whether setup entered and exited menu mode:
- TightVNC Server version, if used:
- Viewer name/version and operating system, if used:
- Other connected viewers, if any:

The replay follows TightVNC 2.8.88's `InputInjector::resetModifiers`: twelve unpaired releases, in the order Alt, Left Alt, Right Alt, Shift, Left Shift, Right Shift, Ctrl, Left Ctrl, Right Ctrl, Left Windows, Right Windows, Delete. Source: [official archive](https://www.tightvnc.com/download/2.8.88/tightvnc-2.8.88-src-gpl.zip), SHA-256 `8df7e0cefac173f0d87217a64d6972b03291d186dba827ca2cffb8e8954b1f21`.

## Steps

1. Extract the specified build into a disposable Windows VM.
2. Open elevated Windows PowerShell 5.1 in that directory.
3. Run the command below and leave keyboard/mouse input alone through the observation period.
4. Read the recorded result and compare with the controls below.

```powershell
.\repro.ps1 -Input TightVncReset -UI Full -OutputDirectory C:\repro-results\reset-full
```

Exact commands actually tested:

```powershell
# Paste the commands used, including any non-default options.
```

For a live disconnect test, describe when the viewer disconnected, how the last client was identified, and how the Windows desktop was observed without changing focus. The synthetic `None` mode should be recorded as **live disconnect** when disconnecting the viewer supplied the trigger.

## Results

| Input | UI | Foreground/input valid? | Menu mode observed? | Progress before Escape? | Progress after Escape? | MSI result |
| --- | --- | --- | --- | --- | --- | --- |
| TightVNC reset replay | Full | | | | | |
| Paired Alt tap | Full | | | | | |
| None | Full | | | | | |
| TightVNC reset replay | Passive | | | | | |
| Paired Alt tap | Passive | | | | | |
| Live disconnect, if tested | Full | | | | | |

- Observation duration after input:
- Last MSI action/message before recovery:
- Time from Escape to next progress, if observed:
- Successful repetitions / valid attempts for each trigger:
- Invalid attempts and reasons, including input failures or foreground changes:
- Differences between an exact reset before and after the paired Alt control:

An MSI error or failed injection is not a successful no-stall control. A run where the exact replay did not enter menu mode should be reported as **trigger not reproduced**, even if a separate paired Alt run stalled.

## Expected behavior

Installation should continue making progress when the close timeout expires, without requiring another key or click to exit keyboard menu navigation.

## Interpretation

[Describe what these measurements establish and what remains untested. Keep exact replay, paired Alt, and live disconnect findings separate.]

Earlier investigation of another installer found its UI thread inside Windows menu mode after `WM_SYSKEYUP` / `SC_KEYMENU`, with an installer notification blocked in `MsiUIMessageContext::Invoke`. The helper in this repository records menu state and MSI progress; a new run does not establish matching thread stacks unless additional captures were taken.

This report asks whether TightVNC can mitigate the interaction during modifier cleanup. It does not assume that releasing modifiers is itself incorrect or that an Alt-tap reproduction proves a specific live disconnect's input sequence.

## Attachments

- JSON result, timestamped events, and verbose MSI log for each reported run.
- Build/hash and Windows/DLL version metadata.
- Optional short recording showing the observation period and recovery.

Review attachments for local usernames and paths before publishing. Do not include unrelated application data or credentials.
