import SwiftUI
import UIKit

// MARK: - RouteShareSheet

/// The route share entry point. Lets the traveler pick between a map-basemap
/// card, a minimal vector trace card, and a plain-text summary, preview it,
/// then hand it to the system share sheet.
///
/// `RouteSharePayload`, `RouteShareCardView`, and `RouteShareRenderer` live in
/// `Views/Companion/Share/`.
struct RouteShareSheet: View {
    let payload: RouteSharePayload

    @Environment(\.dismiss) private var dismiss

    @State private var selectedStyle: RouteShareStyle = .map
    @State private var previewImage: UIImage? = nil
    @State private var isRendering = false
    @State private var activityItems: [Any]? = nil
    @State private var statusMessage: String? = nil
    @State private var statusIsError = false
    /// Cache rendered cards per style so flipping back and forth is instant.
    @State private var renderedCache: [RouteShareStyle: UIImage] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                stylePicker
                previewArea
                if let status = statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.green)
                        .multilineTextAlignment(.center)
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

    // MARK: - Style picker

    private var stylePicker: some View {
        HStack(spacing: 10) {
            ForEach(RouteShareStyle.allCases) { style in
                Button {
                    selectedStyle = style
                    statusMessage = nil
                } label: {
                    Text(style.label)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selectedStyle == style ? Color.accentColor : Color(.secondarySystemBackground))
                        )
                        .foregroundStyle(selectedStyle == style ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewArea: some View {
        if selectedStyle == .text {
            textPreview
        } else {
            cardPreview
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
        .task(id: selectedStyle) { await renderPreview() }
    }

    @MainActor
    private func renderPreview() async {
        guard selectedStyle.isVisualCard else { return }
        if let cached = renderedCache[selectedStyle] {
            previewImage = cached
            return
        }
        previewImage = nil
        isRendering = true
        let result = await RouteShareRenderer.render(payload: payload, style: selectedStyle)
        isRendering = false
        // Cache under both requested and effective style so a fallback isn't re-fetched.
        renderedCache[selectedStyle] = result.image
        renderedCache[result.effectiveStyle] = result.image
        previewImage = result.image
        if result.didFallback {
            flashStatus(NSLocalizedString("route.share.mapFallback", comment: "Map basemap unavailable hint"), error: false)
        }
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
        if selectedStyle == .text {
            textActions
        } else {
            cardActions
        }
    }

    private var cardActions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await shareCard() }
            } label: {
                Label(
                    NSLocalizedString("share.systemShare", comment: "Share via system sheet"),
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRendering)

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
            .disabled(previewImage == nil)

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

    @MainActor
    private func shareCard() async {
        do {
            let (url, result) = try await RouteShareRenderer.renderTempPNG(payload: payload, style: selectedStyle)
            renderedCache[result.effectiveStyle] = result.image
            activityItems = [url]
        } catch {
            flashStatus(NSLocalizedString("share.renderFailed", comment: "Render failed"), error: true)
        }
    }

    private func copyImage() {
        guard let image = previewImage else {
            flashStatus(NSLocalizedString("share.renderFailed", comment: "Render failed"), error: true)
            return
        }
        UIPasteboard.general.image = image
        flashStatus(NSLocalizedString("share.imageCopied", comment: "Image copied"), error: false)
    }

    private func flashStatus(_ message: String, error: Bool) {
        withAnimation { statusMessage = message; statusIsError = error }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
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
    RouteShareSheet(payload: .preview)
}
