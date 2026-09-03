// A fixture Target for demonstrating docs/adr/0002 from the running app.
//
// The window holds two fields. The top one is an ordinary NSTextField, the
// Target every Injection is verified against. The bottom one is the case the
// decision record exists for: its Accessibility value reads before a write and
// not after, so the read-back is unreadable and the Injection into it must
// strand rather than retry.
//
// Build:  swiftc -O -o /tmp/UnverifiableTarget Tools/UnverifiableTarget/main.swift
// Bare:   /tmp/UnverifiableTarget            (no bundle, so no application identity)
// Bundle: wrap the binary in an .app with a CFBundleIdentifier to give it one.
//
// This is demo tooling, not part of the package.

import AppKit

/// A text field whose Accessibility value can be read until it is written to.
final class UnverifiableField: NSView {
    private var written = false

    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textField }
    override func accessibilityLabel() -> String? { "Unverifiable field" }
    override func isAccessibilityFocused() -> Bool { window?.firstResponder === self }
    override func setAccessibilityFocused(_ focused: Bool) { if focused { window?.makeFirstResponder(self) } }

    override func accessibilityValue() -> Any? { written ? nil : "" }

    override func setAccessibilityValue(_ value: Any?) {
        written = true
        NSLog("UnverifiableField: setAccessibilityValue(%@); value is unreadable from now on", String(describing: value))
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        selector == #selector(setAccessibilityValue(_:)) || super.isAccessibilitySelectorAllowed(selector)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        (window?.firstResponder === self ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let text = written ? "written; AXValue now unreadable" : "unverifiable field (click me)"
        (text as NSString).draw(at: NSPoint(x: 8, y: 6), withAttributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) { NSLog("UnverifiableField: keyDown %@", event.characters ?? "") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 130))

        let ordinary = NSTextField(frame: NSRect(x: 20, y: 80, width: 380, height: 28))
        ordinary.placeholderString = "ordinary field"
        content.addSubview(ordinary)

        let unverifiable = UnverifiableField(frame: NSRect(x: 20, y: 24, width: 380, height: 28))
        content.addSubview(unverifiable)

        window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = Bundle.main.bundleIdentifier ?? "UnverifiableTarget (no identity)"
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(unverifiable)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
