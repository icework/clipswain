import XCTest
@testable import PaperclipKit

final class AgentBudgetTests: XCTestCase {
    func testDollarsTextKeepsCents() {
        XCTAssertEqual(AgentBudget.dollarsText(cents: 1250), "12.50")
        XCTAssertEqual(AgentBudget.dollarsText(cents: 1205), "12.05")
        XCTAssertEqual(AgentBudget.dollarsText(cents: 1200), "12")
        XCTAssertEqual(AgentBudget.dollarsText(cents: nil), "0")
    }

    func testParsing() {
        XCTAssertEqual(AgentBudget.cents(fromDollars: "12.5"), 1250)
        XCTAssertEqual(AgentBudget.cents(fromDollars: "12,05"), 1205)
        XCTAssertEqual(AgentBudget.cents(fromDollars: "12"), 1200)
        XCTAssertEqual(AgentBudget.cents(fromDollars: ".5"), 50)
        XCTAssertEqual(AgentBudget.cents(fromDollars: ""), 0)
        XCTAssertNil(AgentBudget.cents(fromDollars: "12.505"))
        XCTAssertNil(AgentBudget.cents(fromDollars: "-3"))
        XCTAssertNil(AgentBudget.cents(fromDollars: "abc"))
    }

    func testRoundTripIsLossless() {
        for cents in [0, 5, 99, 100, 1250, 123_456] {
            XCTAssertEqual(AgentBudget.cents(fromDollars: AgentBudget.dollarsText(cents: cents)), cents)
        }
    }
}

final class InstructionsWriteTests: XCTestCase {
    private func encode(_ write: AgentInstructionsFileWrite) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: PaperclipJSON.encoder.encode(write))
    }

    func testNewEntryFileSendsNullBase() throws {
        let json = try encode(AgentInstructionsFileWrite(path: "AGENTS.md", content: "x"))
        XCTAssertEqual(json["baseRevisionId"], .null)
        XCTAssertNil(json["baseHash"])
    }

    func testEditingSavedEntryUsesItsRevision() throws {
        // The file as re-read after the first save of a new entry: it now has a revision.
        var saved = AgentInstructionsFile(path: "AGENTS.md", content: "v1", isEntryFile: true, editable: true)
        saved.revision = AgentInstructionRevision(id: "rev-1")
        let json = try encode(.editing(saved, content: "v2", bundleMode: "managed"))
        XCTAssertEqual(json["baseRevisionId"], .string("rev-1"))
        XCTAssertNil(json["baseHash"])
    }

    func testEditingOtherManagedFileUsesHash() throws {
        var file = AgentInstructionsFile(path: "notes.md", content: "a", isEntryFile: false, editable: true)
        file.contentHash = String(repeating: "a", count: 64)
        let json = try encode(.editing(file, content: "b", bundleMode: "managed"))
        XCTAssertEqual(json["baseHash"], .string(String(repeating: "a", count: 64)))
        XCTAssertNil(json["baseRevisionId"])
    }

    func testExternalEntryFileIsReadOnly() {
        let entry = AgentInstructionsFile(path: "AGENTS.md", content: "", isEntryFile: true, editable: true)
        XCTAssertFalse(entry.isWritable(bundleMode: "external"))
        XCTAssertTrue(entry.isWritable(bundleMode: "managed"))
        let other = AgentInstructionsFile(path: "notes.md", content: "", isEntryFile: false, editable: true)
        XCTAssertTrue(other.isWritable(bundleMode: "external"))
        let locked = AgentInstructionsFile(path: "x.md", content: "", isEntryFile: false, editable: false)
        XCTAssertFalse(locked.isWritable(bundleMode: "managed"))
    }
}
