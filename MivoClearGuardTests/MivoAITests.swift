import XCTest
@testable import Mivo

final class MivoAITests: XCTestCase {
    private func knowledge() throws -> MivoKnowledge {
        let data = Data("""
        {
          "system": "Use the notes. ", "contact": "support@example.com", "safety": "",
          "facts": [{"id": "plus", "kw": ["plus"], "examples": [],
                     "fact": "Mivo Plus costs $5 each month and includes weekly experiments."}],
          "stop": ["the", "a", "and", "is"],
          "weights": {"keyword": 3, "factText": 1, "example": 1},
          "notesPerQuestion": 3,
          "prompts": {"proof": "Review evidence.", "unlock": "Review the reason."}
        }
        """.utf8)
        return try JSONDecoder().decode(MivoKnowledge.self, from: data)
    }

    func testAcceptsAnAnswerGroundedInItsCitedNote() throws {
        let notes = try knowledge()
        XCTAssertEqual(MivoAI.groundedAnswer("[1] Mivo Plus costs $5 each month.", knowledge: notes, notes: notes.facts),
                       "Mivo Plus costs $5 each month.")
    }

    func testInvalidCitationsCannotIndexOutsideTheNotesOrBypassGrounding() throws {
        let notes = try knowledge()
        for tag in ["[-1]", "[\(Int.min)]", "[0]", "[2]", "[\(Int.max)]", "[abc]", ""] {
            let answer = MivoAI.groundedAnswer("\(tag) Mivo Plus costs $99 each month.", knowledge: notes, notes: notes.facts)
            XCTAssertTrue(answer.contains("rather not guess"), tag)
        }
    }

    func testNoMatchingNotesAndEmptyAnswersFallBackWithoutCrashing() throws {
        let notes = try knowledge()
        XCTAssertTrue(MivoAI.groundedAnswer("[1] Mivo Plus", knowledge: notes, notes: []).contains("rather not guess"))
        XCTAssertTrue(MivoAI.groundedAnswer("[1]   ", knowledge: notes, notes: notes.facts).contains("rather not guess"))
    }

    func testRejectsInventedNumbersAndUnrelatedAnswers() throws {
        let notes = try knowledge()
        for reply in ["[1] Mivo Plus costs $99 each month.", "[1] Bananas orbit distant planets."] {
            XCTAssertTrue(MivoAI.groundedAnswer(reply, knowledge: notes, notes: notes.facts).contains("rather not guess"))
        }
    }

    func testBundledKnowledgeIsPresentAndDecodes() throws {
        let notes = try XCTUnwrap(MivoKnowledge.shared)
        XCTAssertFalse(notes.facts.isEmpty)
        XCTAssertFalse(notes.notes(for: "How does studying earn scroll time?").isEmpty)
    }

    func testServiceOutagesUseOnlyTheBundledNoteOrSupportContact() throws {
        let notes = try knowledge()
        let fallback = MivoAI.noteFallback(knowledge: notes, notes: notes.facts)
        XCTAssertTrue(fallback.contains("couldn't reach the AI service"))
        XCTAssertTrue(fallback.hasSuffix(notes.facts[0].fact))
        let unknown = MivoAI.noteFallback(knowledge: notes, notes: [])
        XCTAssertTrue(unknown.contains(notes.contact))
        XCTAssertFalse(unknown.contains("$"))
    }
}
