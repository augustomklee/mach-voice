import AppKit
import SwiftUI
import os.log

public struct MachVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var permissions = Permissions()
    @State private var modelInstaller = SpeechModelInstaller()

    public init() {
        // Share the model installer and the permissions state with the app delegate,
        // so there is exactly one Permissions instance for the whole app (issue #8).
        _delegate.wrappedValue.modelInstaller = modelInstaller
        _delegate.wrappedValue.permissions = permissions
    }

    public var body: some Scene {
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
    private var permissionsPollTimer: Timer?
    var permissions = Permissions()
    private var utteranceController = UtteranceController()
    var modelInstaller: SpeechModelInstaller?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Every refresh, however it was triggered, brings the event tap in line with
        // the Accessibility grant: up when it arrives (issue #8), down when it is
        // taken away (issue #14).
        permissions.onRefresh = { [weak self] in
            self?.syncEventTapWithGrant()
        }
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

        // permissions.refresh() above already attempted this via onRefresh; this
        // covers the case where onRefresh was set after an already-granted state
        // was read some other way.
        installEventTap()

        // Notice a grant that arrives or is taken away after launch with zero
        // interaction (issues #8 and #14). mach-voice is an accessory app with no
        // window, so there is no activation or menu-open moment to piggyback on.
        startPermissionsPolling()
    }

    private func syncEventTapWithGrant() {
        if permissions.accessibility.isGranted {
            installEventTap()
        } else {
            uninstallEventTap()
        }
    }

    func installEventTap() {
        guard eventTap == nil, permissions.accessibility.isGranted else { return }

        // Install the event tap to monitor Right Command
        let tap = EventTap()
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
                // A lost grant is one reason macOS disables a tap, so check it now
                // rather than re-arming a tap that has to come down at the next tick.
                self?.logger.log("Event tap was disabled, re-checking permissions before re-arming")
                self?.permissions.refresh()
            }
        )
        // Only keep the tap once it is confirmed live: assigning it beforehand left
        // every later attempt no-op forever once CGEvent.tapCreate had failed once.
        if tap.isInstalled {
            eventTap = tap
        }
    }

    /// Remove the tap once the grant is gone, so a restored grant installs a fresh
    /// one through `installEventTap`. An Utterance whose Dictation Key is still held
    /// is closed by the teardown, and its Transcript strands because Injection
    /// cannot run without the grant (see `UtteranceController.disposition`).
    func uninstallEventTap() {
        guard let eventTap else { return }
        logger.log("Accessibility grant lost, removing the event tap")
        eventTap.uninstall()
        self.eventTap = nil
    }

    /// Polls for the whole run rather than stopping once everything is granted:
    /// a grant taken away later has no notification either (issue #14).
    private func startPermissionsPolling() {
        guard permissionsPollTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPermissions()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionsPollTimer = timer
    }

    private func pollPermissions() {
        let wasGranted = permissions.accessibility.isGranted
        permissions.refresh()
        if wasGranted != permissions.accessibility.isGranted {
            logger.log("Accessibility granted: \(self.permissions.accessibility.isGranted)")
        }
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
