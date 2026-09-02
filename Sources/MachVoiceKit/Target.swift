import ApplicationServices
import AppKit
import Foundation
import os.log

private let targetLogger = Logger(subsystem: "com.augustomklee.MachVoice", category: "Target")

/// The Target's text field as an Injection reads and writes it.
///
/// `read` reports whether the value could be read at all, separately from
/// what it was, because the read-back after a write is what decides an
/// Injection (docs/adr/0002) and an unreadable read-back is not an empty one.
struct AccessibilityField {
    var read: () -> (value: String?, readable: Bool)
    var write: (String) -> AXError

    /// The field behind a live AXUIElement.
    init(element: AXUIElement) {
        read = {
            var value: AnyObject?
            let error = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            targetLogger.log("readValue: error=\(String(describing: error), privacy: .public)")
            return (value as? String, error == .success)
        }
        write = { value in
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
        }
    }

    init(read: @escaping () -> (value: String?, readable: Bool), write: @escaping (String) -> AXError) {
        self.read = read
        self.write = write
    }
}

/// The application and text field that receives an Utterance.
struct Target {
    let application: AXUIElement?
    let focusedElement: AXUIElement?
    let bundleIdentifier: String?
    /// The focused text field, or nil when the Target exposes none.
    let field: AccessibilityField?

    init(application: AXUIElement?, focusedElement: AXUIElement?, bundleIdentifier: String?) {
        self.init(
            application: application,
            focusedElement: focusedElement,
            bundleIdentifier: bundleIdentifier,
            field: focusedElement.map(AccessibilityField.init(element:))
        )
    }

    init(application: AXUIElement?, focusedElement: AXUIElement?, bundleIdentifier: String?, field: AccessibilityField?) {
        self.application = application
        self.focusedElement = focusedElement
        self.bundleIdentifier = bundleIdentifier
        self.field = field
    }

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
}