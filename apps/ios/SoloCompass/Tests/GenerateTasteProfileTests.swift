import XCTest
@testable import SoloCompass

/// Tests for `AIService.generateTasteProfile` (P1.2 #122).
///
/// The implementation is deterministic and on-device — every assertion below
/// reduces to "same inputs ⇒ same outputs" or "more inputs ⇒ higher
/// confidence", with no network or LLM dependency. The vision-LLM upgrade
/// path lives behind a future flag and is not the contract for P1.2.
final class GenerateTasteProfileTests: XCTestCase {

    // MARK: - Determinism

    func testSameInputsProduceIdenticalEmbedding() async {
        let svc = AIService()
        let a = await svc.generateTasteProfile(photos: [], style: .explorer, freeformVibe: "rainy cafes")
        let b = await svc.generateTasteProfile(photos: [], style: .explorer, freeformVibe: "rainy cafes")
        XCTAssertEqual(a.embedding, b.embedding, "deterministic seed must yield byte-identical embedding")
        XCTAssertEqual(a.descriptors, b.descriptors)
        XCTAssertEqual(a.confidence, b.confidence, accuracy: 1e-9)
    }

    func testEmbeddingHasContractDimension64() async {
        let svc = AIService()
        let result = await svc.generateTasteProfile(photos: [], style: .worker, freeformVibe: nil)
        XCTAssertEqual(result.embedding.count, 64, "TasteProfile.embedding contract is 64-dim float vector")
    }

    func testEmbeddingValuesAreInExpectedRange() async {
        let svc = AIService()
        let result = await svc.generateTasteProfile(photos: [], style: .foodie, freeformVibe: nil)
        for value in result.embedding {
            XCTAssertGreaterThanOrEqual(value, -1.0)
            XCTAssertLessThanOrEqual(value, 1.0)
        }
    }

    // MARK: - Style differentiation

    func testDifferentStylesProduceDifferentEmbeddings() async {
        let svc = AIService()
        let explorer = await svc.generateTasteProfile(photos: [], style: .explorer, freeformVibe: nil)
        let foodie = await svc.generateTasteProfile(photos: [], style: .foodie, freeformVibe: nil)
        XCTAssertNotEqual(explorer.embedding, foodie.embedding, "distinct style picks must shift the embedding")
        XCTAssertNotEqual(explorer.descriptors, foodie.descriptors, "distinct style picks must shift the descriptors")
    }

    func testEachStyleHasItsOwnDescriptorVocabulary() async {
        let svc = AIService()
        let allStyles = UserPreferences.SoloTravelStyle.allCases
        var seenDescriptors: Set<[String]> = []
        for style in allStyles {
            let r = await svc.generateTasteProfile(photos: [], style: style, freeformVibe: nil)
            XCTAssertFalse(r.descriptors.isEmpty, "every style must produce at least one descriptor")
            seenDescriptors.insert(r.descriptors)
        }
        XCTAssertEqual(seenDescriptors.count, allStyles.count,
                       "each style must produce a unique descriptor list")
    }

    // MARK: - Vibe injection

    func testFreeformVibeAddsDescriptors() async {
        let svc = AIService()
        let base = await svc.generateTasteProfile(photos: [], style: .worker, freeformVibe: nil)
        let withVibe = await svc.generateTasteProfile(photos: [], style: .worker, freeformVibe: "sunlit reading")
        XCTAssertGreaterThan(withVibe.descriptors.count, base.descriptors.count,
                             "non-empty vibe must contribute at least one descriptor word")
        XCTAssertTrue(withVibe.descriptors.contains("sunlit") || withVibe.descriptors.contains("reading"),
                      "vibe words must appear in the descriptor list (lowercased, letter-split)")
    }

    func testEmptyVibeIsTreatedAsAbsent() async {
        let svc = AIService()
        let blank = await svc.generateTasteProfile(photos: [], style: .explorer, freeformVibe: "   ")
        let absent = await svc.generateTasteProfile(photos: [], style: .explorer, freeformVibe: nil)
        XCTAssertEqual(blank.descriptors, absent.descriptors,
                       "whitespace-only vibe must behave the same as a nil vibe")
        XCTAssertEqual(blank.confidence, absent.confidence, accuracy: 1e-9)
    }

    // MARK: - Confidence schedule

    func testConfidenceFloorIs030ForJustStyle() async {
        let svc = AIService()
        let r = await svc.generateTasteProfile(photos: [], style: .explorer, freeformVibe: nil)
        XCTAssertEqual(r.confidence, 0.30, accuracy: 0.001,
                       "style-only fallback must land at 0.30")
    }

    func testConfidenceRisesWithPhotosAndVibe() async {
        let svc = AIService()
        let minimal = await svc.generateTasteProfile(photos: [], style: .explorer, freeformVibe: nil)
        let richer = await svc.generateTasteProfile(
            photos: [Data([0x01]), Data([0x02]), Data([0x03])],
            style: .explorer,
            freeformVibe: "quiet morning"
        )
        XCTAssertGreaterThan(richer.confidence, minimal.confidence,
                             "richer input (photos + vibe) must produce strictly higher confidence")
    }

    func testConfidenceCapsAt055() async {
        let svc = AIService()
        let saturated = await svc.generateTasteProfile(
            photos: (0..<10).map { Data([UInt8($0)]) },
            style: .foodie,
            freeformVibe: "salt smoke chili"
        )
        XCTAssertLessThanOrEqual(saturated.confidence, 0.55,
                                 "P1.2 fallback must cap at 0.55 — the 0.95 ceiling is reserved for TasteUpdateService")
    }

    func testConfidenceDegradesWhenStyleIsNil() async {
        let svc = AIService()
        let r = await svc.generateTasteProfile(photos: [], style: nil, freeformVibe: nil)
        XCTAssertEqual(r.confidence, 0.20, accuracy: 0.001,
                       "no style + no photos + no vibe is the absolute floor — 0.20")
    }

    // MARK: - Descriptor cap

    func testDescriptorListIsCappedAtFive() async {
        let svc = AIService()
        let r = await svc.generateTasteProfile(
            photos: [],
            style: .cultureSeeker,
            freeformVibe: "warm rainy quiet sunlit arty street"
        )
        XCTAssertLessThanOrEqual(r.descriptors.count, 5,
                                 "descriptor list must stay short — prefix(5) is the contract")
    }

    // MARK: - Helpers stay deterministic

    func testTasteSeedHelperIsStable() {
        let s1 = AIService.tasteSeed(style: .explorer, photoCount: 2, vibe: "rain")
        let s2 = AIService.tasteSeed(style: .explorer, photoCount: 2, vibe: "rain")
        XCTAssertEqual(s1, s2, "seed function must be a pure function of its inputs")
    }

    func testDeterministicEmbeddingHelperHandlesZeroSeed() {
        let v = AIService.deterministicEmbedding(seed: 0, dim: 16)
        XCTAssertEqual(v.count, 16)
        XCTAssertTrue(v.contains(where: { $0 != 0 }), "zero seed must still produce a non-trivial vector")
    }
}
