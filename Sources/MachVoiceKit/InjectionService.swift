import ApplicationServices
import AppKit
import Foundation
import os.log

/// Delivers a Transcript into the Target, with verification and fallback.
@MainActor
final class InjectionService: ObservableObject {
    private let logger = Logger(subsystem: "com.augustomklee.MachVoice", category: "InjectionService")
    private let profile = InjectionProfile()
    private let pasteboard = NSPasteboard.general

    /// The result of an injection attempt.
    enum InjectionResult {
        case success(mechanism: InjectionMechanism)
        case stranded
    }

    /// Attempt to inject the given text into the target.
    ///
    /// Tries the profiled mechanism first if known, otherwise probes.
    func inject(_ text: String, target: Target) -> InjectionResult {
        let appID = target.bundleIdentifier ?? "unknown"
        let preferred = profile.mechanism(for: appID)
        logger.log("inject: appID=\(appID, privacy: .public) preferred=\(String(describing: preferred), privacy: .public) hasFocusedElement=\(target.focusedElement != nil)")

        if let preferred, let result = attempt(text, into: target, using: preferred) {
            logger.log("inject: used preferred mechanism \(String(describing: preferred), privacy: .public)")
            return result
        }

        // Probe mechanisms in order
        for mechanism in [InjectionMechanism.accessibility, .paste, .keystrokes] {
            if let result = attempt(text, into: target, using: mechanism) {
                if case .success = result {
                    profile.learn(bundleIdentifier: appID, mechanism: mechanism)
                }
                logger.log("inject: probe succeeded with \(String(describing: mechanism), privacy: .public)")
                return result
            }
            logger.log("inject: probe failed for \(String(describing: mechanism), privacy: .public)")
        }

        logger.log("inject: all mechanisms failed, stranding")
        return .stranded
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
    /// Three outcomes per the design: landed (success), absent (clean failure,
    /// caller falls through to paste), or unreadable (unknowable, caller must
    /// strand rather than retry).
    private func attemptAccessibility(_ text: String, into target: Target) -> InjectionResult? {
        guard let focusedElement = target.focusedElement else {
            logger.log("attemptAccessibility: no focused element")
            return nil
        }

        let (originalValue, wasReadable) = target.readValue()
        guard wasReadable, let originalValue else {
            logger.log("attemptAccessibility: original value unreadable, skipping AX write")
            return nil
        }

        let newValue = originalValue + text

        let setResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )

        guard setResult == .success else {
            logger.log("attemptAccessibility: set failed with \(String(describing: setResult), privacy: .public)")
            return nil
        }

        // Read back to verify.
        let (readBack, readable) = target.readValue()
        if readable, let readBack, readBack.contains(text) {
            logger.log("attemptAccessibility: verified, text landed")
            return .success(mechanism: .accessibility)
        }

        // Restore original value; we know the write happened but did not stick correctly.
        _ = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, originalValue as CFTypeRef)

        if !readable {
            logger.log("attemptAccessibility: read-back unreadable, unknowable outcome")
            // Unknowable: caller must strand, not retry. Signal via nil but the
            // caller's probe loop will still try paste; that is the accepted
            // trade-off during the exploratory MVP rather than a hard strand.
        } else {
            logger.log("attemptAccessibility: text did not land, absent")
        }
        return nil
    }

    /// Try paste injection, marking pasteboard as transient.
    ///
    /// Paste does not require a readable Accessibility element: Cmd+V is
    /// delivered by the system to whatever currently holds keyboard focus,
    /// which is exactly the case Electron/Chromium apps need since they
    /// often expose no usable AXUIElement at all.
    private func attemptPaste(_ text: String, into target: Target) -> InjectionResult? {
        guard target.bundleIdentifier != nil else {
            logger.log("attemptPaste: no target application")
            return nil
        }

        // Save current pasteboard contents
        let oldString = pasteboard.string(forType: .string)
        let oldTypes = pasteboard.types

        // Set the pasteboard with the new text and mark as transient/concealed
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)

        // Post Command-V to the system HID event tap so it reaches whatever
        // application currently has keyboard focus. Posting to pid 0 does not
        // deliver anywhere.
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        logger.log("attemptPaste: posted Cmd+V")

        // Restore previous pasteboard contents after a short delay so the
        // paste has time to land before we overwrite the clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
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
    private func attemptKeystrokes(_ text: String, into target: Target) -> InjectionResult? {
        guard target.bundleIdentifier != nil else {
            logger.log("attemptKeystrokes: no target application")
            return nil
        }

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
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
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