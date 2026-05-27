import SwiftUI

/// Sheet for composing an icebreaker note before sending a companion request.
///
/// US-012: The note is optional but capped at 200 chars.
/// Dismissing without tapping "Send" cancels the action.
struct SendRequestSheet: View {
    let post: DiscoverPost
    let onSend: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    private let maxNoteLength = 200

    var body: some View {
        NavigationStack {
            Form {
                // Post preview
                Section {
                    HStack(spacing: 12) {
                        Text(post.handle)
                            .font(.system(size: 32))
                            .accessibilityHidden(true)
                        Text(post.blurb)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                } header: {
                    Text(NSLocalizedString("companion.request.post.header", comment: "Post preview section header"))
                }

                // Icebreaker note
                Section {
                    TextField(
                        NSLocalizedString("companion.request.note.placeholder", comment: "Icebreaker note placeholder"),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(3...5)
                    .onChange(of: note) { _, new in
                        if new.count > maxNoteLength { note = String(new.prefix(maxNoteLength)) }
                    }
                } header: {
                    Text(NSLocalizedString("companion.request.note.header", comment: "Icebreaker note section header"))
                } footer: {
                    Text(String(
                        format: NSLocalizedString("companion.request.note.footer", comment: "Note char count footer"),
                        note.count,
                        maxNoteLength
                    ))
                    .font(.caption)
                    .foregroundStyle(note.count >= maxNoteLength ? .red : .secondary)
                }
            }
            .navigationTitle(NSLocalizedString("companion.request.sheet.title", comment: "Send request sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("companion.request.send.action", comment: "Send button")) {
                        onSend(note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    SendRequestSheet(post: DiscoverPost(
        id: "cpost_preview",
        handle: "🧭",
        blurb: "Looking for a travel buddy for Tokyo — coffee shops and hidden temples.",
        categories: ["coffee", "culture"],
        cityCode: "TYO",
        mode: "itinerary",
        activeFrom: "2026-04-01",
        activeTo: "2026-04-10"
    )) { _ in }
}
