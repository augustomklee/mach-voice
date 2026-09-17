import CoreGraphics
import Testing
@testable import MachVoiceKit

/// `EventTap.decide` is the pure decision behind the global CGEventTap.
/// These tests lock in the invariant that let Escape regress silently: Escape
/// has no role in this app unless the Dictation Key is held, so it must pass
/// through untouched the rest of the time.
struct EventTapDecisionTests {
    static let rightCommandFlag: UInt64 = 0x10
    static let leftCommandFlag: UInt64 = 0x20
    static let escapeKeyCode: Int64 = 53
    static let otherKeyCode: Int64 = 0 // 'a'

    @Test func escapeIsIgnoredWhileTheDictationKeyIsNotHeld() {
        let decision = EventTap.decide(type: .keyDown, flags: 0, keyCode: Self.escapeKeyCode, rightCommandWasDown: false)
        #expect(decision == .ignore, "Escape must reach the frontmost application when no Utterance is in progress")
    }

    @Test func escapeCancelsWhileTheDictationKeyIsHeld() {
        let decision = EventTap.decide(type: .keyDown, flags: 0, keyCode: Self.escapeKeyCode, rightCommandWasDown: true)
        #expect(decision == .escapeDown)
    }

    @Test func nonEscapeKeysAreAlwaysIgnored() {
        #expect(EventTap.decide(type: .keyDown, flags: 0, keyCode: Self.otherKeyCode, rightCommandWasDown: true) == .ignore)
        #expect(EventTap.decide(type: .keyDown, flags: 0, keyCode: Self.otherKeyCode, rightCommandWasDown: false) == .ignore)
    }

    @Test func rightCommandAloneStartsAndHoldsTheDictationKey() {
        #expect(EventTap.decide(type: .flagsChanged, flags: Self.rightCommandFlag, keyCode: 0, rightCommandWasDown: false) == .rightCommandDown)
        #expect(EventTap.decide(type: .flagsChanged, flags: Self.rightCommandFlag, keyCode: 0, rightCommandWasDown: true) == .rightCommandHeld)
    }

    @Test func releasingRightCommandEndsTheDictationKey() {
        #expect(EventTap.decide(type: .flagsChanged, flags: 0, keyCode: 0, rightCommandWasDown: true) == .rightCommandUp)
    }

    /// docs/adr/0003: the generic Command flag must never substitute for Right Command.
    @Test func leftCommandNeverActsAsTheDictationKey() {
        let bothCommands = Self.rightCommandFlag | Self.leftCommandFlag
        #expect(EventTap.decide(type: .flagsChanged, flags: Self.leftCommandFlag, keyCode: 0, rightCommandWasDown: false) == .ignore)
        #expect(EventTap.decide(type: .flagsChanged, flags: bothCommands, keyCode: 0, rightCommandWasDown: false) == .ignore)
    }
}
