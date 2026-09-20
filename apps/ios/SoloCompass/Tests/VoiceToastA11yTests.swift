import XCTest
import SwiftUI
import UIKit
@testable import SoloCompass

/// US-008: The voice-processing toast must announce itself to VoiceOver. It
/// carries the `.updatesFrequently` accessibility trait so assistive
/// technologies treat it as live, frequently-updating content, and it posts a
/// `UIAccessibility` announcement on appear / text change (exercised manually
/// in the Simulator).
///
/// SwiftUI's view tree is opaque, so instead of reflecting over `body` we render
/// the toast in a real `UIWindow` and inspect the accessibility elements UIKit
/// actually exposes through the public `UIAccessibilityContainer` APIs. The
/// previous `Mirror`-based walk broke on iOS 26 even though production applies
/// the trait; this asserts the *rendered* accessibility output.
@MainActor
final class VoiceToastA11yTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        super.tearDown()
    }

    func testToastViewTreeContainsUpdatesFrequentlyTrait() throws {
        let text = "Thinking about “coffee”…"
        let host = UIHostingController(rootView: VoiceProcessingToast(text: text))
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        }
        let window = try XCTUnwrap(self.window)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Give SwiftUI a beat to materialize its accessibility elements.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let elements = Self.accessibilityElements(in: host.view)
        let toast: ElementSnapshot? = elements.first { element in
            element.identifier == "voiceProcessingToast"
                || (element.label?.contains("coffee") ?? false)
        }
        let resolved = try XCTUnwrap(
            toast,
            "the rendered toast must expose an accessibility element; "
                + "found \(elements.count) element(s).\n" + Self.diagnostics(for: host.view)
        )
        XCTAssertTrue(
            resolved.traits.contains(.updatesFrequently),
            "rendered toast must carry the .updatesFrequently accessibility trait "
                + "so VoiceOver announces its live updates"
        )
    }

    func testLocalizedTextTruncatesLongTranscript() {
        let long = String(repeating: "a", count: 200)
        let text = VoiceProcessingToast.localizedText(for: long)
        // The format string interpolates the truncated transcript; the result
        // must not contain the full 200-char input.
        XCTAssertFalse(text.contains(long), "transcript should be truncated")
        XCTAssertFalse(text.isEmpty)
    }

    func testVoiceProcessingLocalizationKeyResolves() {
        let value = NSLocalizedString("voice.processing", comment: "")
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(
            value, "voice.processing",
            "voice.processing must resolve to a real localized string"
        )
    }

    // MARK: - Rendered accessibility traversal

    /// The public accessibility surface of one rendered element.
    struct ElementSnapshot {
        let identifier: String?
        let label: String?
        let traits: UIAccessibilityTraits
    }

    /// Collects the accessibility elements UIKit exposes for `root` using the
    /// public `UIAccessibilityContainer` accessors (`accessibilityElements`,
    /// `accessibilityElementCount()` / `accessibilityElement(at:)`) plus plain
    /// subviews, de-duplicated by identity.
    static func accessibilityElements(in root: UIView) -> [ElementSnapshot] {
        var snapshots: [ObjectIdentifier: ElementSnapshot] = [:]
        var visited = Set<ObjectIdentifier>()

        func record(_ object: NSObject, vended: Bool) {
            let key = ObjectIdentifier(object)
            guard snapshots[key] == nil else { return }
            if object is UIAccessibilityElement {
                snapshots[key] = snapshot(object)
            } else if let view = object as? UIView, view.isAccessibilityElement {
                snapshots[key] = snapshot(object)
            } else if vended {
                // SwiftUI vends private accessibility-element objects that are
                // not `UIAccessibilityElement` subclasses but still implement
                // the NSObject accessibility surface.
                snapshots[key] = snapshot(object)
            }
        }

        func collect(_ object: NSObject, vended: Bool) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            record(object, vended: vended)

            guard let view = object as? UIView else { return }
            if let children = view.accessibilityElements {
                for child in children {
                    if let child = child as? NSObject { collect(child, vended: true) }
                }
            }
            let count = view.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count {
                    if let element = view.accessibilityElement(at: index) as? NSObject {
                        collect(element, vended: true)
                    }
                }
            }
            for subview in view.subviews { collect(subview, vended: false) }
        }

        collect(root, vended: false)
        return Array(snapshots.values)
    }

    /// Best-effort snapshot of the NSObject accessibility surface (shared by
    /// `UIView`, `UIAccessibilityElement`, and SwiftUI's private elements).
    static func snapshot(_ object: NSObject) -> ElementSnapshot {
        ElementSnapshot(
            identifier: (object as? UIAccessibilityIdentification)?.accessibilityIdentifier,
            label: object.accessibilityLabel,
            traits: object.accessibilityTraits
        )
    }

    /// Human-readable snapshot of the hosting view hierarchy for failure
    /// diagnostics (not an assertion by itself).
    static func diagnostics(for root: UIView) -> String {
        func describe(_ object: NSObject) -> String {
            if let element = object as? UIAccessibilityElement {
                return "UIAccessibilityElement id=\(element.accessibilityIdentifier ?? "-") "
                    + "label=\(element.accessibilityLabel ?? "-") traits=\(element.accessibilityTraits.rawValue)"
            }
            if let view = object as? UIView {
                return "\(type(of: view)) id=\(view.accessibilityIdentifier ?? "-") "
                    + "isElement=\(view.isAccessibilityElement) "
                    + "elements=\(view.accessibilityElements?.count.description ?? "nil") "
                    + "count=\(view.accessibilityElementCount()) "
                    + "subviews=\(view.subviews.count) "
                    + "label=\(view.accessibilityLabel ?? "-") traits=\(view.accessibilityTraits.rawValue)"
            }
            return String(describing: type(of: object))
        }

        var lines: [String] = ["root: \(describe(root))"]
        func walk(_ view: UIView, depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            for subview in view.subviews {
                lines.append(pad + describe(subview))
                walk(subview, depth: depth + 1)
            }
        }
        walk(root, depth: 1)
        return lines.joined(separator: "\n")
    }
}
