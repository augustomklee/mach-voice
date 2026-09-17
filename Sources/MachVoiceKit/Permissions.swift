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

    /// Notified after every refresh, whatever triggered it (launch, the manual
    /// "Re-check permissions" button, or `AppDelegate`'s background poll). Lets
    /// `AppDelegate` install the event tap when the grant arrives (issue #8) and
    /// tear it down when the grant is taken away (issue #14) from one place.
    var onRefresh: (() -> Void)?

    private let isAccessibilityTrusted: () -> Bool
    private let microphoneStatus: () -> AVAuthorizationStatus

    /// The two sources are injectable so a test can take a grant away.
    init(
        isAccessibilityTrusted: @escaping () -> Bool = { Permissions.accessibilityIsTrustedNow() },
        microphoneStatus: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.microphoneStatus = microphoneStatus
    }

    func refresh() {
        accessibility = isAccessibilityTrusted() ? .granted : .denied
        microphone = switch microphoneStatus() {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
        onRefresh?()
    }

    /// Whether the Accessibility grant holds at this moment.
    ///
    /// `AXIsProcessTrusted()` caches a positive answer for the life of the process:
    /// after the grant is taken away it keeps returning true, and so do
    /// `CGPreflightPostEventAccess()` and `CGPreflightListenEventAccess()` (issue #14).
    /// A request answered by another application is checked against the grant
    /// live and fails with `apiDisabled` once it is gone, so a positive answer is
    /// confirmed by asking the Dock, which is always running, for its role.
    /// A missing grant is not cached, so a negative answer needs no confirmation.
    nonisolated static func accessibilityIsTrustedNow() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return true
        }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var role: AnyObject?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) != .apiDisabled
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
