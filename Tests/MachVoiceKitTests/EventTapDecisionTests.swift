import CoreGraphics
import Testing
@testable import MachVoiceKit

/// `EventTap.handleKeyDown` is what let Escape regress silently: Escape has no role
/// in this app unless the Dictation Key is held, so it must pass through untouched
/// the rest of the time. These tests drive the tap's own handlers with real `CGEvent`
/// values and assert two observable outcomes: the consume return and whether `onEscape`
/// fired, per issue #10's testing decisions.
@MainActor
struct EventTapDecisionTests {
    static let rightCommandFlags = CGEventFlags(rawValue: 0x10)
    static let noFlags = CGEventFlags(rawValue: 0)
    static let escapeKeyCode: Int64 = 53
    static let otherKeyCode: Int64 = 0 // 'a'

    static func keyDownEvent(keyCode: Int64) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
        event.flags = noFlags
        return event
    }

    static func flagsChangedEvent(flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x36, keyDown: true)!
        event.flags = flags
        return event
    }

    @Test func escapeWithRightCommandNeverPressedPassesThrough() async throws {
        let tap = EventTap()
        var escapeFired = false
        tap.onEscape = { escapeFired = true }

        let consumed = tap.handleKeyDown(Self.keyDownEvent(keyCode: Self.escapeKeyCode))

        #expect(!consumed, "Escape must reach the frontmost application when no Utterance is in progress")
        try await Task.sleep(for: .milliseconds(50))
        #expect(!escapeFired)
    }

    @Test func rightCommandDownThenEscapeConsumesAndFires() async throws {
        let tap = EventTap()
        var escapeFired = false
        tap.onEscape = { escapeFired = true }
        tap.onKeyDown = {}

        _ = tap.handleFlagsChanged(Self.flagsChangedEvent(flags: Self.rightCommandFlags))
        let consumed = tap.handleKeyDown(Self.keyDownEvent(keyCode: Self.escapeKeyCode))

        #expect(consumed)
        try await Task.sleep(for: .milliseconds(50))
        #expect(escapeFired)
    }

    @Test func rightCommandDownThenUpThenEscapePassesThrough() async throws {
        let tap = EventTap()
        var escapeFired = false
        tap.onEscape = { escapeFired = true }
        tap.onKeyDown = {}
        tap.onKeyUp = {}

        _ = tap.handleFlagsChanged(Self.flagsChangedEvent(flags: Self.rightCommandFlags))
        _ = tap.handleFlagsChanged(Self.flagsChangedEvent(flags: Self.noFlags))
        let consumed = tap.handleKeyDown(Self.keyDownEvent(keyCode: Self.escapeKeyCode))

        #expect(!consumed, "Escape must reach the frontmost application once the Dictation Key is released")
        try await Task.sleep(for: .milliseconds(50))
        #expect(!escapeFired)
    }

    @Test func nonEscapeKeyWithRightCommandDownPassesThrough() async throws {
        let tap = EventTap()
        var escapeFired = false
        tap.onEscape = { escapeFired = true }
        tap.onKeyDown = {}

        _ = tap.handleFlagsChanged(Self.flagsChangedEvent(flags: Self.rightCommandFlags))
        let consumed = tap.handleKeyDown(Self.keyDownEvent(keyCode: Self.otherKeyCode))

        #expect(!consumed)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!escapeFired)
    }

    /// docs/adr/0003: the generic Command flag must never substitute for Right Command.
    @Test func leftCommandNeverActsAsTheDictationKey() {
        let tap = EventTap()
        let bothCommands = CGEventFlags(rawValue: 0x10 | 0x20)
        let leftOnly = CGEventFlags(rawValue: 0x20)

        #expect(!tap.handleFlagsChanged(Self.flagsChangedEvent(flags: leftOnly)))
        #expect(!tap.handleFlagsChanged(Self.flagsChangedEvent(flags: bothCommands)))
    }
}
