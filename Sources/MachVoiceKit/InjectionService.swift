import ApplicationServices
import AppKit
import Foundation
import os.log

/// Delivers a Transcript into the Target, with verification and fallback.
@MainActor
final class InjectionService: ObservableObject {
    private let logger = Logger(subsystem: "com.augustomklee.MachVoice", category: "InjectionService")
    private let profile: InjectionProfile
    private let pasteboard: NSPasteboard
    private let postEvent: @MainActor (CGEvent) -> Void

    /// The nspasteboard.org marker that asks clipboard managers not to keep a
    /// copy of what passes through, so a Transcript does not outlive its
    /// Retention Window somewhere outside mach-voice.
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// The result of an injection attempt.
    enum InjectionResult {
        case success(mechanism: InjectionMechanism)
        case stranded
    }

    convenience init() {
        self.init(profile: InjectionProfile(), pasteboard: .general) { $0.post(tap: .cghidEventTap) }
    }

    /// `postEvent` is where synthetic key events leave the process, so a test can
    /// observe that paste and keystrokes were never attempted.
    init(profile: InjectionProfile, pasteboard: NSPasteboard, postEvent: @escaping @MainActor (CGEvent) -> Void) {
        self.profile = profile
        self.pasteboard = pasteboard
        self.postEvent = postEvent
    }

    /// Attempt to inject the given text into the target.
    ///
    /// Tries the profiled mechanism first if known, otherwise probes. A Target
    /// whose application identity is unknown is still injected into, because
    /// paste and keystrokes go to whatever holds keyboard focus, but it teaches
    /// the Injection Profile nothing: there is no key to learn under.
    func inject(_ text: String, target: Target) -> InjectionResult {
        let appID = target.bundleIdentifier
        let preferred = appID.flatMap { profile.mechanism(for: $0) }
        logger.log("inject: appID=\(appID ?? "nil", privacy: .public) preferred=\(String(describing: preferred), privacy: .public) hasFocusedElement=\(target.focusedElement != nil)")

        let order = [preferred].compactMap { $0 } + InjectionMechanism.allCases.filter { $0 != preferred }
        for mechanism in order {
            guard let result = attempt(text, into: target, using: mechanism) else {
                logger.log("inject: probe failed for \(String(describing: mechanism), privacy: .public)")
                continue
            }
            switch result {
            case .success:
                logger.log("inject: delivered with \(String(describing: mechanism), privacy: .public)")
                if let appID, mechanism != preferred {
                    profile.learn(bundleIdentifier: appID, mechanism: mechanism)
                }
            case .stranded:
                // docs/adr/0002: the read-back was unreadable, so the Transcript
                // may already be in the document. Nothing else is attempted in
                // this Utterance, and the application is marked unverifiable so
                // the next Utterance there goes straight to paste.
                logger.log("inject: \(String(describing: mechanism), privacy: .public) outcome unknowable, stranding without retry")
                if let appID {
                    profile.markUnverifiable(bundleIdentifier: appID)
                }
            }
            return result
        }

        logger.log("inject: all mechanisms failed, stranding")
        return .stranded
    }

    /// Put a Stranded Transcript on the clipboard so the speaker loses nothing.
    ///
    /// Bumping the pasteboard's change count is also what stops a pending
    /// paste restore from overwriting it: see `attemptPaste`.
    func keepOnClipboard(_ text: String) {
        pasteboard.declareTypes([.string, Self.concealed], owner: nil)
        pasteboard.setString(text, forType: .string)
        logger.log("keepOnClipboard: Stranded Transcript placed on the clipboard")
    }

    private func attempt(_ text: String, into target: Target, using mechanism: InjectionMechanism) -> InjectionResult? {
        switch mechanism {
        case .accessibility:
            return attemptAccessibility(text, into: target)
        case .paste:
            return attemptPaste(text, into: target)
        case .keystrokes:
            return attemptKeystrokes(text, into: target)
        }
    }

