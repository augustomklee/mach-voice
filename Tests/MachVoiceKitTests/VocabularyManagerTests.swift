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

    @Test func addRejectsDuplicatesCaseSensitively() {
        let manager = VocabularyManager()
        let before = manager.allTerms.count

        manager.add("Ibiuna Voice Case Test Term")
        manager.add("ibiuna voice case test term")

        #expect(manager.allTerms.count == before + 2)
        #expect(manager.allTerms.contains("Ibiuna Voice Case Test Term"))
        #expect(manager.allTerms.contains("ibiuna voice case test term"))

        manager.remove(at: manager.allTerms.count - 1)
        manager.remove(at: manager.allTerms.count - 1)
    }
}
