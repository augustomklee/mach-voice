# Escape swallowed globally while MachVoice runs - demo evidence

Captured on macOS 26.5 / Xcode 26.5 from the signed bundle's real entry point
(`make run`, `build/MachVoice.app`). This tap-level bug has no visible UI, so
the evidence is the actual effect on the system event stream rather than a
screenshot: a second, independent process (`listen`, a listen-only
`CGEventTap` placed `tailAppendEventTap`, downstream of MachVoice's own tap)
either does or does not see a synthetic Escape `keyDown`, and `log show
--predicate 'subsystem == "com.augustomklee.MachVoice"'` for MachVoice's own
side. Process ids and the subsystem prefix are trimmed from log lines below;
nothing else is edited.

## How the Utterances were driven

`Tools/` already builds a standalone fixture outside the package for ADR-0002
demos; the same idea is used here. Two throwaway command-line tools, not part
of `MachVoiceKit`:

- `listen` - a listen-only session tap at `tailAppendEventTap` that logs every
  `keyDown` it is handed. Since a consuming `headInsertEventTap` (MachVoice's)
  removes an event from the stream before any downstream tap sees it, this
  process observing (or not observing) `keyCode=53` is a direct, non-visual
  read of whether MachVoice let Escape through.
- `simulate_utterance` - posts a `flagsChanged` event carrying the Right
  Command device flag (`0x10`, not the generic Command mask - the ADR-0003
  distinction), then an Escape `keyDown`/`keyUp`, then releases Right Command.

Neither tool touches MachVoice; both talk to the same session event stream a
real keyboard would.

## 1. Before the fix: Escape swallowed even when no Utterance is in progress

MachVoice built at `47fdeac` (pre-fix), running and idle - Dictation Key never
held.

```
$ /tmp/escape-repro/listen &        # armed, tailAppendEventTap
$ osascript -e 'tell application "System Events" to key code 53'
$ cat listen.log
listener armed
```

No `OBSERVED` line at all: the synthetic Escape never reached the downstream
tap. Control - kill MachVoice and send the identical Escape again:

```
$ pkill -x MachVoice
$ osascript -e 'tell application "System Events" to key code 53'
$ cat listen.log
listener armed
OBSERVED keyDown keyCode=53
```

Same event, same listener, only difference is whether MachVoice's tap is
alive. This is `Sources/MachVoiceKit/EventTap.swift:125-135` before the fix:
`handleKeyDown` returns `true` for keycode 53 unconditionally, with no check
of `rightCommandWasDown` or any other state.

## 2. After the fix: Escape passes through when idle

Same build with the fix applied (`handleKeyDown` gates the Escape branch on
`rightCommandWasDown`), MachVoice running and idle.

```
$ /tmp/escape-repro/listen &
$ /tmp/escape-repro/just_escape     # posts a bare synthetic Escape keyDown/keyUp
posted bare escape down/up
$ cat listen.log
listener armed
OBSERVED keyDown keyCode=53
```

Escape now reaches the downstream tap while MachVoice is alive and idle -
exactly the reported bug, fixed.

## 3. After the fix: Escape still cancels an Utterance, and is still consumed, while the Dictation Key is held

Same build, `simulate_utterance` holds the (real, right-specific) Right
Command flag before sending Escape:

```
$ /tmp/escape-repro/listen &
$ /tmp/escape-repro/simulate_utterance
2026-09-17T00:00:02.833Z posting rightCommandDown
2026-09-17T00:00:03.868Z posting escapeDown (rightCommandWasDown should be true in EventTap by now)
2026-09-17T00:00:05.177Z posting rightCommandUp
2026-09-17T00:00:05.177Z done
$ cat listen.log
listener armed
```

No `OBSERVED` line during the whole sequence: Escape is still consumed while
the Dictation Key is held, so it still never reaches another application.
MachVoice's own log for the same run:

```
2026-09-16 21:00:02.870 [EventTap] Right Command pressed
2026-09-16 21:00:02.870 [UtteranceController] Utterance started, target bundleID=com.github.wez.wezterm
2026-09-16 21:00:03.894 [UtteranceController] Utterance cancelled
2026-09-16 21:00:05.203 [EventTap] Right Command released
2026-09-16 21:00:05.204 [UtteranceController] Utterance ended
```

`Utterance cancelled` lands right after the simulated Escape post, matching
`docs/MVP.md` #6 ("Escape pressed mid-Utterance" -> Abandoned Utterance).

`Utterance ended` also fires later, at Right Command release - `EventTap`
calls `onKeyUp` unconditionally on release regardless of an earlier cancel.
That double call is pre-existing (`UtteranceController.cancelUtterance` and
`.endUtterance` were already both reachable for the same Utterance before this
fix, whenever Escape preceded a key-up) and is unrelated to the Escape-swallow
bug this change fixes, so it is left alone here.

## Build and tests

```
$ swift build -c release
Build complete!

$ swift test --filter EventTapDecisionTests
✔ Test escapeWithRightCommandNeverPressedPassesThrough() passed
✔ Test rightCommandDownThenEscapeConsumesAndFires() passed
✔ Test rightCommandDownThenUpThenEscapePassesThrough() passed
✔ Test nonEscapeKeyWithRightCommandDownPassesThrough() passed
✔ Test leftCommandNeverActsAsTheDictationKey() passed
✔ Test run with 5 tests in 1 suite passed

$ swift test
✔ Test run with 16 tests in 4 suites passed
```

Red check: with `handleKeyDown`'s `keyCode == 53` branch reverted to drop the
`&& rightCommandWasDown` guard (the pre-fix behavior), both tests that require
Escape to pass through fail:

```
✘ Test escapeWithRightCommandNeverPressedPassesThrough() recorded an issue:
  Expectation failed: !(consumed → <not evaluated>)
  Escape must reach the frontmost application when no Utterance is in progress
✘ Test rightCommandDownThenUpThenEscapePassesThrough() recorded an issue:
  Expectation failed: !(consumed → <not evaluated>)
  Escape must reach the frontmost application once the Dictation Key is released
```

So the tests are what hold the gate in place.

## Spec

This closes [#10](https://github.com/augustomklee/mach-voice/issues/10), whose
Implementation Decisions this change follows: `handleFlagsChanged`,
`handleKeyDown` and the four closure properties widen from `private` to
`internal` rather than a new pure decision type, and the dormant `KeyEvent`
enum is left untouched. `CONTEXT.md`'s Abandoned Utterance entry gained the
two sentences the issue asked for, describing Escape's behavior in both
states. The follow-up in [#11](https://github.com/augustomklee/mach-voice/issues/11)
(release-after-Escape calling `endUtterance` on an already-abandoned
Utterance) is out of scope here, per the issue's own Out of Scope section.
