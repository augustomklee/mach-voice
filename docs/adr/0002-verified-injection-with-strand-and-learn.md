# Verified Injection, stranding once per application

**Injection** tries the Accessibility API first, verifies the write actually landed by reading the field back, and falls through to a concealed clipboard paste and then to synthetic unicode keystrokes.
The Accessibility API returns a success code in Electron and Chromium applications while silently discarding the text, so the return value cannot be trusted and the read-back is what decides.

When the read-back is inconclusive, because the application exposes no readable value in either direction, mach-voice does **not** retry inside that **Utterance**.
It strands the **Transcript** instead, records that the application cannot be verified in its **Injection Profile**, and uses paste there from then on.

## Why stranding beats retrying

Retrying an unverifiable write risks injecting the same text twice.
A **Stranded Transcript** loses nothing, because it goes to the clipboard and to **History** and the speaker is told.
Duplicated text silently corrupts the document the speaker was writing and may not be noticed at all.
Given one failure mode is recoverable and the other is not, the recoverable one wins.

## Consequences

**The first Utterance into a never-seen application may be stranded, and this is deliberate.**
It is the probe that teaches the **Injection Profile**, it happens at most once per application, and every later **Utterance** there goes straight to a mechanism known to work.
A future reader will be tempted to "fix" this by retrying on an inconclusive verify.
That reintroduces double-injection, which is the outcome this design exists to prevent.

Because Electron applications are both common and unverifiable, paste is the ordinary path rather than a rare fallback.
Every **Transcript** therefore passes through the system clipboard, so the pasteboard is marked concealed and transient to ask clipboard managers not to record it, and the previous clipboard contents are restored afterwards.
That flag is an advisory convention, not an enforced guarantee: a badly-behaved clipboard manager can still retain **Transcript** text past the **Retention Window**.
This is accepted for a personal tool on a single trusted machine, and it would need revisiting if mach-voice were ever distributed.
