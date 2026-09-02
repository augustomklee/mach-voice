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

    // CGEventFlag constants for left/right command.
    // Verified: 0x10 is Right Command, 0x20 is Left Command.
    private let rightCommandFlag: UInt64 = 0x10
    private let leftCommandFlag: UInt64 = 0x20

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

    /// Handle modifier flag changes to detect Right Command.
    private func handleFlagsChanged(_ event: CGEvent) -> Bool {
        let flags = event.flags.rawValue

        let rightCommand = (flags & rightCommandFlag) != 0
        let leftCommand = (flags & leftCommandFlag) != 0

        // Only care about Right Command, not Left Command
        if rightCommand && !leftCommand {
            if !rightCommandWasDown {
                rightCommandWasDown = true
                logger.log("Right Command pressed")
                let callback = onKeyDown
                DispatchQueue.main.async {
                    callback?()
                }
            }
            return true // Consume Right Command events
        } else if !rightCommand && rightCommandWasDown {
            rightCommandWasDown = false
            logger.log("Right Command released")
            let callback = onKeyUp
            DispatchQueue.main.async {
                callback?()
            }
            return true // Consume Right Command release
        }

        return false // Let other modifier events pass
    }

    /// Handle key down events to detect Escape.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 53 { // Escape key code
            let callback = onEscape
            DispatchQueue.main.async {
                callback?()
            }
            return true // Consume Escape when it's pressed during an utterance
        }
        return false
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