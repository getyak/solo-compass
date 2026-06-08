import XCTest
import SwiftUI
@testable import SoloCompass

/// US-013 coverage for the shareable friend code + QR sheet.
///
/// - `FriendCode.generate()` must emit `SOLO-XXXX-XXXX` from the unambiguous
///   alphabet (never `0/O/1/I`).
/// - `AddFriendSheet` must render a real screen (QR + code) rather than a flat
///   band — the "verify QR renders" acceptance step, captured as a /tmp PNG.
@MainActor
final class AddFriendSheetTests: XCTestCase {

    private static let windowSize = CGSize(width: 402, height: 874)

    // MARK: - Code format

    func testGeneratedCodeMatchesSoloFormat() {
        let forbidden: Set<Character> = ["0", "O", "1", "I"]
        for _ in 0..<500 {
            let code = FriendCode.generate().rawValue
            // SOLO-XXXX-XXXX with two 4-char groups.
            let parts = code.split(separator: "-")
            XCTAssertEqual(parts.count, 3, "Unexpected shape: \(code)")
            XCTAssertEqual(parts.first.map(String.init), "SOLO")
            XCTAssertEqual(parts[1].count, 4)
            XCTAssertEqual(parts[2].count, 4)
            // No visually-ambiguous glyphs in the two random groups.
            for ch in (parts[1] + parts[2]) {
                XCTAssertFalse(forbidden.contains(ch), "Code \(code) contains ambiguous '\(ch)'")
            }
        }
    }

    // MARK: - US-014: code format validation

    func testIsValidFormatAcceptsCanonicalCodes() {
        // Generated codes must always pass their own validator.
        for _ in 0..<200 {
            let code = FriendCode.generate().rawValue
            XCTAssertTrue(FriendCode.isValidFormat(code), "Rejected generated code \(code)")
        }
        XCTAssertTrue(FriendCode.isValidFormat("SOLO-7K2F-9XQR"))
    }

    func testIsValidFormatRejectsMalformedOrAmbiguous() {
        let bad = [
            "",                  // empty
            "SOLO-7K2F",         // missing group
            "SOLO-7K2F-9XQRZ",   // group too long
            "NOPE-7K2F-9XQR",    // wrong prefix
            "SOLO-7K2F-9XQ0",    // ambiguous '0'
            "SOLO-7K2F-9XQI",    // ambiguous 'I'
            "solo-7k2f-9xqr",    // lowercase (caller normalises first)
        ]
        for code in bad {
            XCTAssertFalse(FriendCode.isValidFormat(code), "Accepted malformed code '\(code)'")
        }
    }

    // MARK: - Render

    func testAddFriendSheetRendersCodeAndQR() throws {
        let service = FriendService()
        // Seed a cached code so the sheet's lazy load resolves instantly to a
        // deterministic value (no live backend in-process).
        service.myFriendCode = FriendCode(rawValue: "SOLO-7K2F-9XQR")

        let image = try render(content: AddFriendSheet(service: service))
        dump(image, to: "add_friend_sheet")
        XCTAssertFalse(
            isUniformColor(image),
            "AddFriendSheet rendered as a flat band — the QR/code did not lay out."
        )
    }

    func testAddFriendTabRendersScanAndEntry() throws {
        // The add-by-code tab must lay out its scan button + manual-entry field
        // (the "scan via pasted-code fallback" verify path) rather than a band.
        let service = FriendService()
        let image = try render(content: AddFriendSheet(service: service, startInAddFriend: true))
        dump(image, to: "add_friend_redeem_tab")
        XCTAssertFalse(
            isUniformColor(image),
            "Add-friend tab rendered flat — scan/entry controls did not lay out."
        )
    }

    // MARK: - Helpers

    private func dump(_ image: UIImage, to name: String) {
        guard let data = image.pngData() else { return }
        try? data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }

    private func render<Content: View>(content: Content) throws -> UIImage {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        let bounds = CGRect(origin: .zero, size: Self.windowSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    private func isUniformColor(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return true }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        func sample(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = y * bytesPerRow + x * bytesPerPixel
            return (pixels[i], pixels[i + 1], pixels[i + 2])
        }
        let steps = 16
        let first = sample(0, 0)
        let tolerance = 6
        for sy in 0..<steps {
            for sx in 0..<steps {
                let x = min(width - 1, sx * width / steps)
                let y = min(height - 1, sy * height / steps)
                let p = sample(x, y)
                if abs(Int(p.0) - Int(first.0)) > tolerance
                    || abs(Int(p.1) - Int(first.1)) > tolerance
                    || abs(Int(p.2) - Int(first.2)) > tolerance {
                    return false
                }
            }
        }
        return true
    }
}
