import Foundation

/// The decision `EventTap` reaches for one hardware event: consume it and act,
/// or let it pass through untouched. `.escapeDown` only occurs while the
/// Dictation Key is held - Escape has no role in this app otherwise, and must
/// reach the frontmost application unchanged.
enum KeyEvent: Equatable {
    case rightCommandDown
    case rightCommandHeld
    case rightCommandUp
    case escapeDown
    case ignore
}