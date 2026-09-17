# Accessibility grant taken away mid-run - demo evidence

Captured on macOS 26.5 / Xcode 26.5 from the signed bundle (`make run`, `build/MachVoice.app`).
Logs come from `/usr/bin/log stream --style compact --predicate 'subsystem == "com.augustomklee.MachVoice"'`.

## Correction: `tccutil reset` does not revoke an already-running process

This evidence file originally claimed `tccutil reset Accessibility` revokes the
grant on macOS 26.5, based on a *freshly launched* process reporting
`Accessibility granted: false` right after the reset. That part is true, and
is why section 2 below still uses it: a fresh process reads the TCC database
row directly, and the reset clears that row.

It does not follow for an *already-running* process with an established
grant, and this was checked directly rather than assumed. With MachVoice
running and granted, `tccutil reset Accessibility com.augustomklee.MachVoice`
was run, and three minutes later `lldb -p <pid>` evaluated inside that same
process:

```
(lldb) expr -l objc++ -- int result = 0; { void *elem = (void*)AXUIElementCreateApplication(<Dock pid>); void *role = 0; result = (int)AXUIElementCopyAttributeValue((AXUIElementRef)elem, (CFStringRef)@"AXRole", (CFTypeRef*)&role); } result
(int) $0 = 0
```

`0` is `kAXErrorSuccess` - the exact probe `Permissions.accessibilityIsTrustedNow()`
uses to unmask a stale `AXIsProcessTrusted()` returned a live success, not
`apiDisabled`, a full three minutes after the reset. `tccutil reset` clears
the stored decision for the *next* launch; it does not tear down a session an
already-running, already-trusted process is holding. Section 1's capture,
which did see `apiDisabled` quickly after a revoke, was against a build from
*before* this fix existed and cannot have been probing the same code path -
what it demonstrates correctly is macOS's own tap-disable behavior, not this
detection mechanism.

The live demo in sections 3-4 below therefore uses the real revoke path the
issue itself names: toggling Accessibility off for MachVoice by hand in
System Settings, which does tear down an already-running process's access.

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

## 3. Live: Accessibility revoked by hand while the app keeps running

Same process (pid 89000) the whole time, launched idle, granted through
System Settings, tap came up on its own (issue #8's poll), Right Command
held, then Accessibility turned off by hand in System Settings while the app
kept running.

```
2026-09-17 09:21:20.282 [EventTap] Event tap installed successfully
2026-09-17 09:21:20.282 [AppDelegate] Accessibility granted: true
2026-09-17 09:21:36.586 [EventTap] Right Command pressed
...
2026-09-17 09:21:59.326 [EventTap] Right Command released
2026-09-17 09:22:02.256 [AppDelegate] Accessibility grant lost, removing the event tap
2026-09-17 09:22:02.256 [EventTap] Event tap uninstalled
2026-09-17 09:22:02.256 [AppDelegate] Accessibility granted: false
```

The Utterance had no words this time and ended normally on its own before
the revoke was noticed - not the case this issue is really about - but the
poll caught the grant loss independently a few seconds later, with no tap
event and no interaction with MachVoice needed, and tore the tap down.

## 4. Live: Accessibility granted back, no relaunch, real dictation works

Same process, still running, Accessibility turned back on by hand:

```
2026-09-17 09:26:00.275 [EventTap] Event tap installed successfully
2026-09-17 09:26:00.275 [AppDelegate] Accessibility granted: true
```

Then a real Dictation Key hold with spoken audio (`say`), same process, same
launch, after already having cycled through one full revoke:

```
2026-09-17 09:26:23.724 [EventTap] Right Command pressed
2026-09-17 09:26:32.662 [AppDelegate] Draft: The
...
2026-09-17 09:26:43.397 [AppDelegate] Draft: The quick brown fox just over the lazy dog the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog
2026-09-17 09:26:46.194 [AppDelegate] Transcript: The quick brown fox just over the lazy dog the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog
```

Full Draft -> Transcript cycle, confirming the app is left in a working state
after a revoke-then-regrant cycle, not just that the log lines appear.

## 5. What was not live-verified: an Utterance forcibly closed mid-revoke

The issue's Definition of Done also asks what happens to an Utterance still
open at the exact moment the grant is pulled. Two attempts were made to force
this live: holding a synthetic Right Command (`rcmd down`) with `say` playing
continuously, then revoking by hand mid-hold. Both times the synthetic hold
was released within ~2 seconds of asking for the revoke - not by our code,
but because authenticating the System Settings toggle involves real keyboard
activity, and a real `flagsChanged` event from actual hardware reports the
true state (Right Command genuinely up) and overwrites a synthetic-only hold.
This is a limitation of the test tooling, not a signal about the app.

This path is covered by `GrantLossTests` instead (`uninstallWhileDictationKeyHeldFiresKeyUpOnce`,
`escapeAfterUninstallPassesThrough`, `transcriptWithoutGrantStrandsWithoutInjection`),
each checked against a mutation per the note below. The repository owner
judged forcing a live reproduction of this specific race not worth pursuing
further - it requires either a second person, Touch ID instead of a typed
password for the System Settings prompt, or a real physical Right-Command
hold synchronized with the toggle, and the scenario itself (losing
Accessibility in the exact instant a Dictation Key is held) is rare enough
that the unit coverage was accepted as sufficient without a live capture.

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