    /// Try accessibility API and verify the write landed.
    ///
    /// Three outcomes per docs/adr/0002: landed (`.success`), absent (`nil`, a
    /// clean failure the caller falls through from), or unreadable read-back
    /// (`.stranded`, the unknowable outcome the caller must never retry).
    ///
    /// Only a read-back that fails *after* a successful write is unknowable. An
    /// original value that cannot be read before any write is a clean failure:
    /// nothing was written, so nothing can be duplicated by trying paste.
    private func attemptAccessibility(_ text: String, into target: Target) -> InjectionResult? {
        guard let field = target.field else {
            logger.log("attemptAccessibility: no focused element")
            return nil
        }

        let (originalValue, wasReadable) = field.read()
        guard wasReadable, let originalValue else {
            logger.log("attemptAccessibility: original value unreadable, skipping AX write")
            return nil
        }

        let setResult = field.write(originalValue + text)
        guard setResult == .success else {
            logger.log("attemptAccessibility: set failed with \(String(describing: setResult), privacy: .public)")
            return nil
        }

        // Read back to verify.
        let (readBack, readable) = field.read()
        if readable, let readBack, readBack.contains(text) {
            logger.log("attemptAccessibility: verified, text landed")
            return .success(mechanism: .accessibility)
        }

        // Restore the original value. Best-effort against a state this branch
        // does not know: the read-back may have been unreadable, so whether the
        // Transcript reached the Target is unknown, and this write cannot be
        // verified either.
        _ = field.write(originalValue)

        guard readable else {
            logger.log("attemptAccessibility: read-back unreadable, unknowable outcome")
            return .stranded
        }
        logger.log("attemptAccessibility: text did not land, absent")
        return nil
    }

    /// Try paste injection, marking the pasteboard concealed.
    ///
    /// Paste does not require a readable Accessibility element or a known
    /// application identity: Cmd+V is delivered by the system to whatever
    /// currently holds keyboard focus, which is exactly the case
    /// Electron/Chromium apps need since they often expose no usable
    /// AXUIElement at all.
    private func attemptPaste(_ text: String, into target: Target) -> InjectionResult? {
        // Save current pasteboard contents
        let oldString = pasteboard.string(forType: .string)
        let oldTypes = pasteboard.types

        // Set the pasteboard with the new text and mark it concealed
        pasteboard.declareTypes([.string, Self.concealed], owner: nil)
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        // Post Command-V to the system HID event tap so it reaches whatever
        // application currently has keyboard focus. Posting to pid 0 does not
        // deliver anywhere.
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        if let keyDown { postEvent(keyDown) }
        if let keyUp { postEvent(keyUp) }

        logger.log("attemptPaste: posted Cmd+V")

        // Restore previous pasteboard contents after a short delay so the
        // paste has time to land before we overwrite the clipboard. Restore
        // only if nothing has written to the pasteboard since: a Stranded
        // Transcript kept on the clipboard in the meantime must survive.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.pasteboard.changeCount == ourChangeCount else { return }
            if let oldTypes, let oldString {
                self.pasteboard.declareTypes(oldTypes, owner: nil)
                self.pasteboard.setString(oldString, forType: .string)
            } else {
                self.pasteboard.clearContents()
            }
        }

        return .success(mechanism: .paste)
    }

    /// Try synthetic keystrokes as a fallback.
    ///
    /// Like paste, keystrokes go to whatever holds keyboard focus, so no
    /// application identity is needed.
    private func attemptKeystrokes(_ text: String, into target: Target) -> InjectionResult? {
        let source = CGEventSource(stateID: .hidSystemState)
        for char in text {
            if char == " " {
                postKey(49, source: source)
                continue
            }
            guard let keyCode = keyCodeForCharacter(char) else { continue }
            postKey(keyCode, source: source)
        }

        logger.log("attemptKeystrokes: posted \(text.count) characters")
        return .success(mechanism: .keystrokes)
    }

    private func postKey(_ keyCode: CGKeyCode, source: CGEventSource?) {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        if let keyDown { postEvent(keyDown) }
        if let keyUp { postEvent(keyUp) }
    }

    private func keyCodeForCharacter(_ char: Character) -> CGKeyCode? {
        let string = String(char)
        // Simple ASCII mapping
        switch string.uppercased() {
        case "A": return 0
        case "B": return 11
        case "C": return 8
        case "D": return 2
        case "E": return 14
        case "F": return 3
        case "G": return 5
        case "H": return 4
        case "I": return 34
        case "J": return 38
        case "K": return 40
        case "L": return 37
        case "M": return 46
        case "N": return 45
        case "O": return 31
        case "P": return 35
        case "Q": return 12
        case "R": return 15
        case "S": return 1
        case "T": return 17
        case "U": return 32
        case "V": return 9
        case "W": return 13
        case "X": return 7
        case "Y": return 16
        case "Z": return 6
        case " ": return 49
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        default: return nil
        }
    }
}