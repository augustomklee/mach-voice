import CoreGraphics
import Foundation
// usage: rcmd down|up|tap <seconds>
let src = CGEventSource(stateID: .hidSystemState)
func post(_ down: Bool) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: 0x36, keyDown: down)!
    e.type = .flagsChanged
    e.flags = down ? CGEventFlags(rawValue: 0x100000 | 0x10 | 0x100) : CGEventFlags(rawValue: 0x100)
    e.post(tap: .cghidEventTap)
}
let args = CommandLine.arguments
switch args[1] {
case "down": post(true)
case "up": post(false)
default:
    post(true)
    Thread.sleep(forTimeInterval: Double(args.count > 2 ? args[2] : "1")!)
    post(false)
}
