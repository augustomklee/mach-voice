import Testing
@testable import MachVoiceKit

/// VocabularyManager persists to a shared file under Application Support, so these
/// tests check the in-memory result of each call rather than asserting an absolute
/// list, and clean up whatever they add.
@MainActor
struct VocabularyManagerTests {
    @Test func addTrimsSurroundingWhitespace() {
        let manager = VocabularyManager()
        let before = manager.allTerms.count

        manager.add("  Ibiuna Voice Test Term  ")

        #expect(manager.allTerms.count == before + 1)
        #expect(manager.allTerms.last == "Ibiuna Voice Test Term")

        manager.remove(at: manager.allTerms.count - 1)
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

        manager.remove(at: manager.allTerms.count - 1)
    }
}
