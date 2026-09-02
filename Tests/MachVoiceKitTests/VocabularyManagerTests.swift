import Testing
@testable import MachVoiceKit

/// VocabularyManager persists to a shared file under Application Support, so these
/// tests check the in-memory result of each call rather than asserting an absolute
/// list, and clean up whatever they add.
///
/// Cleanup is by value and never by index. `#expect` is not fatal, so a test whose
/// expectation just failed still runs its cleanup, and an index computed from the
/// list length would then delete a term the speaker added rather than the term the
/// test added.
@MainActor
struct VocabularyManagerTests {
    @Test func addTrimsSurroundingWhitespace() {
        let manager = VocabularyManager()
        let before = manager.allTerms.count

        manager.add("  Ibiuna Voice Test Term  ")

        #expect(manager.allTerms.count == before + 1)
        #expect(manager.allTerms.last == "Ibiuna Voice Test Term")

        remove("Ibiuna Voice Test Term", from: manager)
    }

    @Test func addRejectsEmptyTerm() {
        let manager = VocabularyManager()
        let before = manager.allTerms

        manager.add("   ")

        #expect(manager.allTerms == before)
    }

    @Test func addRejectsDuplicateTerm() {
        let manager = VocabularyManager()
        let before = manager.allTerms.count

        manager.add("Ibiuna Voice Duplicate Test Term")
        manager.add("Ibiuna Voice Duplicate Test Term")

        #expect(manager.allTerms.count == before + 1)

        remove("Ibiuna Voice Duplicate Test Term", from: manager)
    }

    @Test func addRejectsDuplicatesCaseSensitively() {
        let manager = VocabularyManager()
        let before = manager.allTerms.count

        manager.add("Ibiuna Voice Case Test Term")
        manager.add("ibiuna voice case test term")

        #expect(manager.allTerms.count == before + 2)
        #expect(manager.allTerms.contains("Ibiuna Voice Case Test Term"))
        #expect(manager.allTerms.contains("ibiuna voice case test term"))

        remove("Ibiuna Voice Case Test Term", from: manager)
        remove("ibiuna voice case test term", from: manager)
    }

    private func remove(_ term: String, from manager: VocabularyManager) {
        guard let index = manager.allTerms.firstIndex(of: term) else { return }
        manager.remove(at: index)
    }
}
