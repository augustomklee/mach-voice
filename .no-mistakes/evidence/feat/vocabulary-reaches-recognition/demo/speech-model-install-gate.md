# Speech Model install gate - demo evidence

Companion to `vocabulary-reaches-recognition.md`, which covers the Vocabulary
path.
This file covers the launch gate in `SpeechModelInstaller`, which that capture
could not show because the installer reported through `print` and so never
reached the app's `os.log` subsystem.
The installer now logs through the same `Logger` every other file uses, so one
capture command covers the whole launch path.

Captured on macOS 26.5 / Xcode 26.5 from the signed bundle's real entry point,
`build/MachVoice.app/Contents/MacOS/MachVoice`, run straight from the terminal.

## The gate short-circuits on an already-installed model

```
$ make sign
Build complete!
build/MachVoice.app: valid on disk
build/MachVoice.app: satisfies its Designated Requirement

$ ./build/MachVoice.app/Contents/MacOS/MachVoice &
$ /usr/bin/log show --predicate 'subsystem == "com.augustomklee.MachVoice"' --last 10m --style compact
2026-09-02 01:24:45.424 Df MachVoice[30197] [com.augustomklee.MachVoice:AppDelegate] Accessibility granted: true
2026-09-02 01:24:45.424 Df MachVoice[30197] [com.augustomklee.MachVoice:AppDelegate] Microphone granted: false
2026-09-02 01:24:45.436 Df MachVoice[30197] [com.augustomklee.MachVoice:EventTap] Event tap installed successfully
2026-09-02 01:24:45.484 Df MachVoice[30197] [com.augustomklee.MachVoice:SpeechModelInstaller] Reserved locale: en_US
2026-09-02 01:24:45.489 Df MachVoice[30197] [com.augustomklee.MachVoice:SpeechModelInstaller] Speech model already available
2026-09-02 01:24:45.560 Df MachVoice[30197] [com.augustomklee.MachVoice:SpeechEngine] Speech model warmed, format=<AVAudioFormat 1 ch, 16000 Hz, Int16>
```

`Speech model already available` is the
`AssetInventory.status(forModules: [DictationTranscriber]) == .installed`
branch.
The gate reaches `.installed`, so `installationState` is `.installed`, the menu
bar icon is `mic.fill` and the menu reads `Ready`.
No download is requested, which is what M3 asks for.

`Microphone granted: false` is an artifact of launching the binary from a
terminal instead of through LaunchServices: the microphone grant is attached to
the terminal in that case, not to the bundle.
The Accessibility grant survives because it is keyed to the bundle identifier
and the signing authority.
Recognition itself is unchanged by this round, so
`vocabulary-reaches-recognition.md` remains the capture for the Utterance path.

## Why the status probe must come after the reservation

`AssetInventory.status(forModules:)` reports `supported` until the locale is
reserved and `installed` afterwards, for both modules.
Probed against the real framework on this machine with throwaway programs built
by `swiftc` against the macOS 26.5 SDK:

```
$ .build/probe/probe3
before reserve  dictation: supported
before reserve  speech:    supported
after reserve   dictation: installed
after reserve   speech:    installed

$ .build/probe/probe2
before reserve: supported
reserve returned: true
reservedLocales: ["en_US"]
after reserve: installed
assetInstallationRequest: non-nil
```

`installIfNeeded()` already reserves before it probes, so the ordering is
correct.
This is what the `Asset status for en_US` row in `docs/MVP.md` now records; the
earlier `supported, not installed` reading came from a probe taken before any
reservation.

Two modules, probed side by side, confirming they keep separate inventories:

```
$ .build/probe/probe
DictationTranscriber en_US status: supported
SpeechTranscriber en_US status:    supported
SpeechTranscriber.isAvailable:     true
DictationTranscriber.installedLocales: ["en_US"]
SpeechTranscriber.installedLocales:    ["en_SG", "en_IE", "en_NZ", "en_GB", "en_ZA", "en_US", "en_CA", "en_AU", "en_IN"]
reservedLocales: []
```

`SpeechTranscriber.isAvailable` is `true` while `DictationTranscriber` has a
single installed locale, so the old `isAvailable` gate said nothing about the
module the analyzer actually runs.

## Build and test evidence

```
$ swift build
Build complete! (1.31s)

$ swift test
◇ Suite VocabularyManagerTests started.
✔ Test addTrimsSurroundingWhitespace() passed after 0.001 seconds.
✔ Test addRejectsEmptyTerm() passed after 0.001 seconds.
✔ Test addRejectsDuplicateTerm() passed after 0.001 seconds.
✔ Test addRejectsDuplicatesCaseSensitively() passed after 0.001 seconds.
✔ Suite VocabularyManagerTests passed after 0.002 seconds.
✔ Test run with 4 tests in 1 suite passed after 0.002 seconds.
```
