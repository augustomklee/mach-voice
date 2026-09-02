import Foundation

/// Single editable list of terms that bias recognition.
///
/// `allTerms` is what `UtteranceController` hands to `SpeechEngine
/// .startAnalysis(vocabulary:)` at the start of every Utterance. The list is
/// read from `vocabulary.json` once in `init` and nothing re-reads it, so a
/// term added by editing that file by hand only reaches recognition after the
/// app is relaunched.
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

    /// Add a term to the Vocabulary. Surrounding whitespace is trimmed and an
    /// empty term is rejected. A duplicate is rejected case-sensitively, so
    /// "Ibiuna" and "ibiuna" are held as two separate terms.
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