# Right Command is a dedicated Dictation Key

Right Command is the **Dictation Key**, and the event tap consumes it so that no other application ever sees it.
Push-to-talk means holding the key for the whole **Utterance**, and a live Command modifier turns every other keypress into a shortcut: space becomes Spotlight, Tab becomes the application switcher, and the switcher would move focus off the **Target** while an **Utterance** is in flight.
Swallowing the key removes that entire class of collision rather than trying to filter it.

## Considered options

Passing the modifier through and living with the collisions was rejected because the app-switcher case actively breaks an **Utterance** already in progress.
A non-modifier key such as F13 avoids the problem by construction but is a longer reach for a key held many times a day.
Right Option was the near-miss alternative and remains the obvious fallback if right Command is ever wanted back.

## Consequences

**Right Command no longer works as a Command modifier anywhere on this machine while mach-voice is running.**
Right-hand Command-C and Command-V stop working; left Command is unaffected and keeps every existing shortcut.
This was chosen knowing the right-hand modifier is not used for shortcuts here, and it is the first thing to revisit if that ever changes.

The tap must compare left and right modifier flags rather than the generic Command flag, or left Command would trigger dictation inside every Command-S.
If mach-voice crashes the tap dies with it and the key returns to normal behaviour, which is the correct failure direction.
If it merely hangs, macOS disables the slow tap and the key silently becomes an ordinary Command again mid-**Utterance**, so the tap-disabled event must be handled and the tap re-armed.

## Update: the grant taken away mid-run

The tap exists only while the Accessibility grant holds, and the grant can be taken away while mach-voice keeps running (issue #14).
Observed on macOS 26.5: after the grant is removed, the live tap still delivers the next event, then macOS disables it, so the key-up of a held **Dictation Key** is lost.
`AXIsProcessTrusted()`, `CGPreflightPostEventAccess()` and `CGPreflightListenEventAccess()` all keep returning true in the running process, so none of them can notice the loss.
An Accessibility request answered by another application fails with `apiDisabled` as soon as the grant is gone, and that is the check mach-voice polls for the whole run.

On loss the tap is removed rather than re-armed, which returns Right Command to ordinary Command, the same failure direction as a crash.
An **Utterance** whose **Dictation Key** is held at that moment is closed by the teardown instead of being left live.
Its **Transcript** becomes a **Stranded Transcript** without any **Injection** attempt, because no mechanism works without the grant and paste would still report success.
It is not abandoned: the speaker did not cancel it, and a strand keeps the words on the clipboard and in **History**.
A restored grant installs a fresh tap through the same poll.
