# Accessibility grant taken away mid-run - demo evidence

Captured on macOS 26.5 / Xcode 26.5 from the signed bundle (`make run`, `build/MachVoice.app`).
Logs come from `/usr/bin/log stream --style compact --predicate 'subsystem == "com.augustomklee.MachVoice"'`.

## Status: the live demo of the final build has not run yet

`tccutil reset Accessibility com.augustomklee.MachVoice` does remove the grant on macOS 26.5.
The #8 evidence said it did not, but a freshly launched second instance reported `Accessibility granted: false` right after the reset.
What misled #8 is that the running process keeps answering `true` (section 1).
So an agent can revoke the grant, but only a person can turn it back on in System Settings, because that toggle needs authentication.
The first probe below used up the grant, and nobody turned it back on during a 20-minute wait.
To finish the demo, turn MachVoice on in System Settings > Privacy & Security > Accessibility while the app runs, then run `revoke-mid-utterance.sh` from this directory after `swiftc -o /tmp/rcmd rcmd.swift`.
The script holds a synthetic Right Command, speaks through `say`, revokes with `tccutil` while the key is still held, releases, and screenshots the menu before and after.

## 1. What macOS does when the grant is taken away

Build: this branch before the live check was added, when `Permissions` still asked `AXIsProcessTrusted()`.
The grant was active at launch, and `tccutil reset` ran between launch and 08:41:24 with the app left running.
A synthetic Right Command press was posted at 08:41:24 and released 1.5 s later.

```
2026-09-17 08:40:27.802 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:EventTap] Event tap installed successfully
2026-09-17 08:40:27.802 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:AppDelegate] Accessibility granted: true
2026-09-17 08:40:27.802 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:AppDelegate] Microphone granted: true
2026-09-17 08:40:27.845 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:SpeechModelInstaller] Reserved locale: en_US
2026-09-17 08:40:27.850 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:SpeechModelInstaller] Speech model already available
2026-09-17 08:40:27.883 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:SpeechEngine] Speech model warmed, format=<AVAudioFormat 0x9feb96c10:  1 ch,  16000 Hz, Int16>
2026-09-17 08:41:24.514 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:EventTap] Right Command pressed
2026-09-17 08:41:24.533 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:Target] capture: appError=AXError(rawValue: -25204) elementError=AXError(rawValue: -25211) bundleID=com.github.wez.wezterm hasElement=false
2026-09-17 08:41:24.533 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:UtteranceController] Utterance started, target bundleID=com.github.wez.wezterm
2026-09-17 08:41:24.550 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:SpeechEngine] Analysis started
2026-09-17 08:41:24.614 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:AudioCapture] Input format: <AVAudioFormat 0x9feb95630:  1 ch,  48000 Hz, Float32>
2026-09-17 08:41:24.614 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:AudioCapture] Target format: <AVAudioFormat 0x9feb96c10:  1 ch,  16000 Hz, Int16>
2026-09-17 08:41:24.661 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:AudioCapture] Audio capture started
2026-09-17 08:41:26.021 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:EventTap] Event tap disabled
2026-09-17 08:41:26.021 Df MachVoice[82563:160a95] [com.augustomklee.MachVoice:AppDelegate] Event tap was disabled, re-checking permissions before re-arming
... AudioCapture "Captured buffer #N" lines continue with no end until the process was killed at 08:44:11 (buffer #1541)
```

Facts read from this run:

1. After the revoke, the tap still delivered the next event: the key-down opened an Utterance.
2. Accessibility requests made by the same process already failed with `-25211` (`apiDisabled`), as the Target capture line shows.
3. macOS disabled the tap on the following event, so the key-up never arrived.
4. The refresh on `tapDisabled` saw no loss, the tap was re-armed, and the Utterance hung, capturing audio for three minutes.

`lldb -p 82563` evaluated inside that revoked process:

| Call | Result |
| --- | --- |
| `AXIsProcessTrusted()` | true (stale) |
| `AXIsProcessTrustedWithOptions(NULL)` | true (stale) |
| `CGPreflightPostEventAccess()` | true (stale) |
| `CGPreflightListenEventAccess()` | true (stale) |
| `AXUIElementCopyAttributeValue(<Dock app>, AXRole)` | -25211 `apiDisabled` (live) |
| `AXUIElementCopyAttributeValue(<Finder app>, AXFocusedUIElement)` | -25211 `apiDisabled` (live) |
| `AXUIElementCopyAttributeValue(<pid 99999>, AXRole)` | -25204, same as a granted process, so not a signal |

The same Dock request from a granted process returned `0` (`AXApplication`) in 32 ms.
This is why `Permissions.accessibilityIsTrustedNow()` confirms a positive `AXIsProcessTrusted()` by asking the Dock for its role.

## 2. Launch without the grant, final build

```
2026-09-17 08:44:49.576 [AppDelegate] Accessibility granted: false
2026-09-17 08:44:49.576 [AppDelegate] Microphone granted: true
```

No tap is installed, as in #8.

## Build and tests

```
$ swift build
Build complete!
$ swift test
✔ Suite GrantLossTests passed
✔ Test run with 27 tests in 6 suites passed
```

Each new `GrantLossTests` assertion was checked against a mutation.
With the key-up on teardown disabled, `uninstallWhileDictationKeyHeldFiresKeyUpOnce` and `escapeAfterUninstallPassesThrough` fail.
With the grant check in `UtteranceController.disposition` disabled, `transcriptWithoutGrantStrandsWithoutInjection` fails.
