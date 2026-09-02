import AppKit
import SwiftUI
import Foundation

/// Observable state driving the recording indicator's live waveform and Draft text.
@MainActor
final class RecordingIndicatorState: ObservableObject {
    @Published var transcript: String = ""
    @Published var audioLevel: CGFloat = 0
    /// A message shown in place of the waveform and Draft once the Utterance has ended.
    @Published var message: String?
}

/// The indicator's content: an animated waveform plus the current Draft,
/// or a message on its own.
private struct RecordingIndicatorView: View {
    @ObservedObject var state: RecordingIndicatorState

    private static let barWeights: [CGFloat] = [0.35, 0.6, 1.0, 0.75, 0.45]

    var body: some View {
        VStack(spacing: 10) {
            if let message = state.message {
                Label(message, systemImage: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                HStack(spacing: 5) {
                    ForEach(Array(Self.barWeights.enumerated()), id: \.offset) { index, weight in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 4, height: barHeight(weight: weight))
                            .animation(.easeOut(duration: 0.12), value: state.audioLevel)
                    }
                }
                .frame(height: 28)

                Text(state.transcript.isEmpty ? "Listening…" : state.transcript)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .fixedSize()
    }

    private func barHeight(weight: CGFloat) -> CGFloat {
        let level = min(max(state.audioLevel, 0), 1)
        return 6 + 22 * level * weight
    }
}

/// Non-activating recording indicator overlay.
///
/// Must never become the key window: if it takes focus, mach-voice itself
/// becomes the Target and the Injection goes into the indicator instead of
/// the real application the speaker was dictating into.
@MainActor
final class RecordingIndicator {
    private var window: NSPanel?
    private let state = RecordingIndicatorState()
    private var dismissal: Task<Void, Never>?

    /// Show the indicator for a new Utterance.
    func show() {
        dismissal?.cancel()
        state.transcript = ""
        state.audioLevel = 0
        state.message = nil

        presentPanel()
    }

    /// Show a message after the Utterance has ended, then dismiss it.
    ///
    /// `hide()` has already run by the time a Transcript arrives, so this
    /// rebuilds the panel rather than expecting one to exist, and `show()`
    /// for the next Utterance cancels the pending dismissal.
    func announce(_ message: String, for duration: Duration = .seconds(3)) {
        dismissal?.cancel()
        state.message = message
        presentPanel()

        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func presentPanel() {
        guard window == nil else { return }

        let hosting = NSHostingView(rootView: RecordingIndicatorView(state: state))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 110)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        positionPanel(panel)

        window = panel
        panel.orderFrontRegardless()
    }

    /// Update the live Draft text shown in the indicator.
    func updateTranscript(_ text: String) {
        state.transcript = text
    }

    /// Update the waveform's audio level, roughly 0...1.
    func updateLevel(_ level: Float) {
        state.audioLevel = CGFloat(level)
    }

    /// Hide the indicator.
    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - panel.frame.width / 2
        let y = screen.frame.minY + 140
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}