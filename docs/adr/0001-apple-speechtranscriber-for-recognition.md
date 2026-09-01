# Apple SpeechTranscriber for recognition

mach-voice uses the Speech framework's on-device `SpeechTranscriber` rather than a downloaded model such as Parakeet or Whisper.
It runs entirely on the machine, costs nothing, needs no third-party runtime, and supports biasing recognition with a **Vocabulary** before any text exists, which is the mechanism this project relies on to get project-specific words right.
Verified available on this machine, with the English **Speech Model** already present and 16 kHz mono as the working audio format.

## Considered options

Parakeet via Hugging Face was the alternative, and it is the one a reader is most likely to suggest again.
It is a credible engine and may well beat Apple on raw English accuracy.
It was rejected because it adds a model download, a runtime, and a second thing to keep working, in exchange for an accuracy difference that this project can close more cheaply through **Vocabulary**.

## Consequences

Recognition is wrapped behind a single-method protocol so swapping engines stays about a day's work rather than a rewrite.
That wrapper exists specifically so this decision can be revisited cheaply, and it should not be removed as unnecessary indirection.
