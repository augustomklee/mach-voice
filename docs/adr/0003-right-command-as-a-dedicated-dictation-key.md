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
