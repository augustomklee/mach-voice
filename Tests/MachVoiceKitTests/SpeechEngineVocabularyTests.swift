import AVFoundation
import Foundation
import Testing
@testable import MachVoiceKit

/// Drives the real `SpeechEngine` over the same audio twice, once with an empty
/// Vocabulary and once with the term in it, so the Vocabulary reaching
/// recognition is observable without a person holding the Dictation Key.
///
/// The call sequence is the one `UtteranceController` runs for a held Dictation
/// Key: `startAnalysis(vocabulary:)`, then `analyze(buffer:)` per audio buffer,
/// then `finalize()`. Only the Vocabulary differs between the two Utterances, so
/// a difference in the Transcript can only have come from the Vocabulary.
///
/// The audio is spoken by the system speech synthesiser rather than committed as
/// a fixture, and recognising it needs the en_US Speech Model installed, which is
/// what the app itself needs to recognise anything at all.
@MainActor
struct SpeechEngineVocabularyTests {
    /// A Portuguese place name the stock en_US Speech Model does not know, so an
    /// unbiased Utterance lands on an English word that sounds like it.
    static let term = "Ibiuna"
    static let spokenPhrase = "Send it to Ibiuna please"

    @Test func vocabularyTermReachesRecognition() async throws {
        let speechEngine = try await SpeechEngine()
        await speechEngine.prepare()

        let buffers = try Self.speak(Self.spokenPhrase, into: speechEngine.audioFormat)
        #expect(!buffers.isEmpty)

        let withoutVocabulary = try await Self.transcribe(buffers, vocabulary: [], with: speechEngine)
        let withVocabulary = try await Self.transcribe(buffers, vocabulary: [Self.term], with: speechEngine)

        print("""

        --- Vocabulary reaches recognition ---
        analyzer format : \(speechEngine.audioFormat.sampleRate) Hz, \(speechEngine.audioFormat.channelCount) ch, Int16
        spoken audio    : "\(Self.spokenPhrase)" (identical buffers for both Utterances)

        Utterance 1, Vocabulary []
          Drafts     : \(withoutVocabulary.drafts.suffix(4).map { "\"\($0)\"" }.joined(separator: " -> "))
          Transcript : "\(withoutVocabulary.transcript)"

        Utterance 2, Vocabulary ["\(Self.term)"]
          Drafts     : \(withVocabulary.drafts.suffix(4).map { "\"\($0)\"" }.joined(separator: " -> "))
          Transcript : "\(withVocabulary.transcript)"
        --------------------------------------

        """)

        #expect(withVocabulary.transcript.localizedCaseInsensitiveContains(Self.term))
        #expect(!withoutVocabulary.transcript.localizedCaseInsensitiveContains(Self.term))
    }

    /// Run one Utterance end to end and return its Drafts and its Transcript.
    ///
    /// Buffers are fed at the pace `AudioCapture` delivers them, one tenth of a
    /// second of audio per tenth of a second, because the running hypothesis
    /// depends on audio arriving in real time.
    private static func transcribe(
        _ buffers: [AVAudioPCMBuffer],
        vocabulary: [String],
        with speechEngine: SpeechEngine
    ) async throws -> (drafts: [String], transcript: String) {
        let sink = TranscriptSink()
        speechEngine.onDraft = { [sink] text in sink.drafts.append(text) }
        speechEngine.onTranscript = { [sink] text in sink.text = text }

        let sampleRate = speechEngine.audioFormat.sampleRate
        speechEngine.startAnalysis(vocabulary: vocabulary)
        for buffer in buffers {
            speechEngine.analyze(buffer: buffer)
            try await Task.sleep(for: .milliseconds(Int(Double(buffer.frameLength) / sampleRate * 1000)))
        }
        speechEngine.finalize()

        let deadline = Date().addingTimeInterval(30)
        while sink.text == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        speechEngine.stop()

        let transcript = try #require(sink.text, "no Transcript within 30s for Vocabulary \(vocabulary)")
        return (sink.drafts, transcript)
    }

    /// Speak `phrase` with the system speech synthesiser straight into the sample
    /// rate the analyzer demands, then hand it back as Utterance-sized buffers.
    private static func speak(_ phrase: String, into format: AVAudioFormat) throws -> [AVAudioPCMBuffer] {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mach-voice-vocabulary-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let synthesiser = Process()
        synthesiser.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        synthesiser.arguments = [
            "-o", url.path,
            "--file-format=WAVE",
            "--data-format=LEF32@\(Int(format.sampleRate))",
            phrase
        ]
        try synthesiser.run()
        synthesiser.waitUntilExit()
        try #require(synthesiser.terminationStatus == 0, "system speech synthesiser failed")

        // The synthesiser writes Float32 and the analyzer demands Int16 at the
        // same sample rate. Feeding it any other format crashes inside the Speech
        // framework, so every buffer is converted before it is fed.
        let file = try AVAudioFile(forReading: url)
        try #require(file.processingFormat.sampleRate == format.sampleRate)
        let converter = try #require(AVAudioConverter(from: file.processingFormat, to: format))

        var buffers: [AVAudioPCMBuffer] = []
        let chunk = AVAudioFrameCount(format.sampleRate / 10)
        while file.framePosition < file.length {
            guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                  let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
            try file.read(into: source, frameCount: chunk)
            if source.frameLength == 0 { break }
            try converter.convert(to: converted, from: source)
            buffers.append(converted)
        }

        // A tail of silence gives the analyzer an end-of-speech boundary.
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk * 5) {
            silence.frameLength = chunk * 5
            buffers.append(silence)
        }

        return buffers
    }
}

/// Holds the Drafts and the Transcript the `SpeechEngine` hands back, so the test
/// can wait on the Transcript and report the Drafts that led to it.
@MainActor
private final class TranscriptSink {
    var drafts: [String] = []
    var text: String?
}
