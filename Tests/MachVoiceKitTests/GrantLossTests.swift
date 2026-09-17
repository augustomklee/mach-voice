import AVFoundation
import CoreGraphics
import Testing
@testable import MachVoiceKit

/// Issue #14: the Accessibility grant can be taken away while mach-voice runs.
/// These tests hold the three seams that decide what happens then: `Permissions`
/// notices the loss, the `EventTap` teardown closes a held Dictation Key, and a
/// Transcript that arrives without the grant strands instead of being injected.
@MainActor
struct GrantLossTests {

    // MARK: Permissions notices the loss

    @Test func refreshReportsAGrantTakenAway() {
        var trusted = true
        let permissions = Permissions(isAccessibilityTrusted: { trusted }, microphoneStatus: { .authorized })
        permissions.refresh()
        #expect(permissions.allGranted)

        trusted = false
        permissions.refresh()

        #expect(permissions.accessibility == .denied)
        #expect(!permissions.allGranted)
    }

    // MARK: EventTap teardown closes a held Dictation Key

    @Test func uninstallWhileDictationKeyHeldFiresKeyUpOnce() async throws {
        let tap = EventTap()
        var keyUps = 0
        tap.onKeyDown = {}
        tap.onKeyUp = { keyUps += 1 }

        _ = tap.handleFlagsChanged(EventTapDecisionTests.flagsChangedEvent(flags: EventTapDecisionTests.rightCommandFlags))
        tap.uninstall()
        tap.uninstall()

        try await Task.sleep(for: .milliseconds(50))
        #expect(keyUps == 1, "every Utterance the tap opened must be closed exactly once")
        #expect(!tap.isInstalled)
    }

    @Test func uninstallWithDictationKeyUpFiresNothing() async throws {
        let tap = EventTap()
        var keyUps = 0
        tap.onKeyUp = { keyUps += 1 }

        tap.uninstall()

        try await Task.sleep(for: .milliseconds(50))
        #expect(keyUps == 0)
    }

    @Test func escapeAfterUninstallPassesThrough() async throws {
        let tap = EventTap()
        tap.onKeyDown = {}
        tap.onKeyUp = {}
        tap.onEscape = { Issue.record("Escape abandoned an Utterance the teardown already closed") }

        _ = tap.handleFlagsChanged(EventTapDecisionTests.flagsChangedEvent(flags: EventTapDecisionTests.rightCommandFlags))
        tap.uninstall()
        let consumed = tap.handleKeyDown(EventTapDecisionTests.keyDownEvent(keyCode: EventTapDecisionTests.escapeKeyCode))

        #expect(!consumed)
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: A Transcript without the grant strands

    static let target = Target(application: nil, focusedElement: nil, bundleIdentifier: "com.example.Editor", field: nil)

    @Test func transcriptWithoutGrantStrandsWithoutInjection() {
        let disposition = UtteranceController.disposition(
            of: "the quick brown fox", elapsed: 2, target: Self.target, accessibilityGranted: false
        )
        guard case .strand = disposition else {
            Issue.record("expected .strand, got \(disposition)")
            return
        }
    }

    @Test func transcriptWithGrantAndTargetIsInjected() {
        let disposition = UtteranceController.disposition(
            of: "the quick brown fox", elapsed: 2, target: Self.target, accessibilityGranted: true
        )
        guard case .inject(let target) = disposition else {
            Issue.record("expected .inject, got \(disposition)")
            return
        }
        #expect(target.bundleIdentifier == Self.target.bundleIdentifier)
    }

    @Test func transcriptWithoutTargetStrands() {
        let disposition = UtteranceController.disposition(
            of: "the quick brown fox", elapsed: 2, target: nil, accessibilityGranted: true
        )
        guard case .strand = disposition else {
            Issue.record("expected .strand, got \(disposition)")
            return
        }
    }

    /// An Abandoned Utterance produces no Transcript, so losing the grant must
    /// not turn it into a Stranded one that overwrites the clipboard.
    @Test func abandonedUtteranceStaysAbandonedWithoutGrant() {
        for (text, elapsed) in [("hi", 0.1), ("  ", 2.0)] {
            let disposition = UtteranceController.disposition(
                of: text, elapsed: elapsed, target: Self.target, accessibilityGranted: false
            )
            guard case .abandon = disposition else {
                Issue.record("expected .abandon for \(text.debugDescription), got \(disposition)")
                continue
            }
        }
    }
}
