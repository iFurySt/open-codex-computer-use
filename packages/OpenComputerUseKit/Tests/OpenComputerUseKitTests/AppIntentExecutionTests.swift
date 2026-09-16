import XCTest
@testable import OpenComputerUseKit

final class AppIntentExecutionTests: XCTestCase {
    func testIdentifierJoinsBundleAndIntent() {
        XCTAssertEqual(AppIntentExecution.identifier(bundleID: "com.apple.Notes", actionID: "CreateNote"), "com.apple.Notes.CreateNote")
        XCTAssertEqual(AppIntentExecution.identifier(bundleID: "com.apple.Notes", actionID: "com.apple.Notes.CreateNote"), "com.apple.Notes.CreateNote")
        XCTAssertEqual(AppIntentExecution.identifier(bundleID: "x", actionID: "is.workflow.actions.alert"), "x.is.workflow.actions.alert")
    }

    func testRunRefusesBuiltInShortcutsActions() {
        XCTAssertThrowsError(try AppIntentExecution.run(bundleID: "is.workflow", actionID: "actions.runshellscript", parameters: [:], input: nil))
    }

    func testIdentifierValidationRejectsPathCharacters() {
        XCTAssertTrue(AppIntentExecution.isValidIdentifier("com.apple.Notes.CreateNote"))
        XCTAssertTrue(AppIntentExecution.isValidIdentifier("is.workflow.actions.run-shortcut_2"))
        for action in ["../../x", "a/b", "a\nb", "..", "com.example..", ".", " ", "", "a b"] {
            XCTAssertFalse(AppIntentExecution.isValidIdentifier(action), action)
        }
    }
}
