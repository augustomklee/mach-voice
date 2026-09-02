import Foundation

/// The method used to inject a Transcript into the Target.
enum InjectionMechanism: String, Codable, CaseIterable {
    case accessibility
    case paste
    case keystrokes
}