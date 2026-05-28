import XCTest
@testable import SoloCompass

@MainActor
final class UserDirectoryTests: XCTestCase {

    // MARK: - loadIfNeeded

    func testLoadIfNeededPopulatesSevenUsers() {
        let dir = UserDirectory.shared
        dir.loadIfNeeded(bundle: Self.seedBundle())

        XCTAssertEqual(dir.count, 7)
        let handles = Set(dir.all.map(\.handle))
        XCTAssertEqual(handles, Set(["maya", "lin", "tomas", "ren", "eira", "kosuke", "yuna"]))
    }

    func testUserLookupByHandle() {
        let dir = UserDirectory.shared
        dir.loadIfNeeded(bundle: Self.seedBundle())

        let maya = dir.user(handle: "maya")
        XCTAssertNotNil(maya)
        XCTAssertEqual(maya?.handle, "maya")
        XCTAssertFalse(maya?.blurb.isEmpty ?? true)
        XCTAssertFalse(maya?.color.isEmpty ?? true)
        XCTAssertGreaterThan(maya?.trips ?? 0, 0)
    }

    func testUserLookupReturnsNilForUnknownHandle() {
        let dir = UserDirectory.shared
        dir.loadIfNeeded(bundle: Self.seedBundle())

        XCTAssertNil(dir.user(handle: "ghost_user_xyz"))
    }

    func testAllUsersHaveWalkedField() {
        let dir = UserDirectory.shared
        dir.loadIfNeeded(bundle: Self.seedBundle())

        for user in dir.all {
            // walked is an array (may be empty) — just ensure it decoded
            XCTAssertNotNil(user.walked, "user \(user.handle) must have walked field")
        }
    }

    // MARK: - Helpers

    private static func seedBundle() -> Bundle {
        let testBundle = Bundle(for: UserDirectoryTests.self)
        if testBundle.url(forResource: "seed_users", withExtension: "json") != nil {
            return testBundle
        }
        return .main
    }
}
