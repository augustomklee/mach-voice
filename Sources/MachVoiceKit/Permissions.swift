import AVFoundation
import AppKit
import ApplicationServices
import Observation

/// The separate grants mach-voice needs before any Utterance is possible.
///
/// These are keyed by macOS to the signing identity and bundle identifier, not to
/// a path, which is why the build signs with a stable certificate. An ad-hoc signed
/// build gets a new code hash every time and loses the Accessibility grant on every
/// rebuild. See docs/adr/0003 for why the Dictation Key needs this grant at all.
@MainActor
@Observable
final class Permissions {

    enum State {
        case granted
        case denied
        case undetermined

        var isGranted: Bool { self == .granted }
    }

    private(set) var accessibility: State = .undetermined
    private(set) var microphone: State = .undetermined

    var allGranted: Bool { accessibility.isGranted && microphone.isGranted }

    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    /// The microphone is the only one of the two that has a usable system prompt.
    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    /// Accessibility has no prompt worth relying on, so the app opens the pane and
    /// the person grants it by hand. Asking with the prompt option at least makes
    /// mach-voice appear in the list before they get there.
    func revealAccessibilitySettings() {
        // Spelled out rather than using kAXTrustedCheckOptionPrompt: that symbol is a
        // mutable C global, which Swift 6 strict concurrency rejects. The value is
        // stable and documented, so the literal is safer than silencing the check.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }
}
