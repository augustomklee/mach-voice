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
    /// Read live when a Transcript arrives rather than from the last poll, which
    /// can be up to one tick stale.
    var accessibilityGranted: () -> Bool = { Permissions.accessibilityIsTrustedNow() }

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

    /// What happens to a Transcript once it arrives.
    enum TranscriptDisposition {
        case abandon(reason: String)
        case strand(reason: String)
        case inject(Target)
    }

    /// Decide a Transcript's fate from the facts at the moment it arrives.
    ///
    /// Without the Accessibility grant no Injection mechanism can work: the AX
    /// write is refused and posted Cmd+V or keystrokes are dropped, while
    /// `attemptPaste` would still report success. So a Transcript that arrives
    /// after the grant was taken away, including the one from an Utterance the
    /// teardown closed mid-speech (issue #14), strands before any Injection is
    /// attempted and teaches the Injection Profile nothing.
    static func disposition(of text: String, elapsed: TimeInterval?, target: Target?, accessibilityGranted: Bool) -> TranscriptDisposition {
        if let elapsed, elapsed < 0.25 {
            return .abandon(reason: "too short")
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .abandon(reason: "no words")
        }
        guard accessibilityGranted else {
            return .strand(reason: "Accessibility grant missing")
        }
        guard let target else {
            return .strand(reason: "No Target captured")
        }
        return .inject(target)
    }

    private func handleTranscript(_ text: String) {
        let elapsed = utteranceStart.map { Date().timeIntervalSince($0) }
        switch Self.disposition(of: text, elapsed: elapsed, target: currentTarget, accessibilityGranted: accessibilityGranted()) {
        case .abandon(let reason):
            logger.log("Abandoned utterance, \(reason, privacy: .public)")
        case .strand(let reason):
            logger.log("\(reason, privacy: .public)")
            strand(text)
        case .inject(let target):
            switch injectionService.inject(text, target: target) {
            case .success(let mechanism):
                history.add(text: text, success: true)
                logger.log("Injected via \(String(describing: mechanism), privacy: .public)")
            case .stranded:
                strand(text)
            }
        }
    }

    /// A Stranded Transcript loses nothing: clipboard, History, and the speaker is told.
    private func strand(_ text: String) {
        history.add(text: text, success: false)
        injectionService.keepOnClipboard(text)
        indicator.announce("Could not deliver the words. They are on the clipboard.")
        logger.log("Stranded Transcript: \(text, privacy: .public)")
    }
}