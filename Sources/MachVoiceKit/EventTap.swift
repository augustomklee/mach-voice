import ApplicationServices
import Foundation
import os.log

// Disable strict concurrency for this file - event taps work with low-level C APIs
// that are not designed for Swift's concurrency model.

/// Global event tap that monitors keyboard events and detects the Dictation Key.
///
/// The tap consumes Right Command so it never reaches other applications,
/// and posts only lightweight signals from the callback to avoid being disabled
/// by macOS for slow handlers.
final class EventTap: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.augustomklee.MachVoice", category: "EventTap")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var rightCommandWasDown = false

    // Callback closures
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var onEscape: (() -> Void)?
    private var onDisabled: (() -> Void)?

    /// Install the event tap and register callbacks.
    func install(
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void,
        onEscape: @escaping () -> Void,
        onDisabled: @escaping () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onEscape = onEscape
        self.onDisabled = onDisabled

        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                EventTap.callback(proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap - check Accessibility permissions")
            return
        }

        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.log("Event tap installed successfully")
    }

    /// The event tap callback. Must be a global function for C compatibility.
    private static func callback(
        _ proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        guard let refcon else { return Unmanaged.passRetained(event) }

        let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
        var shouldConsume = false

        switch type {
        case .flagsChanged:
            shouldConsume = tap.handleFlagsChanged(event)
        case .keyDown:
            shouldConsume = tap.handleKeyDown(event)
        case .tapDisabledByUserInput, .tapDisabledByTimeout:
            tap.logger.log("Event tap disabled")
            tap.handleDisabled()
        default:
            break
        }

        // Only consume Right Command events; let everything else pass through
        return shouldConsume ? nil : Unmanaged.passRetained(event)
    }

    /// Escape key code, per the Carbon HIToolbox virtual keycode table (kVK_Escape).
    private static let escapeKeyCode: Int64 = 53

    // CGEventFlag constants for left/right command.
    // Verified: 0x10 is Right Command, 0x20 is Left Command.
    private static let rightCommandFlagMask: UInt64 = 0x10
    private static let leftCommandFlagMask: UInt64 = 0x20

    /// The pure decision behind both handlers below: given the event and whether the
    /// Dictation Key is currently held, what should happen. Kept free of side effects
    /// so it can be tested without a real CGEventTap.
    static func decide(type: CGEventType, flags: UInt64, keyCode: Int64, rightCommandWasDown: Bool) -> KeyEvent {
        switch type {
        case .flagsChanged:
            let rightCommand = (flags & rightCommandFlagMask) != 0
            let leftCommand = (flags & leftCommandFlagMask) != 0

            // Only care about Right Command, not Left Command
            if rightCommand && !leftCommand {
                return rightCommandWasDown ? .rightCommandHeld : .rightCommandDown
            } else if !rightCommand && rightCommandWasDown {
                return .rightCommandUp
            }
            return .ignore // Let other modifier events pass
        case .keyDown:
            // Escape has no role in this app unless the Dictation Key is held.
            if keyCode == escapeKeyCode && rightCommandWasDown {
                return .escapeDown
            }
            return .ignore
        default:
            return .ignore
        }
    }

    /// Handle modifier flag changes to detect Right Command.
    private func handleFlagsChanged(_ event: CGEvent) -> Bool {
        switch EventTap.decide(type: .flagsChanged, flags: event.flags.rawValue, keyCode: 0, rightCommandWasDown: rightCommandWasDown) {
        case .rightCommandDown:
            rightCommandWasDown = true
            logger.log("Right Command pressed")
            let callback = onKeyDown
            DispatchQueue.main.async {
                callback?()
            }
            return true // Consume Right Command events
        case .rightCommandHeld:
            return true // Consume Right Command events
        case .rightCommandUp:
            rightCommandWasDown = false
            logger.log("Right Command released")
            let callback = onKeyUp
            DispatchQueue.main.async {
                callback?()
            }
            return true // Consume Right Command release
        case .escapeDown, .ignore:
            return false
        }
    }

    /// Handle key down events to detect Escape.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch EventTap.decide(type: .keyDown, flags: 0, keyCode: keyCode, rightCommandWasDown: rightCommandWasDown) {
        case .escapeDown:
            let callback = onEscape
            DispatchQueue.main.async {
                callback?()
            }
            return true // Consume Escape only while the Dictation Key is held
        default:
            return false
        }
    }

    /// Handle the tap being disabled and re-arm it.
    private func handleDisabled() {
        let callback = onDisabled
        nonisolated(unsafe) let tap = eventTap
        DispatchQueue.main.async {
            callback?()

            // Simple re-arm logic
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }
}