# Permissions never update on their own - demo evidence

Captured on macOS 26.5 / Xcode 26.5 from the signed bundle's real entry point
(`make sign`, `build/MachVoice.app`), following exactly the sequence in issue
#8's own Definition of Done: revoke Accessibility, launch, grant Accessibility
while the app keeps running, dictate successfully, with no relaunch and no
interaction beyond the System Settings toggle itself. `log stream --predicate
'subsystem == "com.augustomklee.MachVoice"'` for the whole run. All lines
below come from one process, PID 79379, from launch through the injected
Transcript - it was never quit or relaunched.

Toggling Accessibility itself needed a human hand, since the grant has no API
and no system prompt (that is the whole premise of the issue). `tccutil reset
Accessibility com.augustomklee.MachVoice` did not actually clear the grant on
this macOS version (`AXIsProcessTrusted()` kept returning `true` afterward),
so the revoke and the later re-grant were both done by hand in System
Settings > Privacy & Security > Accessibility, with the app left running
throughout.

## 1. Before the fix, for reference: same repro, `47fdeac` (pre-issue-#10-fix
baseline shares this app code) - `AppDelegate.installEventTap()` only ever
runs once, at `applicationDidFinishLaunching`, so a grant arriving later was
never retried and the person had to relaunch. Not re-captured here since the
demo below already shows the fixed code path end to end; the absence of any
retry mechanism is Finding F4 from the grill session (`grepped: no Timer,
NotificationCenter, addObserver, didBecomeActive`) and Finding F2 (the
`self.eventTap = tap` assignment ordering bug that made a second attempt a
permanent no-op even if one had existed).

## 2. Launch with Accessibility already revoked

```
2026-09-17 08:15:41.802 [AppDelegate] Accessibility granted: false
2026-09-17 08:15:41.802 [AppDelegate] Microphone granted: true
2026-09-17 08:15:41.851 [SpeechModelInstaller] Reserved locale: en_US
2026-09-17 08:15:41.856 [SpeechModelInstaller] Speech model already available
2026-09-17 08:15:41.929 [SpeechEngine] Speech model warmed, format=...
```

No `Event tap installed successfully` line - `installEventTap()`'s new guard
(`Sources/MachVoiceKit/MachVoiceApp.swift`) declines to even attempt
`CGEvent.tapCreate` while `permissions.accessibility.isGranted` is false,
rather than trying and failing every poll tick.

## 3. Accessibility granted back, app never quit or relaunched

```
2026-09-17 08:16:17.835 [EventTap] Event tap installed successfully
```

36 seconds after launch (the time it took to walk through System Settings),
with zero interaction with MachVoice itself - no menu opened, no button
clicked. `AppDelegate`'s 2-second poll timer (`startPermissionsPollingIfNeeded`
/ `pollPermissions`) noticed the grant on its own and `Permissions.onRefresh`
fired `installEventTap()`, which this time kept the tap because
`tap.isInstalled` was true.

## 4. Dictation works immediately, same process, same launch

Right Command held in Firefox's address bar, "test test test" spoken, released:

```
2026-09-17 08:19:42.341 [EventTap] Right Command pressed
2026-09-17 08:19:42.357 [UtteranceController] Utterance started, target bundleID=org.mozilla.firefox
2026-09-17 08:19:42.376 [SpeechEngine] Analysis started
2026-09-17 08:19:43.956 [AppDelegate] Draft: Test
2026-09-17 08:19:44.530 [AppDelegate] Draft: Test test
2026-09-17 08:19:44.726 [AppDelegate] Draft: Test test test
2026-09-17 08:19:44.764 [EventTap] Right Command released
2026-09-17 08:19:44.764 [UtteranceController] Utterance ended
2026-09-17 08:19:44.865 [AppDelegate] Transcript: Test test test
2026-09-17 08:19:44.865 [InjectionService] inject: appID=org.mozilla.firefox preferred=Optional(MachVoiceKit.InjectionMechanism.paste) hasFocusedElement=true
2026-09-17 08:19:44.872 [InjectionService] inject: delivered with paste
2026-09-17 08:19:44.872 [UtteranceController] Injected via paste
```

Full Utterance -> Draft -> Transcript -> Injection cycle, on the very first
Dictation Key hold after the grant arrived. This is the issue's Definition of
Done, met without a relaunch.

## Build and tests

```
$ swift build
Build complete!

$ swift test
✔ Test freshEventTapIsNotInstalled() passed
✔ Test onRefreshFiresOnEveryCall() passed
✔ Test refreshInvokesOnRefreshCallback() passed
✔ Suite PermissionsRefreshTests passed
✔ Test run with 19 tests in 5 suites passed
```

`PermissionsRefreshTests` covers the two new seams directly: `Permissions`
fires `onRefresh` after every `refresh()` call, whatever triggered it, and a
freshly constructed `EventTap` reports `isInstalled == false` before
`install()` runs. `AppDelegate`'s own timer and retry wiring is not unit
tested - it is thin glue over real system APIs (`AXIsProcessTrusted`,
`CGEvent.tapCreate`, `Timer`) with no seam worth building for this change, and
is what sections 2-4 above verify live instead.

## Spec

This closes [#8](https://github.com/augustomklee/mach-voice/issues/8), whose
Implementation Decisions came out of a `grill-with-docs` session
(`.lavish/permissions-event-tap-grill.html`, not committed - `.lavish/` is
gitignored):

- A 2-second timer polls `AXIsProcessTrusted()` while any grant is missing and
  stops once `allGranted`, since mach-voice has no window, no Dock icon, and
  no activation-notification moment to piggyback on instead (F4, F7).
- Exactly one `Permissions` instance now exists, owned by `MachVoiceApp` as
  `@State` and injected into `AppDelegate` the same way `modelInstaller`
  already was (F5), fixing the two-instance bug (F1) that left the menu bar
  icon stale until a manual re-check.
- No new UI: the existing menu bar icon, "Re-check permissions" item, and
  "Open Accessibility settings…" button are the whole surface. A real
  first-run window is separate issue #9's territory.
- `installEventTap()` retries naturally off `Permissions.onRefresh`, fired
  after every refresh regardless of source (the timer, the manual button, or
  `requestMicrophone()`), rather than a separate one-time "first grant"
  edge-detection path.
- Noticing a later *revoke* (Accessibility pulled back mid-run) is explicitly
  out of scope: the issue's own title and demo are both about a grant
  arriving, not being taken away, and handling a revoke mid-Utterance is a
  materially different, bigger question. Filed as a candidate follow-up if it
  turns out to matter.
