import SwiftUI

/// Sheet for composing an icebreaker note before sending a companion request.
///
/// US-012: The note is optional but capped at 200 chars.
/// US-019: A `source` distinguishes a stranger request (`.discover`) from a
/// friend meetup invite (`.friend`). The friend path skips the stranger
/// friction — there is no reporterWeight gate and no safety consent — because
/// the relationship is already established. The view itself stays presentational;
/// the gate (or lack of one) lives in the caller's `onSend` handler.
///
/// Dismissing without tapping "Send" cancels the action.
struct SendRequestSheet: View {
    /// What kind of request is being composed — signals to the caller whether
    /// stranger trust gates apply.
    enum Source {
        /// Stranger discovered in companion-discover; trust gates apply upstream.
        case discover
        /// Existing friend being invited to a meetup; no trust gate, no consent.
        case friend
    }

    /// The minimal recipient identity shown in the preview, decoupled from
    /// `DiscoverPost` so a friend invite can prefill without a discover post.
    struct Recipient {
        let handle: String
        let blurb: String
    }

    let recipient: Recipient
    let source: Source
    let onSend: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    private let maxNoteLength = 200

    /// US-012: compose from a discovered stranger post (trust-gated upstream).
    init(post: DiscoverPost, onSend: @escaping (String?) -> Void) {
        self.recipient = Recipient(handle: post.handle, blurb: post.blurb)
        self.source = .discover
        self.onSend = onSend
    }

    /// US-019: compose a meetup invite to an existing friend. No reporterWeight
    /// gate and no safety consent — the relationship already cleared those.
    init(recipient: Recipient, source: Source, onSend: @escaping (String?) -> Void) {
        self.recipient = recipient
        self.source = source
        self.onSend = onSend
    }

    private var titleKey: String {
        source == .friend
            ? "companion.invite.sheet.title"
            : "companion.request.sheet.title"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Recipient preview
                Section {
                    HStack(spacing: 12) {
                        Text(recipient.handle)
                            .font(.system(size: 32))
                            .accessibilityHidden(true)
                        Text(recipient.blurb)
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
            .navigationTitle(NSLocalizedString(titleKey, comment: "Send request sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
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
        // Protect a typed-but-unsent icebreaker from an accidental swipe-down.
        .interactiveDismissDisabled(!note.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

#Preview("Discover request") {
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

#Preview("Friend invite") {
    SendRequestSheet(
        recipient: .init(handle: "🌊", blurb: "wanderlust_mei"),
        source: .friend
    ) { _ in }
}
