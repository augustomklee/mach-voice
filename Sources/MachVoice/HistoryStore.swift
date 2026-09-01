import Foundation

/// Durable rolling record of Transcripts from the last 30 days.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let storageURL: URL
    private let retentionDays = 30

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MachVoice")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("history.json")

        load()
        purgeOldEntries()
    }

    /// Add a new Transcript to History.
    func add(text: String, success: Bool) {
        let entry = HistoryEntry(text: text, timestamp: Date(), injectionSucceeded: success)
        entries.insert(entry, at: 0)
        purgeOldEntries()
        save()
    }

    private func purgeOldEntries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
        entries.removeAll { $0.timestamp < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL)
    }
}

struct HistoryEntry: Codable, Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let injectionSucceeded: Bool

    private enum CodingKeys: String, CodingKey {
        case id, text, timestamp, injectionSucceeded
    }
}