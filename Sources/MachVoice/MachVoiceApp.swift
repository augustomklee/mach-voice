import AppKit
import SwiftUI
import os.log

@main
struct MachVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var permissions = Permissions()
    @State private var modelInstaller = SpeechModelInstaller()

    init() {
        // Share the model installer with the app delegate
        _delegate.wrappedValue.modelInstaller = modelInstaller
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(permissions: permissions, modelInstaller: modelInstaller)
        } label: {
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var iconName: String {
        if !permissions.allGranted { return "mic.slash.fill" }
        if modelInstaller.installationState == .notStarted || modelInstaller.installationState == .installing {
            return "mic.slash.fill"
        }
        if case .failed = modelInstaller.installationState {
            return "mic.slash.fill"
        }
        return "mic.fill"
    }
}

/// mach-voice runs as an accessory so it never appears in the Dock and never becomes
/// the active application. That is the same rule the HUD will need later: anything
/// that takes focus becomes the Target, and the Injection goes into mach-voice itself.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.augustomklee.MachVoice", category: "AppDelegate")
    private var eventTap: EventTap?
    private var permissions = Permissions()
    private var utteranceController = UtteranceController()
    var modelInstaller: SpeechModelInstaller?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        permissions.refresh()

        logger.log("Accessibility granted: \(self.permissions.accessibility.isGranted)")
        logger.log("Microphone granted: \(self.permissions.microphone.isGranted)")

        // Share the model installer with the controller
        if let modelInstaller {
            utteranceController.modelInstaller = modelInstaller
        }

        // Install the Speech Model on launch
        Task {
            await utteranceController.prepare()
        }

        // Wire up utterance events
        utteranceController.onDraft = { [weak self] draft in
            self?.logger.log("Draft: \(draft, privacy: .public)")
        }
        utteranceController.onTranscript = { [weak self] transcript in
            self?.logger.log("Transcript: \(transcript, privacy: .public)")
        }

        // Install event tap immediately - will fail gracefully if permissions not granted
        installEventTap()
    }

    func installEventTap() {
        guard eventTap == nil else { return }

        // Install the event tap to monitor Right Command
        let tap = EventTap()
        eventTap = tap
        tap.install(
            onKeyDown: { [weak self] in
                self?.utteranceController.startUtterance()
            },
            onKeyUp: { [weak self] in
                self?.utteranceController.endUtterance()
            },
            onEscape: { [weak self] in
                self?.utteranceController.cancelUtterance()
            },
            onDisabled: { [weak self] in
                self?.logger.log("Event tap was disabled, re-arming...")
            }
        )
    }
}

struct StatusMenu: View {
    @Bindable var permissions: Permissions
    @ObservedObject var modelInstaller: SpeechModelInstaller

    var body: some View {
        Text(statusText)

        Divider()

        Text("Accessibility: \(label(permissions.accessibility))")
        Text("Microphone: \(label(permissions.microphone))")

        if case .installing = modelInstaller.installationState {
            Text("Speech model: \(Int(modelInstaller.progress * 100))%")
        } else {
            Text("Speech model: \(modelStatusText)")
        }

        Divider()

        Button("Re-check permissions") {
            permissions.refresh()
        }

        if !permissions.accessibility.isGranted {
            Button("Open Accessibility settings…") {
                permissions.revealAccessibilitySettings()
            }
        }

        if permissions.microphone == .undetermined {
            Button("Request microphone access") {
                Task { await permissions.requestMicrophone() }
            }
        }

        Divider()

        Button("History") {
            // TODO: open history window
            print("History not yet implemented in UI")
        }

        Button("Vocabulary") {
            // TODO: open vocabulary window
            print("Vocabulary not yet implemented in UI")
        }

        Divider()

        Button("Quit mach-voice") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        guard permissions.allGranted else { return "Waiting on permissions" }
        switch modelInstaller.installationState {
        case .notStarted: return "Starting..."
        case .installing: return "Installing speech model..."
        case .installed: return "Ready"
        case .failed: return "Speech model error"
        }
    }

    private var modelStatusText: String {
        switch modelInstaller.installationState {
        case .notStarted: return "not started"
        case .installing: return "installing"
        case .installed: return "installed"
        case .failed(let error): return "error: \(error)"
        }
    }

    private func label(_ state: Permissions.State) -> String {
        switch state {
        case .granted: "granted"
        case .denied: "not granted"
        case .undetermined: "not asked yet"
        }
    }
}
