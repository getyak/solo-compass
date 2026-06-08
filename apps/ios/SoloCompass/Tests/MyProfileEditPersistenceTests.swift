import XCTest
@testable import SoloCompass

/// US-008: MyProfileEditView upgrade — verifies that editing the display
/// handle and avatar emoji persists across a relaunch (a fresh
/// `UserPreferences` reading the same UserDefaults suite).
final class MyProfileEditPersistenceTests: XCTestCase {

    func testDisplayHandleDefaultsToEmpty() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let prefs = UserPreferences(defaults: defaults)
        XCTAssertEqual(prefs.displayHandle, "")
    }

    func testHandleAndEmojiPersistAcrossReopen() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let prefs = UserPreferences(defaults: defaults)
        prefs.displayHandle = "wanderer"
        prefs.companionAvatarEmoji = "🌊"

        // Simulate relaunch: a brand-new instance reading the same blob.
        let reloaded = UserPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.displayHandle, "wanderer")
        XCTAssertEqual(reloaded.companionAvatarEmoji, "🌊")
    }

    func testHandleValidationBounds() {
        // Length rules mirror MyProfileEditView: empty OR 2...20 inclusive.
        func isValid(_ s: String) -> Bool {
            let count = s.trimmingCharacters(in: .whitespacesAndNewlines).count
            return count == 0 || (count >= 2 && count <= 20)
        }
        XCTAssertTrue(isValid(""))            // cleared
        XCTAssertFalse(isValid("a"))          // too short
        XCTAssertTrue(isValid("ab"))          // min
        XCTAssertTrue(isValid(String(repeating: "x", count: 20)))  // max
        XCTAssertFalse(isValid(String(repeating: "x", count: 21))) // too long
    }
}
