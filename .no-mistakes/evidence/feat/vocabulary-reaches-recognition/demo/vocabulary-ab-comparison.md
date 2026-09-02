# Vocabulary reaches recognition - A/B over identical audio

Gate evidence, captured on macOS 26.5 build 25F71, Swift 6.3.2.
It complements the live capture in `vocabulary-reaches-recognition.md`, which was taken by a person holding the Dictation Key.

The live capture shows the term working once.
This one holds every other variable still.
The same audio buffers are fed twice through the same `SpeechEngine`, and the only difference between the two Utterances is the Vocabulary handed to `startAnalysis(vocabulary:)`.
A difference in the Transcript can therefore only have come from the Vocabulary.

## What was exercised

`Tests/MachVoiceKitTests/SpeechEngineVocabularyTests.swift` runs the call sequence `UtteranceController` runs for a held Dictation Key: `startAnalysis(vocabulary:)`, then `analyze(buffer:)` per audio buffer, then `finalize()`.
The microphone is the only substituted part.
Audio is spoken by the system speech synthesiser, converted to the Int16 16 kHz mono format the analyzer demands, and fed one tenth of a second at a time so the analyzer sees it arriving in real time.

Spoken phrase: **"Send it to Ibiuna please"**.
"Ibiuna" is a Portuguese place name the stock en_US Speech Model does not know.

## Result

```
--- Vocabulary reaches recognition ---
analyzer format : 16000.0 Hz, 1 ch, Int16
spoken audio    : "Send it to Ibiuna please" (identical buffers for both Utterances)

Utterance 1, Vocabulary []
  Drafts     : "Send it to" -> "Send it to Ivy" -> "Send it to Ina" -> "Send it to Ina please"
  Transcript : "Send it to Ina please"

Utterance 2, Vocabulary ["Ibiuna"]
  Drafts     : "Send it to" -> "Send it to Ivy" -> "Send it to Ibiuna" -> "Send it to Ibiuna please"
  Transcript : "Send it to Ibiuna please"
--------------------------------------

✔ Test run with 5 tests in 2 suites passed after 5.131 seconds.
```

Without the Vocabulary the Transcript is wrong.
With the term in the Vocabulary the Transcript is right, and the term is already there in the Drafts, which is what the speaker sees in the indicator while the Dictation Key is still held.

## The same run seen from the app's own log

`log stream --predicate 'subsystem == "com.augustomklee.MachVoice" and category == "SpeechEngine"'`

```
Speech model warmed, format=<AVAudioFormat 1 ch, 16000 Hz, Int16>
Analysis started                                    <- Utterance 1, Vocabulary []
Result isFinal=false text=Send
Result isFinal=false text=Send it
Result isFinal=false text=Send it to
Result isFinal=false text=Send it to Ivy
Result isFinal=false text=Send it to Ina
Result isFinal=false text=Send it to Ina please
Result isFinal=true  text=Send it to Ina please
Finalized utterance
Analysis started                                    <- Utterance 2, Vocabulary ["Ibiuna"]
Result isFinal=false text=Send
Result isFinal=false text=Send it
Result isFinal=false text=Send it to
Result isFinal=false text=Send it to Ivy
Result isFinal=false text=Send it to Ibiuna
Result isFinal=false text=Send it to Ibiuna please
Result isFinal=true  text=Send it to Ibiuna please
Finalized utterance
```

The two Utterances diverge at the fifth Draft, which is the point where the biased term is available to the analyzer.
No `Vocabulary not applied` line appears, so `setContext` accepted the `AnalysisContext` both times.

## Repeatability

The comparison was run five times.
The Vocabulary Utterance produced "Ibiuna" every time.
The unbiased Utterance produced "Ina" four times and "Ibiza" once, and never produced "Ibiuna".

## The real app, launched from its own entry point

`make run`, then `log stream --predicate 'subsystem == "com.augustomklee.MachVoice"'`:

```
[AppDelegate]           Accessibility granted: true
[AppDelegate]           Microphone granted: true
[EventTap]              Event tap installed successfully
[SpeechModelInstaller]  Reserved locale: en_US
[SpeechModelInstaller]  Speech model already available
[SpeechEngine]          Speech model warmed, format=<AVAudioFormat 1 ch, 16000 Hz, Int16>
```

This is the `AssetInventory.status(forModules:)` probe added in this change reporting `.installed` for the `DictationTranscriber` inventory, so the launch gate does not report a false install failure and the analyzer warms on the module it will actually recognise with.

`app-running-menu-bar.png` is the menu bar with the app running.
The icon is `mic.slash.fill` even though the log above reports both grants and an installed Speech Model, because `MachVoiceApp` holds a second `Permissions` instance that nothing ever calls `refresh()` on.
That is unrelated to this change and present on the base commit; neither `MachVoiceApp.swift` nor `Permissions.swift` is in this diff.

## Not captured

There is no screenshot of a Transcript landing in a document.
Reaching that surface needs a held Dictation Key and a live microphone, which the gate has no way to drive.
The live capture in `vocabulary-reaches-recognition.md` covers it, and this A/B covers everything downstream of the microphone.
