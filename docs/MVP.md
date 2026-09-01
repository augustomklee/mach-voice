# mach-voice MVP

## What you are building

mach-voice is a local push-to-talk dictation app for macOS.
The user holds one key, speaks, and releases it, and the words they said appear in whatever application already had their cursor.
No window switch, no copy and paste, no visiting a dictation app first.
Speech recognition runs entirely on the device and no audio or text ever leaves the machine.

The speech recognition is the easy part and is roughly 15% of this project.
The other 85% is delivering a keystroke and a string across the boundary between two applications without stealing keyboard focus.
macOS guards that boundary, each crossing needs a separate permission the user grants by hand, and the failure mode is silent: the system reports success and discards the text.

Read `CONTEXT.md` before writing any code.
It defines the vocabulary used throughout this document, and terms in **bold** below are defined there.
Read `docs/adr/0001`, `0002`, and `0003` for the reasoning behind the three decisions most likely to look wrong at first glance.

## Verified environment facts

These were measured on the target machine by compiling and running a probe against the real frameworks.
Do not re-derive them and do not assume a different macOS version.

| Fact | Value |
| --- | --- |
| macOS | 26.5 (build 25F71) |
| Hardware | Apple M5, 10 cores, 24 GB |
| Toolchain | Xcode 26.5, Swift 6.3.2 |
| `SpeechTranscriber.isAvailable` | `true` |
| Supported locales | 30 |
| Installed locales | 9 English variants, including `en_US` |
| Reserved locales | none, maximum 5 |
| Asset status for `en_US` | `supported`, not `installed` |
| Best available audio format | 16000 Hz, mono |
| Foundation Models | available (Apple Intelligence is enabled) |
| Codesigning identity | `Apple Development: augusto.leee@gmail.com (X8QN7RE5WN)`, team `VGZMWWL5C4` |

An uninstalled locale reports zero compatible audio formats.
That is expected and is not an error condition.

## Verified API surface

All of the following exist in the macOS 26.5 SDK and were read from the installed `.swiftinterface`, not recalled from memory.

Recognition is driven by `SpeechAnalyzer`, an actor that hosts one or more modules.
Use `SpeechTranscriber` as the module, constructed with `init(locale:preset:)`.

- `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` gives the format to convert microphone input to.
- `prepareToAnalyze(in:)` warms the model. Call it at launch so the first Utterance does not pay the cost.
- `SpeechAnalyzer.Options(priority:modelRetention:)` with `ModelRetention.processLifetime` keeps the model resident between Utterances.
- `SpeechTranscriber.Preset.progressiveTranscription` plus `ReportingOption.volatileResults` and `.fastResults` streams partial results while the user is still speaking.
- `finalizeAndFinishThroughEndOfInput()` closes an Utterance on key release.
- `cancelAndFinishNow()` discards one, for the Escape path.
- Results arrive as an `AsyncSequence` of `SpeechTranscriber.Result`, whose `text` is an `AttributedString`.
- `AnalysisContext.contextualStrings[.general]` carries the **Vocabulary**.
- `AssetInventory.reserve(locale:)`, `AssetInventory.status(forModules:)` and `assetInstallationRequest(supporting:)` handle model installation, and `AssetInstallationRequest` exposes a `Progress` plus `downloadAndInstall()`.

`SpeechDetector` also exists for voice activity detection.
It is out of scope for the MVP but is the natural tool if silence trimming is wanted later.

## Scope

### In

1. Signed menu bar application with a working permissions flow.
2. Right Command as the **Dictation Key**, consumed so no other application sees it.
3. `en_US` **Speech Model** reservation and installation, with a real first run state.
4. Audio capture through recognition to a **Transcript**, with **Draft** results streaming during speech.
5. A minimal, non-activating recording indicator.
6. **Injection** with read-back verification, the **Injection Profile**, and the **Stranded Transcript** path.
7. **History**, durable, with the 30 day **Retention Window**.
8. **Vocabulary** as an editable list fed to the analyzer before recognition.

### Out, for a later version

