# Apple Speech framework for recognition

The module is `DictationTranscriber`.
This record was written for `SpeechTranscriber`, and the update section at the end records why the module changed.

mach-voice uses the Speech framework's on-device recognition rather than a downloaded model such as Parakeet or Whisper.
It runs entirely on the machine, costs nothing, needs no third-party runtime, and supports biasing recognition with a **Vocabulary** before any text exists, which is the mechanism this project relies on to get project-specific words right.
Verified available on this machine, with the English **Speech Model** already present and 16 kHz mono as the working audio format.

## Considered options

Parakeet via Hugging Face was the alternative, and it is the one a reader is most likely to suggest again.
It is a credible engine and may well beat Apple on raw English accuracy.
It was rejected because it adds a model download, a runtime, and a second thing to keep working, in exchange for an accuracy difference that this project can close more cheaply through **Vocabulary**.

## Consequences

Swapping the recognition module has to stay about a day's work rather than a rewrite, so that this decision can be revisited cheaply.
The single-method protocol meant to hold that seam is not built: `SpeechEngine` is a concrete class and `UtteranceController` holds it directly.
What keeps the cost low today is `SpeechEngine.makeTranscriber`, the only place the module is constructed, which `SpeechModelInstaller` also probes the asset inventory through rather than naming the module itself.
Adding the protocol is still worth doing, and until it exists that one construction site is what this consequence rests on.

## Update: DictationTranscriber, not SpeechTranscriber

The Vocabulary-closes-the-gap claim above assumed `SpeechTranscriber`, the module `SpeechEngine` built until the Vocabulary was wired to recognition.
Apple's own documentation scopes `AnalysisContext.contextualStrings` to `DictationTranscriber` only; `SpeechTranscriber` exposes no Vocabulary hook at all, and wiring `contextualStrings` into it compiled, ran, and changed nothing observable in three separate live Utterances.
`SpeechEngine` now builds `DictationTranscriber` with the `progressiveShortDictation` preset, which is also the closer fit for a held-key Utterance than the long-form preset it replaced.
The decision to stay on-device with Apple rather than Parakeet is unaffected; only the specific module changed.
