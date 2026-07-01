import SwiftUI

/// P3.2 #320: the 5 Solo Brag base card faces.
///
/// The design brief calls for "album-cover-level" backgrounds — no emoji,
/// no cartoon, warm-amber-aligned tone. The final assets from an external
/// illustrator drop into `Assets.xcassets/BragCards/templateA_sun.imageset`
/// etc. (see `Resources/Assets.xcassets/BragCards/README.md`).
///
/// This file ships programmatic **stand-ins** so:
///   • `BragCardView(template:)` can pick a face today,
///   • snapshot tests can lock the 5 layouts before art delivery,
///   • end-users see a designed background instead of a blank card during
///     the interim, and
///   • real PNG replacement is a one-line site swap when art lands.
///
/// Each template uses SwiftUI Canvas + LinearGradient so the render is
/// resolution-independent and stays zero-asset. Deterministic — no
/// `Date()` / `random()` in the render path so snapshots stay stable.

public enum BragCardTemplate: String, CaseIterable, Codable, Hashable, Sendable {
    /// Warm noon light — general-purpose default.
    case sun          = "templateA_sun"
    /// Golden hour through a café window — the "slow afternoon" mood.
    case lateWindow   = "templateB_lateWindow"
    /// Overcast rain on stone streets — introspective walks.
    case rain         = "templateC_rain"
    /// Purple-amber dusk — end-of-day reflection.
    case dusk         = "templateD_dusk"
    /// Still, quiet room — solo-time-at-home archetype.
    case still        = "templateE_still"

    /// Human-readable descriptor for accessibility + share metadata.
    public var displayName: String {
        switch self {
        case .sun:        return "Noon"
        case .lateWindow: return "Late Window"
        case .rain:       return "Rain"
        case .dusk:       return "Dusk"
        case .still:      return "Still"
        }
    }

    /// Deterministic pick for a given seed — used by the composer so the
    /// same city+day pair renders the same face across runs (a returning
    /// user recognizes "their" card).
    public static func deterministic(for seed: String) -> BragCardTemplate {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        let cases = BragCardTemplate.allCases
        return cases[Int(hash % UInt64(cases.count))]
    }
}

/// SwiftUI backdrop for a Brag card. Sized to fit its parent — pin
/// dimensions at the call site so snapshot output is stable.
public struct BragCardTemplateBackground: View {
    public let template: BragCardTemplate

    public init(_ template: BragCardTemplate) {
        self.template = template
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                baseGradient
                accentOverlay(in: geo.size)
            }
        }
    }

    // MARK: - Per-template gradient

    @ViewBuilder private var baseGradient: some View {
        switch template {
        case .sun:
            LinearGradient(
                colors: [
                    Color(red: 0xFB/255, green: 0xEF/255, blue: 0xD8/255),
                    Color(red: 0xF6/255, green: 0xD6/255, blue: 0xA0/255),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .lateWindow:
            LinearGradient(
                colors: [
                    Color(red: 0xF9/255, green: 0xE6/255, blue: 0xC5/255),
                    Color(red: 0xC9/255, green: 0x84/255, blue: 0x3F/255),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .rain:
            LinearGradient(
                colors: [
                    Color(red: 0xDF/255, green: 0xDF/255, blue: 0xE1/255),
                    Color(red: 0x8B/255, green: 0x8E/255, blue: 0x95/255),
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .dusk:
            LinearGradient(
                colors: [
                    Color(red: 0x8A/255, green: 0x4A/255, blue: 0x66/255),
                    Color(red: 0x3B/255, green: 0x2C/255, blue: 0x4A/255),
                ],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
        case .still:
            LinearGradient(
                colors: [
                    Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE9/255),
                    Color(red: 0xE3/255, green: 0xDA/255, blue: 0xCC/255),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Per-template accent overlay (deterministic, no randomness)

    @ViewBuilder
    private func accentOverlay(in size: CGSize) -> some View {
        switch template {
        case .sun:
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: size.width * 0.55, height: size.width * 0.55)
                .offset(x: size.width * 0.28, y: -size.height * 0.22)
                .blur(radius: 30)
        case .lateWindow:
            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(width: size.width * 0.16)
                .offset(x: -size.width * 0.22)
                .rotationEffect(.degrees(-6))
                .blur(radius: 18)
        case .rain:
            Canvas { ctx, csize in
                let spacing = csize.width / 8
                for i in 0..<7 {
                    let x = CGFloat(i) * spacing
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + csize.width * 0.15,
                                             y: csize.height))
                    ctx.stroke(path, with: .color(Color.white.opacity(0.16)),
                               lineWidth: 1.4)
                }
            }
        case .dusk:
            Circle()
                .fill(Color(red: 0xF9/255, green: 0xD6/255, blue: 0x9E/255).opacity(0.35))
                .frame(width: size.width * 0.42, height: size.width * 0.42)
                .offset(x: -size.width * 0.24, y: size.height * 0.16)
                .blur(radius: 22)
        case .still:
            Rectangle()
                .fill(Color(red: 0xB8/255, green: 0xA6/255, blue: 0x88/255).opacity(0.4))
                .frame(height: 1.2)
                .offset(y: size.height * 0.28)
        }
    }
}

#Preview("Sun")        { BragCardTemplateBackground(.sun).frame(width: 320, height: 480) }
#Preview("Late Window") { BragCardTemplateBackground(.lateWindow).frame(width: 320, height: 480) }
#Preview("Rain")       { BragCardTemplateBackground(.rain).frame(width: 320, height: 480) }
#Preview("Dusk")       { BragCardTemplateBackground(.dusk).frame(width: 320, height: 480) }
#Preview("Still")      { BragCardTemplateBackground(.still).frame(width: 320, height: 480) }