- The cleanup pass that removes filler words using Foundation Models.
  It is available but it must run before Injection, so it spends time in the only window the user feels.
  Build it later behind a toggle, defaulted off, and measure it against a no cleanup baseline.
- An animated waveform. A simple recording indicator is enough for the MVP.
- Launch at login. Trivial to add and not needed to prove the app works.
- Any language other than English.

## Milestones

Work in this order.
The unglamorous parts come first because they are what kill projects like this, and the pleasant parts come last.

### M1. Signed app shell that keeps its permissions

Menu bar only application, no Dock icon, stable bundle identifier, signed with the Apple Development identity above.
Info.plist needs `LSUIElement`, `NSMicrophoneUsageDescription`, and `LSMinimumSystemVersion` of 26.0.
Show the live state of the Accessibility and Microphone grants in the menu, and offer a button that opens the Accessibility pane.

**Acceptance:** grant Accessibility, then rebuild the app twice from clean, and confirm the grant is still in effect without re-granting it.

A note on this, because the folklore is misleading.
People often report that rebuilding breaks the permission grant.
That is true for ad-hoc signed or unsigned builds, where the Designated Requirement embeds the code hash and the hash changes on every build.
With a real signing certificate the Designated Requirement is the bundle identifier plus the signing authority, and the binary can change underneath it freely.
Verify this early with `codesign -d -r- <app>` across two clean builds and confirm the `designated =>` line is byte for byte identical.
If it is identical, this milestone is much smaller than it looks.
Never fall back to ad-hoc signing to work around a problem here.

### M2. Global push-to-talk

Install a `CGEventTap` that observes modifier changes and detects right Command specifically.

**Acceptance:** holding right Command logs a press and a release, left Command does nothing, and pressing right Command plus any other key does not trigger a system shortcut.

Three things this milestone must get right:

- Compare the left and right modifier flags, not the generic Command flag.
  Using the generic flag means every Command-S in every app starts dictation.
- Consume the event so the key never reaches another application.
  If Command stays live for the duration of an Utterance, then space becomes Spotlight and Tab becomes the application switcher, and the switcher moves focus off the **Target** while an Utterance is in flight.
- Do no work inside the tap callback beyond posting a signal.
  macOS disables taps whose handler is slow, and when that happens dictation dies silently and right Command reverts to being an ordinary Command key.
  Listen for the tap-disabled event and re-arm.

### M3. Speech Model installation

Reserve `en_US`, check status, request installation, and show progress.
Handle the already-installed case without a spurious download.

**Acceptance:** on a machine with nothing reserved, the app installs the model on first launch with visible progress, and on second launch it starts immediately.

### M4. Audio to Transcript

Capture from `AVAudioEngine`, convert to 16000 Hz mono, stream into the analyzer, and print **Draft** and final results to the console.
No injection yet and no UI beyond what already exists.

**Acceptance:** holding the key and speaking prints streaming Drafts, and releasing prints one final **Transcript**.

Keep roughly 300 ms of audio in a ring buffer before the keypress and prepend it.
Without that the first syllable is clipped and the user gets "esting, one two" instead of "testing, one two".

### M5. Verified Injection

This is the actual project.
Budget more time here than for M4.

Injection consults the **Target** application's **Injection Profile** first.
If a mechanism is already known for that application, use it.
Otherwise write through the Accessibility API and read the field back to find out what happened.

Read-back has three outcomes, not two:

| Outcome | Meaning | Action |
| --- | --- | --- |
| The text is there | It landed | Done. Profile learns Accessibility. |
| The text is absent | A clean, honest failure | Retry with paste. Profile learns paste. |
| Nothing is readable | Unknowable: it may or may not have landed | Strand it. Profile learns paste. Never retry. |

The third outcome is the whole point.
The Accessibility API returns a success code in Electron and Chromium applications while silently discarding the text, so the return value is not evidence and the read-back decides.
Some applications also expose no readable value at all, which makes the question unanswerable.
Retrying there risks injecting the same text twice, and duplicated text silently corrupts the document the user was writing.
A **Stranded Transcript** loses nothing, because it goes to the clipboard and to **History** and the user is told.
One failure mode is recoverable and the other is not, so the recoverable one wins.

