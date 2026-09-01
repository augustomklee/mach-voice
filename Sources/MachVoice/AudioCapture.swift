import Foundation
import os.log
@preconcurrency import AVFoundation

/// Captures audio from the microphone and converts it to the format the
/// speech analyzer expects.
final class AudioCapture {
    private let logger = Logger(subsystem: "com.augustomklee.MachVoice", category: "AudioCapture")
    private let engine = AVAudioEngine()
    private let inputFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var bufferCount = 0

    /// Called for each converted audio buffer.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onError: ((Error) -> Void)?
    /// Called with a normalized (roughly 0...1) input level for the recording indicator.
    var onLevel: ((Float) -> Void)?

    /// - Parameter targetFormat: The exact format the speech analyzer requires.
    ///   Must match `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`;
    ///   feeding a mismatched format crashes deep inside the Speech framework.
    init(targetFormat: AVAudioFormat) {
        inputFormat = engine.inputNode.outputFormat(forBus: 0)
        self.targetFormat = targetFormat
    }

    /// Start capturing audio from the microphone.
    func start() {
        guard let inputFormat, let targetFormat else {
            onError?(AudioCaptureError.invalidFormat)
            return
        }

        logger.log("Input format: \(inputFormat.description, privacy: .public)")
        logger.log("Target format: \(targetFormat.description, privacy: .public)")

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        guard converter != nil else {
            onError?(AudioCaptureError.converterCreationFailed)
            logger.error("Failed to create audio converter")
            return
        }

        bufferCount = 0

        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        do {
            try engine.start()
            logger.log("Audio capture started")
        } catch {
            onError?(error)
            logger.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stop capturing audio.
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        logger.log("Audio capture stopped after \(self.bufferCount) buffers")
    }

    /// Convert the captured audio to the target format and pass to the handler.
    private func process(buffer: AVAudioPCMBuffer) {
        emitLevel(for: buffer)

        guard let converter, let targetFormat else { return }

        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        nonisolated(unsafe) var consumed = false
        let localBuffer = buffer
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return localBuffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            onError?(error)
            logger.error("Conversion error: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard status == .haveData, outputBuffer.frameLength > 0 else {
            return
        }

        bufferCount += 1
        if bufferCount % 20 == 1 {
            logger.log("Captured buffer #\(self.bufferCount), frames=\(outputBuffer.frameLength)")
        }

        onBuffer?(outputBuffer)
    }

    /// Compute a rough RMS level from the raw (pre-conversion) input buffer
    /// and normalize it for the recording indicator's waveform.
    private func emitLevel(for buffer: AVAudioPCMBuffer) {
        guard let onLevel, let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = samples[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Speech RMS is typically well under 1.0; scale up so normal speaking
        // volume visibly moves the waveform, then clamp.
        let normalized = min(max(rms * 6, 0), 1)
        onLevel(normalized)
    }

    enum AudioCaptureError: Error {
        case invalidFormat
        case converterCreationFailed
    }
}