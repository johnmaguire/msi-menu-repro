# Validation on Windows 11

The unmodified [Actions build from commit `81c0d4e`](https://github.com/johnmaguire/msi-menu-repro/actions/runs/34431542745) reproduced the menu-mode stall. The corresponding passive-UI comparisons completed without recovery input. Tests ran on 2026-09-10 UTC in an elevated, interactive Windows PowerShell 5.1 console.

## Environment and provenance

- Windows 11 24H2, build `26100.9445`, x64.
- `msi.dll`: `5.0.26100.9444`; `msihnd.dll`: `5.0.26100.7920`.
- ZIP SHA-256: `35965dcb33d3bdb9e1f44564c6c49efaaa7fc772bee65f050ae6f33bdfe0bcba`.
- MSI SHA-256: `311fa1e462886079e80f9c15c475ab9a8a10772e59d25bb17295775e0fc4b53b`.

[Machine-readable measurements](validation.json) include the helper/script hashes, DLL hashes, accepted input events, timestamps, recovery results, and hashes of the original evidence files. The tested package came directly from Actions; no package files were edited in the VM.

## Results in execution order

Each row is one valid run. The test product was installed and removed between rows, with no reboot during this sequence. All six installations and cleanup operations returned exit code 0.

| Order | Input | UI | Menu mode | Outcome |
| --- | --- | --- | --- | --- |
| 1 | Exact TightVNC reset | Full | Not observed | Trigger not reproduced; completed without Escape |
| 2 | None | Full | Not observed | Control completed without Escape |
| 3 | Paired Alt tap | Full | `0x0C` | Stalled; resumed after Escape |
| 4 | Exact TightVNC reset | Full | `0x0C` | Stalled; resumed after Escape |
| 5 | Paired Alt tap | Passive | Not observed | Completed without Escape |
| 6 | Exact TightVNC reset | Passive | Not observed | Completed without Escape |

All injected events were accepted: two for each paired Alt tap and twelve for each exact reset. The expected installer window owned the foreground, menu mode was initially inactive, and no tracked modifier or Delete key was down before each injection.

In rows 3 and 4, GUI flags became `0x0C` (`GUI_INMENUMODE | GUI_SYSTEMMENUMODE`). After the ten-second close timeout, the MSI log remained unchanged for another 26.680 and 26.668 seconds respectively. The close action had not completed. The helper then sent Escape, new close-action completion appeared in the log, and installation finished successfully. No recovery input was sent in the other rows.

Before this sequence, a separate exact-reset trial immediately following a VM reboot also completed without reproducing. A subsequent no-input trial could not acquire foreground access from its scheduled launcher and was correctly marked invalid before trigger injection. That idle installer was dismissed, and the six runs above used one persistent classic PowerShell console. These additional attempts are recorded separately in the measurement file.

## Interpretation

The exact reset sequence can trigger this stall in the standalone installer, but it did not do so in every recorded context. In this sequence it reproduced after the paired Alt control and did not reproduce before it. These observations do not isolate which part of session history matters or establish a reproduction rate. Preserve run order and negative results when comparing systems.

The no-input control and recovery after Escape distinguish the stall from the deliberate application-close timeout. The passive comparisons validate complete installation/removal for this package and these synthetic inputs. They do not validate a production upgrade during an actual TightVNC disconnect.

No live TightVNC disconnect, VPN interruption, or stack capture was performed in this validation. Menu state and MSI progress are the evidence collected here.
