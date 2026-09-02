import ApplicationServices
import AppKit
import Foundation
import os.log

private let targetLogger = Logger(subsystem: "com.augustomklee.MachVoice", category: "Target")

/// The application and text field that receives an Utterance.
struct Target {
    let application: AXUIElement?
    let focusedElement: AXUIElement?
    let bundleIdentifier: String?

    /// Capture the Target at key-down.
    ///
    /// Uses the frontmost application's PID (via NSWorkspace) rather than the
    /// system-wide focused application attribute, which can be stale or nil
    /// depending on how the frontmost app manages its accessibility tree.
    static func capture() -> Target {
        let system = AXUIElementCreateSystemWide()
        var focusedAppRef: AnyObject?
        let appError = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedAppRef)

        var bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var appPID: pid_t = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0

        let focusedApp = focusedAppRef as! AXUIElement?
        if appError == .success, let focusedApp {
            var pid: pid_t = 0
            AXUIElementGetPid(focusedApp, &pid)
            if pid != 0 {
                appPID = pid
                if let runningApp = NSRunningApplication(processIdentifier: pid) {
                    bundleID = runningApp.bundleIdentifier
                }
            }
        }

        // Prefer asking the app-specific AXUIElement for its focused UI element,
        // falling back to the system-wide one.
        var focusedElementRef: AnyObject?
        var elementError: AXError = .cannotComplete

        if appPID != 0 {
            let appElement = AXUIElementCreateApplication(appPID)
            elementError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        }

        if elementError != .success {
            elementError = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        }

        targetLogger.log("capture: appError=\(String(describing: appError), privacy: .public) elementError=\(String(describing: elementError), privacy: .public) bundleID=\(bundleID ?? "nil", privacy: .public) hasElement=\(focusedElementRef != nil)")

        return Target(
            application: focusedApp,
            focusedElement: focusedElementRef as! AXUIElement?,
            bundleIdentifier: bundleID
        )
    }

    /// Get the current text value of the focused element, and whether it was readable at all.
    func readValue() -> (value: String?, readable: Bool) {
        guard let focusedElement else { return (nil, false) }
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &value)
        targetLogger.log("readValue: error=\(String(describing: error), privacy: .public)")
        return (value as? String, error == .success)
    }

    /// Get the current text value of the focused element.
    func currentValue() -> String? {
        readValue().value
    }
}