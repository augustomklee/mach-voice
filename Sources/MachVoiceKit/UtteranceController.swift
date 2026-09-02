import AVFoundation
import Foundation
import Speech
import os.log

/// Coordinates an Utterance from key press to Transcript.
@MainActor
final class UtteranceController: ObservableObject {
    private let logger = Logger(subsystem: "com.augustomklee.MachVoice", category: "UtteranceController")
    private var audioCapture: AudioCapture?
    private var speechEngine: SpeechEngine?
    var modelInstaller = SpeechModelInstaller()
    private let injectionService = InjectionService()
    private let history = HistoryStore()
    private let indicator = RecordingIndicator()
    let vocabulary = VocabularyManager()
    private var currentTarget: Target?
    private var utteranceStart: Date?

    /// Called when a partial Draft is produced.
    var onDraft: ((String) -> Void)?
    /// Called when the final Transcript is produced.
    var onTranscript: ((String) -> Void)?

    /// Initialize and prepare the speech engine.
    func prepare() async {
        await modelInstaller.installIfNeeded()

        do {
            speechEngine = try await SpeechEngine()
            speechEngine?.onDraft = { [weak self] text in
                self?.onDraft?(text)
                self?.indicator.updateTranscript(text)
            }
            speechEngine?.onTranscript = { [weak self] text in
                self?.onTranscript?(text)
                self?.indicator.updateTranscript(text)
                self?.handleTranscript(text)
            }
            await speechEngine?.prepare()
        } catch {
            logger.error("Failed to create speech engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Start a new Utterance.
    func startUtterance() {
        guard let speechEngine else {
            logger.error("Speech engine not ready yet")
            return
        }

        utteranceStart = Date()
        currentTarget = Target.capture()
        logger.log("Utterance started, target bundleID=\(self.currentTarget?.bundleIdentifier ?? "nil", privacy: .public)")
        indicator.show()
        speechEngine.startAnalysis(vocabulary: vocabulary.allTerms)

        audioCapture = AudioCapture(targetFormat: speechEngine.audioFormat)
        audioCapture?.onBuffer = { [weak self] buffer in
            // Feed audio to the speech engine
            self?.speechEngine?.analyze(buffer: buffer)
        }
        audioCapture?.onLevel = { [weak self] level in
            self?.indicator.updateLevel(level)
        }
        audioCapture?.onError = { [weak self] error in
            self?.logger.error("Audio capture error: \(error.localizedDescription, privacy: .public)")
        }
        audioCapture?.start()
    }

    /// End the current Utterance and produce a final Transcript.
    func endUtterance() {
        logger.log("Utterance ended")
        indicator.hide()
        audioCapture?.stop()
        audioCapture = nil
        speechEngine?.finalize()
    }

    /// Cancel the current Utterance.
    func cancelUtterance() {
        logger.log("Utterance cancelled")
        indicator.hide()
        audioCapture?.stop()
        audioCapture = nil
        speechEngine?.cancel()
        utteranceStart = nil
    }

    private func handleTranscript(_ text: String) {
        // Abandoned Utterance: too short
        if let start = utteranceStart, Date().timeIntervalSince(start) < 0.25 {
            logger.log("Abandoned utterance, too short")
            return
        }

        guard let target = currentTarget else {
            logger.log("No target captured, transcript is stranded: \(text, privacy: .public)")
            return
        }

        let result = injectionService.inject(text, target: target)
        switch result {
        case .success(let mechanism):
            history.add(text: text, success: true)
            logger.log("Injected via \(String(describing: mechanism), privacy: .public)")
        case .stranded:
            history.add(text: text, success: false)
            logger.log("Stranded transcript: \(text, privacy: .public)")
        }
    }
}