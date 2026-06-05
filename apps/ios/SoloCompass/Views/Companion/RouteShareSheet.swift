import SwiftUI
import UIKit

// MARK: - RouteSharePayload

/// Pure-data input to the route share card. Decoupled from `Route` so the card
/// can be previewed / rendered without standing up the experience service, and
/// so the visual layer never reaches back into model logic.
struct RouteSharePayload: Hashable {
    let title: String
    let summary: String
    let placeLabel: String          // region / city, already human-readable
    let category: ExperienceCategory // drives gradient + emoji (mirrors RouteDetailView hero)
    let durationMinutes: Int
    let distanceMeters: Int
    let paceLabel: String
    let stopCount: Int
    let walkedByCount: Int
    let tags: [String]
    let brandHandle: String

    init(
        title: String,
        summary: String,
        placeLabel: String,
        category: ExperienceCategory,
        durationMinutes: Int,
        distanceMeters: Int,
        paceLabel: String,
        stopCount: Int,
        walkedByCount: Int,
        tags: [String],
        brandHandle: String = "solocompass.app"
    ) {
        self.title = title
        self.summary = summary
        self.placeLabel = placeLabel
        self.category = category
        self.durationMinutes = durationMinutes
        self.distanceMeters = distanceMeters
        self.paceLabel = paceLabel
        self.stopCount = stopCount
        self.walkedByCount = walkedByCount
        self.tags = Array(tags.prefix(3))
        self.brandHandle = brandHandle
    }

    /// Build from a `Route` plus its resolved primary category and stop count.
    init(route: Route, category: ExperienceCategory, stopCount: Int) {
        self.init(
            title: route.title,
            summary: route.summary,
            placeLabel: route.region.isEmpty ? route.cityCode : route.region,
            category: category,
            durationMinutes: route.estimatedDuration,
            distanceMeters: route.distanceMeters,
            paceLabel: route.pace.localizedLabel,
            stopCount: stopCount,
            walkedByCount: route.verification.walkedByCount,
            tags: route.tags
        )
    }

    /// Human distance: "1.2 km" above 1000 m, else "650 m".
    var distanceLabel: String {
        if distanceMeters >= 1000 {
            let km = Double(distanceMeters) / 1000
            return String(format: "%.1f km", km)
        }
        return "\(distanceMeters) m"
    }

    /// Multi-line plain-text share body — the "copy as text" / fallback path.
    var shareText: String {
        var lines: [String] = []
        lines.append("🧭 \(title)")
        if !summary.isEmpty { lines.append(summary) }
        var facts: [String] = []
        if !placeLabel.isEmpty { facts.append("📍 \(placeLabel)") }
        facts.append("⏱ \(durationMinutes) min")
        facts.append("📏 \(distanceLabel)")
        facts.append("👣 \(stopCount) \(NSLocalizedString("route.share.stops", comment: "stops unit"))")
        lines.append(facts.joined(separator: "  ·  "))
        if walkedByCount > 0 {
            let fmt = NSLocalizedString("route.share.walkedBy", comment: "walked-by social proof")
            lines.append(String(format: fmt, walkedByCount))
        }
        if !tags.isEmpty {
            lines.append(tags.map { "#\($0)" }.joined(separator: " "))
        }
        lines.append("— \(brandHandle)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - RouteShareCardView

/// 1080×1920 portrait share card for a route. Mirrors the `RouteDetailView`
/// hero language (category gradient + emoji) so a shared image reads as the
/// same product. Laid out at half-pixel `renderSize`; `ImageRenderer` scales up.
struct RouteShareCardView: View {
    let payload: RouteSharePayload

    /// On-screen render size in points (half of the 1080×1920 pixel target).
    static let renderSize = CGSize(width: 540, height: 960)
    static let renderScale: CGFloat = 2.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CategoryVisual.gradient(for: payload.category)

            // Subtle scrim so bottom text stays legible over bright gradients.
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                // Top: emoji + brand
                HStack(alignment: .top) {
                    Text(CategoryVisual.emoji(for: payload.category))
                        .font(.system(size: 64))
                    Spacer()
                    Text(NSLocalizedString("route.share.kicker", comment: "Route share card kicker"))
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer(minLength: 0)

                // Bottom block: title, summary, stats, tags, walked-by, brand
                VStack(alignment: .leading, spacing: 18) {
                    if !payload.placeLabel.isEmpty {
                        Label(payload.placeLabel, systemImage: "mappin.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text(payload.title)
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)

                    if !payload.summary.isEmpty {
                        Text(payload.summary)
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    statRow

                    if payload.walkedByCount > 0 {
                        let fmt = NSLocalizedString("route.share.walkedBy", comment: "walked-by social proof")
                        Text(String(format: fmt, payload.walkedByCount))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    if !payload.tags.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(payload.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(.white.opacity(0.2)))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    Text(payload.brandHandle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.top, 4)
                }
            }
            .padding(40)
        }
        .frame(width: Self.renderSize.width, height: Self.renderSize.height)
    }

    /// Three glass stat chips: duration · distance · stops.
    private var statRow: some View {
        HStack(spacing: 12) {
            statChip(icon: "clock.fill", value: "\(payload.durationMinutes)",
                     unit: NSLocalizedString("route.share.min", comment: "minutes unit"))
            statChip(icon: "ruler.fill", value: payload.distanceLabel, unit: "")
            statChip(icon: "figure.walk", value: "\(payload.stopCount)",
                     unit: NSLocalizedString("route.share.stops", comment: "stops unit"))
        }
    }

    private func statChip(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
            Text(value)
                .font(.system(size: 22, weight: .bold))
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 16, weight: .medium))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(.white.opacity(0.2)))
    }
}

// MARK: - RouteShareRenderer

/// Renders `RouteShareCardView` to a `UIImage` / temp PNG. Mirrors
/// `ShareCardRenderer` so both share surfaces share the same pipeline shape.
@MainActor
enum RouteShareRenderer {
    enum RenderError: Error {
        case imageGenerationFailed
        case pngEncodingFailed
        case fileWriteFailed
    }

