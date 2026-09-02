import Foundation

/// Remembers which injection mechanism works for each application.
@MainActor
final class InjectionProfile: ObservableObject {
    private var profiles: [String: InjectionMechanism] = [:]
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MachVoice")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("injection-profile.json")

        load()
    }

    /// Get the known mechanism for an app, if any.
    func mechanism(for bundleIdentifier: String) -> InjectionMechanism? {
        profiles[bundleIdentifier]
    }

    /// Learn the mechanism for an app.
    func learn(bundleIdentifier: String, mechanism: InjectionMechanism) {
        profiles[bundleIdentifier] = mechanism
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: InjectionMechanism].self, from: data) else {
            return
        }
        profiles = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: storageURL)
    }
}