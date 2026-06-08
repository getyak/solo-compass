import SwiftUI
import UIKit

// Wrapper so we can use .sheet(item:) without making String Identifiable
struct ExportPayload: Identifiable {
    let id = UUID()
    let markdown: String
}

/// Share sheet for Markdown PKM export (US-037).
/// Presents copy, Notion Web Clipper, and system share.
struct MarkdownShareSheet: View {
    let markdown: String
    let title: String
    let notionURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var showActivityVC = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(NSLocalizedString("export.preview", comment: "Export preview"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    Text(markdown)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxHeight: 280)

                VStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = markdown
                        Haptics.notify(.success)
                        dismiss()
                    } label: {
                        Label(
                            NSLocalizedString("export.copy", comment: "Copy Markdown"),
                            systemImage: "doc.on.clipboard"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if let url = notionURL {
                        Link(destination: url) {
                            Label(
                                NSLocalizedString("export.notion", comment: "Open in Notion"),
                                systemImage: "arrow.up.right.square"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        showActivityVC = true
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
            .padding(20)
            .navigationTitle(NSLocalizedString("detail.exportNote", comment: "Export Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.close", comment: "Close")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showActivityVC) {
            ActivityViewControllerWrapper(items: [markdown])
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    MarkdownShareSheet(
        markdown: "---\ntitle: \"Test\"\n---\n\n# Test\n\nBody text.",
        title: "Test Place",
        notionURL: URL(string: "https://notion.so/new")
    )
}
