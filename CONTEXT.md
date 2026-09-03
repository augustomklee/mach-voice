# mach-voice

A local push-to-talk dictation app for macOS.
You hold a key, speak, and release, and the words you said appear in whatever application already had your cursor.
Nothing you say leaves the machine.

## Language

**Utterance**:
One press-hold-release cycle and everything it produces.
_Avoid_: recording, session, clip, dictation

**Dictation Key**:
The single key held for the length of an Utterance, which mach-voice consumes so that it never reaches any other application.
_Avoid_: hotkey, shortcut, push-to-talk modifier, trigger

**Target**:
The application and text field that will receive an Utterance, identified at the moment the key goes down rather than when the text is ready.
_Avoid_: focused app, destination, receiver, frontmost

**Draft**:
The running, uncommitted guess shown to the speaker while they are still talking.
_Avoid_: partial, interim, preview, volatile result

**Transcript**:
The committed text of an Utterance, produced once the speaker releases the key.
_Avoid_: result, output, final text

**Injection**:
The delivery of a Transcript into the Target, which replaces whatever text was selected there rather than inserting alongside it.
_Avoid_: insertion, paste, typing, sending

**Abandoned Utterance**:
An Utterance the speaker cancelled before releasing the Dictation Key, or one too brief to have contained speech, which produces no Transcript and leaves no trace anywhere.
_Avoid_: cancelled recording, empty utterance, discard

**Stranded Transcript**:
A Transcript that Injection did not deliver, either because no mechanism worked or because one could not be verified, which is placed on the clipboard and kept in History so the speaker never loses words.
_Avoid_: failed transcript, dropped text, lost dictation

**Injection Profile**:
The remembered record, held per application, of which Injection mechanism is known to work there.
_Avoid_: app config, strategy cache, compatibility list

**History**:
The durable rolling record of Transcripts from the last 30 days, which is both the recovery path for a Stranded Transcript and the way to retrieve something dictated earlier.
_Avoid_: log, archive, transcript list

**Retention Window**:
The age past which a Transcript is purged from History without being asked, currently 30 days.
_Avoid_: TTL, expiry, cleanup policy

**Vocabulary**:
The single list of words and phrases, shared across every application, handed to recognition ahead of an Utterance so that they are heard correctly in the first place.
_Avoid_: dictionary, custom words, replacements, autocorrect

**Speech Model**:
The on-device model for one language, which must be reserved and installed before any Utterance can be transcribed.
_Avoid_: engine, locale, language pack

## Relationships

- An **Utterance** produces exactly one **Transcript** and any number of **Drafts** along the way
- An **Utterance** binds to exactly one **Target**, fixed at key-down and never re-read later
- A **Transcript** is either delivered by **Injection** or becomes a **Stranded Transcript**
- An **Injection** consults the **Target** application's **Injection Profile** before choosing a mechanism
- A **Stranded Transcript** teaches the **Injection Profile**, so the same application strands at most one **Transcript**
- Every **Transcript** enters **History**, whether or not **Injection** succeeded
- A **Transcript** leaves **History** when it is older than the **Retention Window**
- **Vocabulary** biases the **Draft** and the **Transcript** before either one exists
- No **Utterance** is possible until the **Speech Model** is installed
- Holding the **Dictation Key** opens an **Utterance**, and releasing it closes one
- An **Abandoned Utterance** produces no **Transcript**, so it never reaches **History** and never triggers **Injection**
- An **Injection** replaces the **Target**'s selected text, which is what makes re-dictating a selected sentence work

## Example dialogue

> **Dev:** If the Target application closes while I am still speaking, what happens to the Utterance?
> **Domain expert:** It still produces a Transcript. The Target is fixed at key-down, so there is nowhere to inject it, and it becomes a Stranded Transcript. On the clipboard, in History, and the speaker is told.

> **Dev:** I tapped the key by accident and nothing happened. Should that have been recorded?
> **Domain expert:** No. That is an Abandoned Utterance. Too short to hold speech, so there is no Transcript, nothing in History, and nothing injected. Same if you hit Escape halfway through a sentence you did not mean to start.

> **Dev:** The first Utterance into a new app got stranded, but the second one worked. Is that a bug?
> **Domain expert:** That is the design. The first one could not be verified, so we refused to retry and risk injecting twice. It taught the Injection Profile which mechanism that app accepts, and every Utterance after it goes straight there. One Stranded Transcript per app, never two.

> **Dev:** So should I add the word "Ibiuna" to the dictionary so it gets fixed afterwards?
> **Domain expert:** Not a dictionary. Vocabulary. It goes in before recognition runs so the model hears "Ibiuna" the first time, rather than us finding and replacing a wrong guess after the fact. The two produce different results, and only one of them is correct when the wrong guess happens to be a real word.

## Flagged ambiguities

- "dictionary" was used to mean after-the-fact string replacement on a Transcript.
  Resolved: this project uses **Vocabulary**, which biases recognition before any text exists.
  The two are different mechanisms with different failure modes and must not share a name.
- "volatile" is the platform's word for what this project calls a **Draft**.
  Resolved: **Draft** is the term in conversation and in the domain, and "volatile" appears only where the platform API forces it.
- "hotkey" suggests a key combination that other applications can also see.
  Resolved: the **Dictation Key** is consumed by mach-voice and delivered to nobody else, so it is a dedicated key rather than a shortcut.
- "history" could suggest an optional convenience feature.
  Resolved: **History** serves two purposes, and the first one is why it is durable rather than in-memory.
  It is the recovery path for a **Stranded Transcript**, and it is also how the speaker retrieves something dictated earlier.
  Because the second purpose alone would justify keeping everything forever, the **Retention Window** exists to bound what the first purpose does not need.
