import XCTest
@testable import SoloCompass

final class FriendAvatarEmojiTests: XCTestCase {

    // (1) Same userId always returns the same emoji across repeated calls.
    func testDeterminismForFixedId() {
        let id = "traveler_abc"
        let first = AvatarEmoji.emoji(for: id)
        for _ in 0..<10 {
            XCTAssertEqual(AvatarEmoji.emoji(for: id), first)
        }
    }

    // (2) Two distinct ids both map into the pool (non-empty result).
    func testDistinctIdsMapIntoPool() {
        let a = AvatarEmoji.emoji(for: "maya")
        let b = AvatarEmoji.emoji(for: "kenji")
        XCTAssertFalse(a.isEmpty)
        XCTAssertFalse(b.isEmpty)
    }

    // (3) Every returned value is a member of the pool.
    func testResultIsAlwaysInPool() {
        let ids = ["alice", "bob", "charlie", "d", "user-123", "🌍-traveler", ""]
        for id in ids {
            let emoji = AvatarEmoji.emoji(for: id)
            XCTAssertTrue(AvatarEmoji.pool.contains(emoji), "\(emoji) not in pool for id '\(id)'")
        }
    }

    // Bonus: verify stableHash is consistent (same value twice).
    func testStableHashIsConsistent() {
        let h1 = AvatarEmoji.stableHash("hello")
        let h2 = AvatarEmoji.stableHash("hello")
        XCTAssertEqual(h1, h2)
    }
}
