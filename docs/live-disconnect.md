# Actual VPN-carried TightVNC disconnects during DNClient upgrades

Two stock DNClient Desktop 0.9.7 -> 0.9.8 upgrades were tested on 2026-09-10 using a real macOS Screen Sharing connection through the VPN. The upgrade closed Desktop, the VPN stopped, the viewer connection disappeared, and TightVNC's session helper exited. Its twelve cleanup releases were captured with the installer foreground. Neither upgrade stalled.

These are production-installer tests, separate from this repository's synthetic-input fixture and its explicit Alt/Escape setup. They reproduce the real disconnect and cleanup sequence, but do not reproduce the original failure.

## Environment and method

- Windows 11 build `26100.9445`, x64.
- `msi.dll` `5.0.26100.9444`, `msihnd.dll` `5.0.26100.7920`, `user32.dll` `10.0.26100.8117`.
- TightVNC Server `2.8.88.0` and macOS Screen Sharing on macOS `15.7.9`, build `24G830`.
- One authenticated viewer connected through the enrolled VPN before MSI launch; Desktop and all GUI instrumentation ran in interactive session 1.
- Each test started after a separate boot from the same enrolled 0.9.7 snapshot. The registered cached MSI was verified readable, with the expected version and hash, before each upgrade.
- No Alt/Escape setup, synthetic reset, manual viewer close, or viewer interaction after connection. Enter advanced the full wizard before execution; Finish was pressed after the observation period. The passive test sent no keyboard input.

The observer recorded interface state, TCP connections, Desktop/helper processes, foreground ownership, and MSI menu state. A passive keyboard hook and WinEvent recorder captured input and menu events. Observation continued for 60 seconds after the close-action boundary. The recorder does not capture mouse clicks; their absence is a procedural control.

## Results

Times are the VM's recorded UTC timestamps. Each row is one measured upgrade, not an estimated reproduction rate.

| Case | UI | Close-action entry | Twelve cleanup releases | Menu mode | Result |
| --- | --- | --- | --- | --- | --- |
| `vpn-full-03` | Full wizard | 06:23:44.016 | 06:23:44.116-06:23:44.118 | Not observed | Exit 0, version 0.9.8, VPN restored |
| `vpn-passive-01` | `/passive` | 06:28:14.007 | 06:28:14.140-06:28:14.146 | Not observed | Exit 0, version 0.9.8, VPN restored |

All cleanup events arrived with the corresponding MSI dialog foreground and GUI flags zero. In the full run, `ExecuteAction` completed at 06:23:54; no subsequent key was recorded until Finish at 06:24:44.373. In the passive run, installation completed at 06:28:24.348 and the twelve releases were the only recorded keyboard input. Neither trace contained a menu event or reconnect. Both recorders reported zero dropped records, callback errors, or writer errors.

The keyboard hook reports the generic modifier inputs as their sided equivalents: `164,164,165,160,160,161,162,162,163,91,92,46`. All twelve events are injected key releases with hook message `WM_KEYUP` (`0x101`). This hook does not identify the producer PID or the final message delivered to the window, so these fields cannot directly be equated with the original stalled UI thread's saved `WM_SYSKEYUP`.

An earlier attempt stopped before MSI launch because the viewer had not connected. Another reached an unrelated unreadable cached-package error before the close action; a standard recache from the original MSI succeeded before saving the common baseline. Neither attempt is counted above.

## Interpretation

The disconnect and cleanup burst are insufficient to reproduce the hang in these two runs. The original captured menu-mode stall and the [synthetic setup experiment](alt-setup.md) remain separate evidence. The missing condition in the original live failure has not been identified; these results do not establish that a Windows update fixed it or that the customer used Alt/Escape.

Since the full wizard also succeeded, this comparison does not demonstrate `/passive` fixing a reproduced live failure. The [earlier synthetic passive comparisons](validation.md) establish only their tested cases.

Raw production logs remain local. The archives were checked for ZIP integrity, JSON parsing, intact recorder output, and matching harness hashes. Their SHA-256 values are preserved for provenance:

| Artifact | SHA-256 |
| --- | --- |
| Stock 0.9.7 MSI | `b47d43dbc66c0632a8d642b9ef9d487388ebdf8e2e2e025ff87f0628139d04a2` |
| Stock 0.9.8 MSI | `e78f5723bda16a3efea7650b89daedfaed6d0f64ace375bad8419ff7f11d6891` |
| Full run archive | `5604e1f35be68acf31cf848de08ba9f8cf0f9fb259496b593f5056a8ba913ca2` |
| Passive run archive | `d007245ddc4287639fafcca179a73fe5ca80fe0fe09d1bc19e7d72a2c6016456` |