    static func renderImage(payload: RouteSharePayload) throws -> UIImage {
        let view = RouteShareCardView(payload: payload)
        let renderer = ImageRenderer(content: view)
        renderer.scale = RouteShareCardView.renderScale
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw RenderError.imageGenerationFailed }
        return image
    }

    static func renderTempPNG(payload: RouteSharePayload) throws -> URL {
        let image = try renderImage(payload: payload)
        guard let data = image.pngData() else { throw RenderError.pngEncodingFailed }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "solocompass-route-\(UUID().uuidString.prefix(8)).png"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RenderError.fileWriteFailed
        }
        return url
    }
}

// MARK: - RouteShareSheet

/// The route share entry point. Lets the traveler pick between a visual card
/// (image) and a plain-text summary, preview it, then hand it to the system
/// share sheet. Replaces the bare `ShareLink(item: title)` that only shared a
/// title string.
struct RouteShareSheet: View {
    let payload: RouteSharePayload

    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: Mode = .card
    @State private var previewImage: UIImage? = nil
    @State private var activityItems: [Any]? = nil
    @State private var statusMessage: String? = nil
    @State private var statusIsError = false

    enum Mode: String, CaseIterable, Identifiable {
        case card
        case text

        var id: String { rawValue }
        var label: String {
            switch self {
            case .card: return NSLocalizedString("route.share.mode.card", comment: "Visual card mode")
            case .text: return NSLocalizedString("route.share.mode.text", comment: "Plain text mode")
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                modePicker
                previewArea
                if let status = statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.green)
                        .transition(.opacity)
                }
                actionButtons
            }
            .padding(20)
            .navigationTitle(NSLocalizedString("route.share.title", comment: "Share route"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.close", comment: "Close")) { dismiss() }
                }
            }
        }
        .sheet(item: Binding(
            get: { activityItems.map { RouteActivityPayload(items: $0) } },
            set: { if $0 == nil { activityItems = nil } }
        )) { payload in
            RouteActivityViewControllerWrapper(items: payload.items)
        }
        .presentationDetents([.large])
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(Mode.allCases) { mode in
                Button {
                    selectedMode = mode
                    statusMessage = nil
                } label: {
                    Text(mode.label)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selectedMode == mode ? Color.accentColor : Color(.secondarySystemBackground))
                        )
                        .foregroundStyle(selectedMode == mode ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewArea: some View {
        switch selectedMode {
        case .card: cardPreview
        case .text: textPreview
        }
    }

    private var cardPreview: some View {
        let aspect = RouteShareCardView.renderSize.width / RouteShareCardView.renderSize.height
        return ZStack {
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await renderPreview() }
    }

    @MainActor
    private func renderPreview() async {
        if previewImage != nil { return }
        previewImage = try? RouteShareRenderer.renderImage(payload: payload)
    }

    private var textPreview: some View {
        ScrollView {
            Text(payload.shareText)
                .font(.system(.body))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionButtons: some View {
        switch selectedMode {
        case .card: cardActions
        case .text: textActions
        }
    }

    private var cardActions: some View {
        VStack(spacing: 10) {
            Button {
                shareCard()
            } label: {
                Label(
                    NSLocalizedString("share.systemShare", comment: "Share via system sheet"),
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                copyImage()
            } label: {
                Label(
                    NSLocalizedString("share.copyImage", comment: "Copy image"),
                    systemImage: "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text(NSLocalizedString("share.saveHint", comment: "Hint to use Save Image in the system share sheet"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var textActions: some View {
        VStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = payload.shareText
                flashStatus(NSLocalizedString("share.copied", comment: "Copied"), error: false)
            } label: {
                Label(
                    NSLocalizedString("export.copy", comment: "Copy text"),
                    systemImage: "doc.on.clipboard"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                activityItems = [payload.shareText]
            } label: {
                Label(
                    NSLocalizedString("export.share", comment: "Share…"),
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Impl

    private func shareCard() {
        do {
            let url = try RouteShareRenderer.renderTempPNG(payload: payload)
            activityItems = [url]
        } catch {
            flashStatus(NSLocalizedString("share.renderFailed", comment: "Render failed"), error: true)
        }
    }

    private func copyImage() {
        do {
            let image = try RouteShareRenderer.renderImage(payload: payload)
            UIPasteboard.general.image = image
            flashStatus(NSLocalizedString("share.imageCopied", comment: "Image copied"), error: false)
        } catch {
            flashStatus(NSLocalizedString("share.renderFailed", comment: "Render failed"), error: true)
        }
    }

    private func flashStatus(_ message: String, error: Bool) {
        withAnimation { statusMessage = message; statusIsError = error }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { statusMessage = nil }
        }
    }
}

// MARK: - ActivityViewController bridging

private struct RouteActivityPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct RouteActivityViewControllerWrapper: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    RouteShareSheet(payload: RouteSharePayload(
        title: "黄昏河岸慢走",
        summary: "从老城咖啡馆出发，沿河散步到日落观景台，途经三处隐藏角落。",
        placeLabel: "Bangkok",
        category: .coffee,
        durationMinutes: 120,
        distanceMeters: 2400,
        paceLabel: "Relaxed",
        stopCount: 4,
        walkedByCount: 37,
        tags: ["sunset", "riverside", "coffee"]
    ))
}
