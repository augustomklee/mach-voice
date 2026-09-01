import Foundation

/// Single editable list of terms that bias recognition.
@MainActor
final class VocabularyManager: ObservableObject {
    @Published private(set) var terms: [String] = []

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MachVoice")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("vocabulary.json")

        load()
    }

    /// All terms as a single array.
    var allTerms: [String] { terms }

    /// Add a term to the Vocabulary.
    func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !terms.contains(trimmed) else { return }
        terms.append(trimmed)
        save()
    }

    /// Remove a term from the Vocabulary.
    func remove(at index: Int) {
        terms.remove(at: index)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        terms = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(terms) else { return }
        try? data.write(to: storageURL)
    }
}