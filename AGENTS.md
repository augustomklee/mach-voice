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

Only the read-back taken after a successful write is unknowable.
A value that cannot be read before any write is a clean failure, because nothing was written and so nothing can be duplicated, and that path still falls through to paste.
`InjectionServiceStrandTests` holds both halves of that distinction, so collapsing either one into the other turns a test red.
An application mach-voice cannot identify has no key in the **Injection Profile**, so a strand there teaches nothing and the next **Utterance** into it can strand again.

**Construct a fresh `SpeechAnalyzer` and `DictationTranscriber` for every Utterance.**
`docs/adr/0001` and the comment at the top of `SpeechEngine.swift`.
`finalizeAndFinishThroughEndOfInput()` and `cancelAndFinishNow()` finish the analyzer permanently and not merely the current **Utterance**, so a reused analyzer is dead after the first one.
`ModelRetention.processLifetime` is what keeps the model weights resident, so a fresh analyzer per **Utterance** stays cheap.
Reusing the analyzer to save allocation is the wrong optimisation and breaks every **Utterance** after the first.

**Compare left and right modifier flags, never the generic Command flag.**
`docs/adr/0003`.
Right Command is the **Dictation Key** and the event tap consumes it so no other application sees it.
Testing the generic Command flag would open an **Utterance** inside every left-hand Command-S.
If macOS disables the tap for being slow, the key silently reverts to an ordinary Command mid-**Utterance**, so the tap-disabled event must be handled and the tap re-armed.

Recognition is meant to sit behind a single-method protocol, so that `docs/adr/0001` can be revisited for about a day's work.
That protocol is not built: no `protocol` is declared anywhere in `Sources/`, and `UtteranceController` holds the concrete `SpeechEngine` class directly.
What stands in for it is `SpeechEngine.makeTranscriber`, the only place the recognition module is constructed, which is why `SpeechModelInstaller` probes the asset inventory through that call instead of naming the module itself.
Keep that single construction site, and do not read the missing protocol as licence to name the module in the callers.

## The environment, probed off the machine

macOS 26.5, build 25F71.
Swift 6.3.2, Xcode 26.5.
`Package.swift` pins swift-tools 6.2, Swift language mode 6, and platform `.macOS(.v26)`.
Three targets: the `MachVoiceKit` library holds every source file the app ships, the `MachVoice` executable holds only the entry point and depends on it, and `MachVoiceKitTests` tests `MachVoiceKit` with swift-testing.
`Tools/` sits outside `Package.swift` and is built by hand.
The English **Speech Model** is installed for `DictationTranscriber` and 16 kHz mono is the working audio format.

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

`Tools/UnverifiableTarget/main.swift` is a fixture **Target** for `docs/adr/0002`, built on its own because it is not in the package:

```
swiftc -O -o /tmp/UnverifiableTarget Tools/UnverifiableTarget/main.swift
```

Its bottom field reads its Accessibility value before a write and not after, which is the unknowable read-back, so running it is the only way to reach the hard strand from the real entry point.
Run the binary bare for a **Target** with no application identity, or wrap it in an `.app` with a `CFBundleIdentifier` to give it one.

## What is not built yet

Say so rather than working around it.

`VocabularyManager` persists terms to `vocabulary.json`, and `SpeechEngine.startAnalysis(vocabulary:)` hands them to `AnalysisContext.contextualStrings[.general]` before every Utterance's `DictationTranscriber` is built, so a term added through `VocabularyManager.add` takes effect on the next Utterance.
`docs/adr/0001` has an update section recording the earlier `SpeechTranscriber` dead end: that module ignores `AnalysisContext` entirely, which is why the module changed.

The Vocabulary window is still not built, so editing `vocabulary.json` directly is the only way to add a term today.
That file is a JSON array of strings at `~/Library/Application Support/MachVoice/vocabulary.json`.
Terms are compared case-sensitively, so `Ibiuna` and `ibiuna` are two separate terms rather than a duplicate.
That path needs the app relaunched, because `VocabularyManager` reads the file once in `init` and nothing re-reads it afterwards.
The History and Vocabulary menu items in `MachVoiceApp.swift` are `TODO` stubs that print and open nothing.

`InjectionService.attemptPaste` reports success unconditionally, because Cmd+V goes to whatever holds keyboard focus and there is nothing to read back afterwards.
Paste therefore always wins the probe, and the keystrokes mechanism is reached only when the **Injection Profile** on disk already names it.
Inside `inject`, an unreadable read-back is the only way a **Transcript** strands.
The other strand is an **Utterance** whose **Target** was never captured, which `UtteranceController` handles before `inject` is called.

The pasteboard carries the `org.nspasteboard.ConcealedType` marker but not the transient one that `docs/adr/0002` and `docs/MVP.md` also name.

There is a test target, `MachVoiceKitTests`, but no continuous integration.

## Definition of done

A change is done when it builds on the Mac, and when there is evidence it ran from the real entry point rather than from a harness that proves only that the code compiles.
Console output or a screenshot captured from the running app counts.
An assertion that it should work does not.

## The gate

`no-mistakes` decides what merges, and it runs on this Mac outside whatever wrote the code.
Do not merge a pull request that has not been through it.

This repository has no `.github/workflows/`, so the ci step never sees a status check register and waits out the full timeout instead of failing.
Pass `--skip=ci` when driving `no-mistakes axi run` here.
`.no-mistakes.yaml` carries the same intent as an `# nm-skill-skip: ci` marker, which the tool ignores and the agent reads.

Demo evidence is committed, in the same commit as the work, under `.no-mistakes/evidence/<branch>/demo/`.
A change that builds and passes its tests but has no capture from the running app has not met the definition of done above.

## Forbidden actions

Do not retry an **Injection** after an unreadable read-back.
Do not reuse a `SpeechAnalyzer` across **Utterances**.
Do not test the generic Command flag in the event tap.
Do not change the bundle identifier or the signing identity.
Do not report a change as built, tested or demonstrated from a Linux container, which cannot do any of the three.
Do not introduce after-the-fact string replacement on a **Transcript** and call it **Vocabulary**.
Do not construct the recognition module anywhere but `SpeechEngine.makeTranscriber`.
