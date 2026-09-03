import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import MachVoiceKit

/// Drives the real `InjectionService.inject` with the three places it touches
/// the machine swapped for observable stand-ins: the Target's text field is a
/// scripted `AccessibilityField`, synthetic key events are recorded instead of
/// posted, and the Injection Profile and pasteboard are private to the test.
///
/// docs/adr/0002 distinguishes two read failures, and these tests lock the
/// distinction in: an original value that cannot be read *before* any write is
/// a clean failure that falls through to paste, and a read-back that cannot be
/// read *after* a successful write is unknowable and strands without retry.
@MainActor
struct InjectionServiceStrandTests {
    static let appID = "com.example.Unverifiable"
    static let text = "the quick brown fox"

    /// A field whose value reads before the write and not after: the
    /// unknowable outcome.
    static func unverifiableField() -> AccessibilityField {
        var written = false
        return AccessibilityField(
            read: { written ? (nil, false) : ("", true) },
            write: { _ in written = true; return .success }
        )
    }

    /// A field whose value cannot be read at all, so no write is ever made.
    static func unreadableField() -> AccessibilityField {
        AccessibilityField(read: { (nil, false) }, write: { _ in Issue.record("wrote to an unreadable field"); return .failure })
    }

    @Test func unreadableReadBackStrandsWithoutPasteAndMarksUnverifiable() throws {
        let harness = Harness()
        let target = Target(application: nil, focusedElement: nil, bundleIdentifier: Self.appID, field: Self.unverifiableField())

        let result = harness.service.inject(Self.text, target: target)

        guard case .stranded = result else {
            Issue.record("expected .stranded, got \(result)")
            return
        }
        #expect(harness.postedKeyCodes.isEmpty, "no paste or keystrokes may follow an unreadable read-back")
        #expect(harness.pasteboard.string(forType: .string) == nil, "paste never touched the pasteboard")
        #expect(harness.profile.mechanism(for: Self.appID) == .paste, "the application is marked unverifiable")
    }

    @Test func unreadableOriginalFallsThroughToPaste() throws {
        let harness = Harness()
        let target = Target(application: nil, focusedElement: nil, bundleIdentifier: Self.appID, field: Self.unreadableField())

        let result = harness.service.inject(Self.text, target: target)

        guard case .success(mechanism: .paste) = result else {
            Issue.record("expected .success(.paste), got \(result)")
            return
        }
        #expect(harness.postedKeyCodes == [9, 9], "one Cmd+V key down and key up")
        #expect(harness.pasteboard.string(forType: .string) == Self.text)
        #expect(harness.profile.mechanism(for: Self.appID) == .paste)
    }

    @Test func unknownIdentityStillInjectsButLearnsNothing() throws {
        let harness = Harness()
        let target = Target(application: nil, focusedElement: nil, bundleIdentifier: nil, field: nil)

        let result = harness.service.inject(Self.text, target: target)

        guard case .success(mechanism: .paste) = result else {
            Issue.record("expected .success(.paste), got \(result)")
            return
        }
        #expect(harness.postedKeyCodes == [9, 9])
        #expect(!FileManager.default.fileExists(atPath: harness.profileURL.path), "nothing is written to the Injection Profile")
    }

    @Test func unknownIdentityStrandsWithoutLearning() throws {
        let harness = Harness()
        let target = Target(application: nil, focusedElement: nil, bundleIdentifier: nil, field: Self.unverifiableField())

        let result = harness.service.inject(Self.text, target: target)

        guard case .stranded = result else {
            Issue.record("expected .stranded, got \(result)")
            return
        }
        #expect(harness.postedKeyCodes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.profileURL.path))
    }

    @Test func pasteRestoreDoesNotOverwriteAStrandedTranscript() async throws {
        let harness = Harness()
        harness.pasteboard.declareTypes([.string], owner: nil)
        harness.pasteboard.setString("previous clipboard", forType: .string)
        let pasted = Target(application: nil, focusedElement: nil, bundleIdentifier: nil, field: nil)

        _ = harness.service.inject("first Utterance", target: pasted)
        harness.service.keepOnClipboard("Stranded Transcript")
        try await Task.sleep(for: .milliseconds(600))

        #expect(harness.pasteboard.string(forType: .string) == "Stranded Transcript")
    }

    @Test func pasteRestoresThePreviousClipboardWhenNothingIntervenes() async throws {
        let harness = Harness()
        harness.pasteboard.declareTypes([.string], owner: nil)
        harness.pasteboard.setString("previous clipboard", forType: .string)
        let pasted = Target(application: nil, focusedElement: nil, bundleIdentifier: nil, field: nil)

        _ = harness.service.inject("first Utterance", target: pasted)
        try await Task.sleep(for: .milliseconds(600))

        #expect(harness.pasteboard.string(forType: .string) == "previous clipboard")
    }
}

/// An `InjectionService` whose Injection Profile, pasteboard and key events are
/// all private to one test.
@MainActor
private final class Harness {
    let profileURL: URL
    let profile: InjectionProfile
    let pasteboard: NSPasteboard
    private(set) var postedKeyCodes: [Int64] = []
    private(set) var service: InjectionService!

    init() {
        profileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mach-voice-injection-profile-\(UUID().uuidString).json")
        profile = InjectionProfile(storageURL: profileURL)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("mach-voice-test-\(UUID().uuidString)"))
        service = InjectionService(profile: profile, pasteboard: pasteboard) { [unowned self] event in
            postedKeyCodes.append(event.getIntegerValueField(.keyboardEventKeycode))
        }
    }

    isolated deinit {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: profileURL)
    }
}
