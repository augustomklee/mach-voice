import AVFoundation
import Foundation
import Speech
import os.log

/// Wraps the Speech framework's analyzer and transcriber.
///
/// `finalizeAndFinishThroughEndOfInput()` and `cancelAndFinishNow()` permanently
/// finish a `SpeechAnalyzer` instance, not just the current Utterance -- Apple's
/// docs describe both as "finishes analysis." So a fresh `SpeechAnalyzer` and
/// `DictationTranscriber` pair is created for every Utterance. `ModelRetention
/// .processLifetime` is what keeps the underlying model weights resident so
/// each new analyzer's `prepareToAnalyze` stays cheap, per MVP.md's guidance
/// that the model stays "resident between Utterances."
///
/// `DictationTranscriber`, not `SpeechTranscriber`, is the module used here.
/// Apple's docs for `AnalysisContext.contextualStrings` scope that property to
/// `DictationTranscriber` explicitly; `SpeechTranscriber` exposes no Vocabulary
/// hook at all. `progressiveShortDictation` is also the closer preset for a
/// push-to-talk Utterance: a single held-key phrase, not a long recording.
@MainActor
final class SpeechEngine: ObservableObject {
    private let logger = Logger(subsystem: "com.augustomklee.MachVoice", category: "SpeechEngine")
    private let locale: Locale
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var audioContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzeTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var totalFrames: AVAudioFramePosition = 0

    /// Called when a partial Draft is produced.
    var onDraft: ((String) -> Void)?
    /// Called when the final Transcript is produced.
    var onTranscript: ((String) -> Void)?
    /// Called when an error occurs.
    var onError: ((Error) -> Void)?

    /// The exact audio format the analyzer requires. Feeding buffers in any
    /// other format crashes deep inside the Speech framework.
    let audioFormat: AVAudioFormat

    /// The single module mach-voice recognises with. `SpeechModelInstaller`
    /// probes and installs assets through this same call, because the two
    /// modules keep separate asset inventories and a mismatch leaves the
    /// analyzer with no installed model.
    static func makeTranscriber(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    }

    init(locale: Locale = Locale(identifier: "en_US")) async throws {
        self.locale = locale
        let probeTranscriber = Self.makeTranscriber(locale: locale)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probeTranscriber]) else {
            throw SpeechEngineError.noAudioFormat
        }
        self.audioFormat = format
    }

    /// Warm the model at launch so the first Utterance does not pay the
    /// asset-loading cost. Uses a throwaway analyzer that is immediately
    /// finished; only the underlying model residency (processLifetime)
    /// carries forward.
    func prepare() async {
        do {
            let warmupTranscriber = Self.makeTranscriber(locale: locale)
            let options = SpeechAnalyzer.Options(priority: .medium, modelRetention: .processLifetime)
            let warmupAnalyzer = SpeechAnalyzer(modules: [warmupTranscriber], options: options)

            try await warmupAnalyzer.prepareToAnalyze(in: audioFormat)
            await warmupAnalyzer.cancelAndFinishNow()

            logger.log("Speech model warmed, format=\(self.audioFormat.description, privacy: .public)")
        } catch {
            onError?(error)
            logger.error("Failed to warm speech model: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Start a new Utterance: build a fresh analyzer/transcriber pair and
    /// begin an audio stream for it. `vocabulary` is handed to this
    /// Utterance's `AnalysisContext` before analysis begins, so a term added
    /// to the Vocabulary takes effect on the very next Utterance.
    func startAnalysis(vocabulary: [String]) {
        let newTranscriber = Self.makeTranscriber(locale: locale)
        let options = SpeechAnalyzer.Options(priority: .medium, modelRetention: .processLifetime)
        let newAnalyzer = SpeechAnalyzer(modules: [newTranscriber], options: options)
        let context = AnalysisContext()
        context.contextualStrings[.general] = vocabulary

        analyzer = newAnalyzer
        transcriber = newTranscriber
        totalFrames = 0

        // Collect results for this Utterance's transcriber.
        resultTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in newTranscriber.results {
                    let text = String(result.text.characters)
                    self.logger.log("Result isFinal=\(result.isFinal) text=\(text, privacy: .public)")
                    if result.isFinal {
                        self.onTranscript?(text)
                    } else {
                        self.onDraft?(text)
                    }
                }
                self.logger.log("Results sequence ended")
            } catch {
                self.logger.error("Results sequence error: \(error.localizedDescription, privacy: .public)")
                self.onError?(error)
            }
        }

        let stream = AsyncStream<AnalyzerInput> { continuation in
            self.audioContinuation = continuation
        }

        analyzeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await newAnalyzer.setContext(context)
            } catch {
                self.logger.error("Vocabulary not applied, continuing unbiased: \(error.localizedDescription, privacy: .public)")
            }

            do {
                try await newAnalyzer.prepareToAnalyze(in: self.audioFormat)
                _ = try await newAnalyzer.analyzeSequence(stream)
                self.logger.log("Analysis sequence ended")
            } catch {
                self.logger.error("Analysis sequence error: \(error.localizedDescription, privacy: .public)")
                self.onError?(error)
            }
        }

        logger.log("Analysis started")
    }

    /// Feed an audio buffer into the analyzer.
    func analyze(buffer: AVAudioPCMBuffer) {
        guard let audioContinuation else {
            logger.error("analyze(buffer:) called with no active audio continuation")
            return
        }

        let startTime = CMTimeMake(value: totalFrames, timescale: Int32(audioFormat.sampleRate))
        let input = AnalyzerInput(buffer: buffer, bufferStartTime: startTime)
        audioContinuation.yield(input)

        totalFrames += Int64(buffer.frameLength)
    }

    /// Finalize the current Utterance's analyzer and produce a final Transcript.
    func finalize() {
        audioContinuation?.finish()
        audioContinuation = nil

        guard let analyzer else { return }
        self.analyzer = nil
        let finishedTranscriber = transcriber
        transcriber = nil

        Task {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                self.logger.log("Finalized utterance")
            } catch {
                self.logger.error("Finalize error: \(error.localizedDescription, privacy: .public)")
                onError?(error)
            }
            _ = finishedTranscriber
        }
    }

    /// Cancel the current Utterance's analyzer.
    func cancel() {
        audioContinuation?.finish()
        audioContinuation = nil

        guard let analyzer else { return }
        self.analyzer = nil
        transcriber = nil

        Task {
            await analyzer.cancelAndFinishNow()
            self.logger.log("Cancelled utterance")
        }
    }

    /// Stop the active analysis task.
    func stop() {
        audioContinuation?.finish()
        audioContinuation = nil
        analyzeTask?.cancel()
        analyzeTask = nil
        resultTask?.cancel()
        resultTask = nil
        analyzer = nil
        transcriber = nil
    }

    enum SpeechEngineError: Error {
        case noAudioFormat
    }
}