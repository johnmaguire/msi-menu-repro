# Replaying the reset after an earlier Alt tap

In seven runs that each started after a VM reboot, the exact TightVNC reset stalled the installer in all three runs with an explicit Alt/Escape setup and none of the three runs without it. The setup alone, followed by no trigger input, also completed normally. These results provide a tested setup for this VM; they do not establish universal or deterministic behavior.

## Procedure

Tests ran on 2026-09-10 UTC. Every run used the same standalone MSI and native helper on Windows 11 24H2 build `26100.9445`, with `msi.dll` `5.0.26100.9444` and `msihnd.dll` `5.0.26100.7920`. Each run started after a separate reboot. The runner used the installer's existing ten-second application-close wait; it added no MSI actions.

In the runs with setup, the runner:

1. Verified the installer was foreground and not in menu mode.
2. Sent a paired Alt tap and confirmed menu mode became active.
3. Sent Escape and confirmed menu mode cleared.
4. Replayed the twelve unpaired TightVNC key releases at the common injection time.

Runs without setup skipped steps 2 and 3. Both groups scheduled the reset four seconds after observing the close-action boundary; the measured delay was 4.007-4.024 seconds across the six reset trials. All twelve releases were accepted in every reset trial. Immediately before the reset, the installer was foreground, menu mode was clear, and no tracked modifier or Delete key was down.

The seventh run performed the Alt/Escape setup, then injected no trigger at the common time. It checked whether the setup itself left installation stalled.

The [machine-readable measurements](alt-setup.json) include timing, setup and trigger counts, window state, boot-event provenance, and hashes of the raw evidence.

## Results

Rows are in execution order. Every installation and subsequent removal returned exit code 0.

| Order | Earlier setup | Trigger | Outcome |
| --- | --- | --- | --- |
| 1 | None | Exact TightVNC reset | Completed without a stall |
| 2 | Alt/Escape | Exact TightVNC reset | Stalled; resumed after recovery Escape |
| 3 | Alt/Escape | Exact TightVNC reset | Stalled; resumed after recovery Escape |
| 4 | None | Exact TightVNC reset | Completed without a stall |
| 5 | None | Exact TightVNC reset | Completed without a stall |
| 6 | Alt/Escape | Exact TightVNC reset | Stalled; resumed after recovery Escape |
| 7 | Alt/Escape | None | Completed without a stall |

In the three positive runs, the reset entered menu mode again after the setup had cleared it. The MSI log then stayed quiet for 28.926-29.009 seconds beyond the close timeout. The runner sent a separate recovery Escape after observation, and installation resumed. No recovery input was needed in the other four runs.

## Run the explicit setup

Runner commit `90196cc` exposes the setup as an option:

```powershell
.\repro.ps1 -Input TightVncReset -UI Full -Precondition AltTapAndEscape
```

The default remains `-Precondition None`. The extra Alt and Escape events are recorded under `preconditioning`, separately from the twelve-event `injection`. Setup requires `-UI Full` because it verifies that Alt enters the full wizard's menu mode before clearing it. If either check fails, the run is invalid and the reset is not injected.

For a comparison, reboot the test VM before each command:

```powershell
.\repro.ps1 -Input TightVncReset -UI Full -Precondition None
.\repro.ps1 -Input TightVncReset -UI Full -Precondition AltTapAndEscape
.\repro.ps1 -Input None -UI Full -Precondition AltTapAndEscape
```

The runner does not reboot the machine itself. Running these commands consecutively without rebooting is a different comparison because earlier input may affect later runs.

## Interpretation and provenance

The matched timing and separate reboots support the earlier Alt/Escape setup as the cause of the changed outcome in this experiment. Confirming menu mode was clear before the reset, together with the successful setup-only control, shows that the positive runs were not simply left in the menu opened by the setup.

This does not identify which part of the setup matters internally, establish a particular Windows flag as the cause, or prove that every TightVNC disconnect has equivalent prior input. No live disconnect, VPN interruption, or new stack capture was performed. The [earlier validation](validation.md) remains useful historical evidence, including reset trials with different results in the same desktop session.

The seven measurements used an experimental runner implementing this setup, with the existing MSI and helper from the earlier Actions build. The public option was added afterward. Artifact hashes for these measurements are:

| Artifact | SHA-256 |
| --- | --- |
| MSI | `311fa1e462886079e80f9c15c475ab9a8a10772e59d25bb17295775e0fc4b53b` |
| Native helper | `89ef05bd7841729fecb19a7793211e271904ca0f34a0bbcd088001c7f727a429` |
| Experimental runner | `e2e76caec10aa2f2871040815c8cb99eba5ef5a0011b70b983980d95a641c45f` |

The setup events, confirmation snapshots, main injection, and final recovery are separate fields in each result. Keep those distinctions when reporting a run as an exact TightVNC replay with setup.

The unmodified [Actions package built from `90196cc`](https://github.com/johnmaguire/msi-menu-repro/actions/runs/34437850837) was subsequently checked in a fresh session: the explicit setup followed by the reset reproduced the stall, and the passive reset comparison completed normally. Both installed and uninstalled with exit code 0.

## Alt-Tab check

A separate fresh-session trial used Alt-Tab to switch from the installer to the runner's classic console and Alt-Tab back, then replayed the exact reset at the same four-second point. Both shortcuts were accepted, the intermediate console and return to the original installer were verified, and menu mode was clear before the reset. This trial completed without a stall or recovery input; installation and removal returned 0.

An initial attempt stopped before reset injection because its destination check observed Windows' temporary `ForegroundStaging` window. The valid retry waited for the known console instead. The invalid attempt is retained and is not counted as a negative reproduction.

This one valid Alt-Tab trial did not reproduce the effect of the Alt/Escape setup. It does not rule out other Alt-Tab sequences or establish what happened in a real TightVNC session.
