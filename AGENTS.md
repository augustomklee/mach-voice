# mach-voice

A local push-to-talk dictation app for macOS.
Hold the Dictation Key, speak, release, and the Transcript appears in whatever application already had the cursor.
Nothing spoken leaves the machine.

`CONTEXT.md` carries the ubiquitous language and is the source of truth for every term.
`docs/adr/` carries the decisions.
This file carries the rules that follow from both.

## Speak the domain language

Every term in `CONTEXT.md` has an `_Avoid_` line listing the words that must not be used for it.
Use **Utterance**, **Dictation Key**, **Target**, **Draft**, **Transcript**, **Injection**, **Abandoned Utterance**, **Stranded Transcript**, **Injection Profile**, **History**, **Retention Window**, **Vocabulary**, **Speech Model**.
Do not write recording, hotkey, partial, insertion, dictionary, or engine in code, comments, commit messages or pull request bodies.

Two of those distinctions are not stylistic and a rename would change behaviour.
**Vocabulary** biases recognition before any text exists, and a dictionary replaces strings afterwards.
They are different mechanisms with different failure modes, and the after-the-fact one is wrong whenever the model's wrong guess is itself a real word.
A **Draft** is uncommitted and a **Transcript** is committed, so anything that persists, injects or enters **History** takes a **Transcript** and never a **Draft**.

## The three invariants

These come from the architecture decision records.
Each one exists to prevent a specific failure, and the failure is named so the rule is not softened by someone who cannot see the reason.

**Never retry an Injection whose read-back was unreadable.**
`docs/adr/0002`.
The Accessibility API returns success in Electron and Chromium applications while silently discarding the text, so the return value proves nothing and the read-back decides.
When the read-back cannot be read at all, the outcome is unknowable, and retrying risks injecting the same **Transcript** twice into the document the speaker was writing.
Strand instead: clipboard, **History**, tell the speaker, and record in the **Injection Profile** that the application cannot be verified so paste is used there from then on.
A **Stranded Transcript** loses nothing and a duplicated one silently corrupts.
A future reader will be tempted to fix the first-**Utterance** strand by retrying, and that is the outcome this design exists to prevent.

**Construct a fresh `SpeechAnalyzer` and `SpeechTranscriber` for every Utterance.**
`docs/adr/0001` and the comment at the top of `SpeechEngine.swift`.
`finalizeAndFinishThroughEndOfInput()` and `cancelAndFinishNow()` finish the analyzer permanently and not merely the current **Utterance**, so a reused analyzer is dead after the first one.
`ModelRetention.processLifetime` is what keeps the model weights resident, so a fresh analyzer per **Utterance** stays cheap.
Reusing the analyzer to save allocation is the wrong optimisation and breaks every **Utterance** after the first.

**Compare left and right modifier flags, never the generic Command flag.**
`docs/adr/0003`.
Right Command is the **Dictation Key** and the event tap consumes it so no other application sees it.
Testing the generic Command flag would open an **Utterance** inside every left-hand Command-S.
If macOS disables the tap for being slow, the key silently reverts to an ordinary Command mid-**Utterance**, so the tap-disabled event must be handled and the tap re-armed.

Recognition sits behind a single-method protocol on purpose, so that `docs/adr/0001` can be revisited for about a day's work.
Do not remove that indirection as unnecessary.

## The environment, probed off the machine

macOS 26.5, build 25F71.
Swift 6.3.2, Xcode 26.5.
`Package.swift` pins swift-tools 6.2, Swift language mode 6, and platform `.macOS(.v26)`.
Three targets: the `MachVoiceKit` library holds every source file, the `MachVoice` executable holds only the entry point and depends on it, and `MachVoiceKitTests` tests `MachVoiceKit` with swift-testing.
The English **Speech Model** is installed and 16 kHz mono is the working audio format.

**This repository builds on macOS and nowhere else.**
`AppKit`, `SwiftUI`, `Speech`, `AVFoundation`, `ApplicationServices` and `CGEventTap` are Darwin-only, so `swift build` fails on the first import anywhere else.
An agent running on this Mac can build, run and demo, and is expected to do all three.
An agent running in a Linux container can do none of them, and must say so plainly rather than report a change as verified.
Compilation, the Accessibility grant and the demo all happen on macOS, and the review gate that decides what merges runs there too.

## Building and running, on the Mac

```
make build      # swift build -c release
make bundle     # assemble build/MachVoice.app
make sign       # codesign; the default target
make run        # sign, relaunch, look for the mic icon in the menu bar
make identity   # print the code-signing hash TCC keys the grant to
```

The bundle identifier and the signing identity together are what macOS attaches the Accessibility grant to.
Changing either one makes macOS treat this as a new application and silently drops the grant.
Both are pinned in the `Makefile` on purpose, so do not change them to make a build succeed.

## What is not built yet

Say so rather than working around it.

`VocabularyManager` persists terms to `vocabulary.json` and its terms never reach the transcriber.
`contextualStrings` appears in no source file, so `docs/adr/0001`'s stated reason for choosing Apple over Parakeet is currently unbacked by code.

The History and Vocabulary menu items in `MachVoiceApp.swift` are `TODO` stubs that print and open nothing.

`InjectionService.attemptAccessibility` returns `nil` when the read-back is unreadable and the caller falls through to paste in the same **Utterance**.
The comment in the file admits this diverges from `docs/adr/0002`, which requires a hard strand there.
The code is what is wrong, not the decision record.

There is a test target, `MachVoiceKitTests`, but no continuous integration.

## Definition of done

A change is done when it builds on the Mac, and when there is evidence it ran from the real entry point rather than from a harness that proves only that the code compiles.
Console output or a screenshot captured from the running app counts.
An assertion that it should work does not.

## Forbidden actions

Do not retry an **Injection** after an unreadable read-back.
Do not reuse a `SpeechAnalyzer` across **Utterances**.
Do not test the generic Command flag in the event tap.
Do not change the bundle identifier or the signing identity.
Do not report a change as built, tested or demonstrated from a Linux container, which cannot do any of the three.
Do not introduce after-the-fact string replacement on a **Transcript** and call it **Vocabulary**.
Do not remove the protocol wrapper around recognition.