Paste is the ordinary path rather than a fallback, because Electron applications are both the most common place people type and the ones that fail verification.
Mark the pasteboard concealed and transient so clipboard managers do not record every **Transcript**, then restore the user's previous clipboard contents afterwards.
That flag is an advisory convention rather than an enforced guarantee, and that is accepted.

**Acceptance:** dictate successfully into a native app such as TextEdit, an Electron app such as Slack or VS Code, a terminal, and a browser text field.
Log which mechanism won for each.
Confirm that no application ever receives the same Transcript twice.

### M6. Indicator, History and Vocabulary

The recording indicator must be a non-activating panel that never becomes the key window.
If it takes focus then mach-voice itself becomes the **Target** and the Injection goes into the indicator.
It should join all Spaces and appear over full screen apps.

**History** is durable, holds every Transcript whether or not Injection succeeded, and purges anything older than 30 days.
It is the recovery path for a **Stranded Transcript** first and a browsing convenience second.

**Vocabulary** is a single global list fed to `AnalysisContext.contextualStrings` before recognition runs.

**Acceptance:** adding a term to Vocabulary makes it transcribe correctly on the next Utterance, the indicator never steals focus, and a Transcript older than the window disappears from History.

## Guardrails

These all look like bugs and are all deliberate.
Do not "fix" them.

1. **The first Utterance into a never-seen application may be stranded.**
   That is the probe that teaches the **Injection Profile**.
   It happens at most once per application.
   Retrying on an inconclusive verify reintroduces double injection, which is the outcome the whole design exists to prevent.
2. **Right Command stops working as a Command modifier.**
   That is intentional and the user chose it knowingly.
   Left Command is unaffected.
3. **Vocabulary biases recognition before any text exists.**
   Do not implement it as find and replace on a finished Transcript.
   Post-hoc replacement corrupts cases where the wrong guess is itself a real word.
4. **The Target is captured at key-down and never re-read.**
   Focus can move while the user is speaking.
5. **Injection replaces the Target's selected text** rather than inserting alongside it.
   This is what makes re-dictating a selected sentence work, and all three mechanisms do it for free.
6. **A key tap under about 250 ms with no speech is an Abandoned Utterance.**
   It produces no Transcript, writes nothing to History, and injects nothing.
   The same applies to Escape pressed mid-Utterance.
7. **Never use ad-hoc signing** and never change the bundle identifier.
   Both are what the permission grants attach to.

## Risks

| Risk | Mitigation |
| --- | --- |
| Some application resists all three injection mechanisms | Keep a per-application override in the Injection Profile so paste can be forced, and accept a short blocklist |
| The event tap is disabled under load and dictation dies silently | Do no work in the tap callback, listen for the tap-disabled event, and re-arm |
| Recognition accuracy on project-specific jargon | Vocabulary in M6, which biases at the source |
| A badly-behaved clipboard manager retains Transcripts past the Retention Window | Accepted for a personal tool on a single trusted machine. Revisit if this is ever distributed |
| Scope creep into notes, summaries and voice commands | Ship M1 to M5, use it for a week, then decide what is actually missing |

## Existing state of the repository

`CONTEXT.md` and `docs/adr/0001` through `0003` are complete and authoritative.

There is also an untested scaffold from an earlier session: `Package.swift`, a `Makefile` that assembles and signs the bundle, `Resources/Info.plist`, and two files under `Sources/MachVoice/` covering the menu bar shell and permission checks.
It compiles and signs, but only M1 is even partially represented and none of it is verified.
Treat it as a starting point to check rather than as working code, and replace it freely.

One detail from it worth keeping: `kAXTrustedCheckOptionPrompt` is a mutable C global that Swift 6 strict concurrency rejects.
Use the literal string `"AXTrustedCheckOptionPrompt"` instead of silencing the check.

The project is built with Swift Package Manager plus a Makefile rather than an Xcode project, so the build is reproducible and the project definition is diffable text.
The package still opens in Xcode normally.
