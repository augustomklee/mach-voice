# Vocabulary reaches recognition - demo evidence

Captured from the running app (`make run`, real entry point) via
`log stream --predicate 'subsystem == "com.augustomklee.MachVoice"'` while a
person held the Dictation Key and spoke, on macOS 26.5 / Xcode 26.5.

Term under test: **"Ibiuna"** (Portuguese word, misheard by the stock English
Speech Model). vocabulary.json lives at
`~/Library/Application Support/MachVoice/vocabulary.json` and is only read at
launch, so each vocabulary.json edit below was followed by `make run` before
the next Utterance.

## 1. Baseline, before any code changes (empty Vocabulary, `SpeechTranscriber`)

vocabulary.json: `[]`

```
2026-09-02 00:32:25.850 [EventTap] Right Command pressed
2026-09-02 00:32:25.891 [SpeechEngine] Analysis started
2026-09-02 00:32:28.760 [SpeechEngine] Result isFinal=true text=Ibuna.
2026-09-02 00:32:28.760 [AppDelegate] Transcript: Ibuna.
```

Wrong: "Ibuna." instead of "Ibiuna."

## 2. First wiring attempt: contextualStrings on SpeechTranscriber (did not help)

`AnalysisContext.contextualStrings[.general]` was wired into `SpeechEngine`
exactly as specified, still using `SpeechTranscriber`. vocabulary.json:
`["Ibiuna"]`. Result stayed wrong across three separate Utterances:

```
Transcript: Ebuna.
Transcript:  Ibi, you know?  /  If you know.  /  I'll be you.   (multi-segment hold)
Transcript: Iona.
```

Investigation: Apple's own documentation for `AnalysisContext.contextualStrings`
states this property only takes effect "With the DictationTranscriber module".
`SpeechTranscriber`'s doc page lists no Vocabulary-related API at all. So the
literal instruction compiled and ran but could not change recognition, because
the module in use silently ignores `AnalysisContext`.

## 3. Fix: swap `SpeechTranscriber` for `DictationTranscriber` (`.progressiveShortDictation`)

### 3a. Fresh baseline confirms the failure still exists on the new module

vocabulary.json: `[]`

```
2026-09-02 00:50:59.139 [EventTap] Right Command pressed
2026-09-02 00:50:59.179 [SpeechEngine] Analysis started
2026-09-02 00:51:01.081 [SpeechEngine] Result isFinal=false text=Buna
2026-09-02 00:51:02.852 [SpeechEngine] Result isFinal=true text=Buna
2026-09-02 00:51:02.852 [AppDelegate] Transcript: Buna
```

Wrong: "Buna" instead of "Ibiuna".

### 3b. "Ibiuna" added to vocabulary.json, app relaunched, same word spoken again

vocabulary.json: `["Ibiuna"]`

```
2026-09-02 00:51:39.617 [EventTap] Right Command pressed
2026-09-02 00:51:39.674 [SpeechEngine] Analysis started
2026-09-02 00:51:41.295 [SpeechEngine] Result isFinal=false text=Ibi
2026-09-02 00:51:41.832 [SpeechEngine] Result isFinal=false text=Ibiuna
2026-09-02 00:51:42.659 [SpeechEngine] Result isFinal=true text=Ibiuna
2026-09-02 00:51:42.660 [AppDelegate] Transcript: Ibiuna
2026-09-02 00:51:42.660 [InjectionService] inject: used preferred mechanism paste
```

Correct: "Ibiuna", transcribed and injected, on the very next Utterance after
the term was added to the Vocabulary. No caching or refresh mechanism was
added; the app only ever had one process launch's worth of `VocabularyManager`
state, read at `SpeechEngine.startAnalysis(vocabulary:)` construction time for
that Utterance's fresh `SpeechAnalyzer`/`DictationTranscriber` pair.

## Build and test evidence

```
$ swift build
Build complete!

$ swift test
◇ Suite VocabularyManagerTests started.
✔ Test addRejectsEmptyTerm() passed
✔ Test addRejectsDuplicateTerm() passed
✔ Test addTrimsSurroundingWhitespace() passed
✔ Test addRejectsDuplicatesCaseSensitively() passed
✔ Suite VocabularyManagerTests passed after 0.002 seconds.
✔ Test run with 4 tests in 1 suite passed after 0.002 seconds.
```
