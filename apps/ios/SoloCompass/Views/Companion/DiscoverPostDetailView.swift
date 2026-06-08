import SwiftUI

/// Detail sheet for an anonymized Discover post (US-016).
///
/// Shows the post's emoji handle, blurb, dates, and categories, plus an
/// [Add Friend] action that sends a `source: .discover` friend request through
/// the trust-gated `FriendService.sendDiscoverRequest`. The author's
/// `reporterWeight` is threaded into the gate so a heavily-reported author can't
/// be added, and an optional one-line note (capped at 120 chars) accompanies
/// the request.
///
/// The [Send companion request] flow stays in `DiscoverListView`; this detail
/// is the dedicated *friend* entry point.
struct DiscoverPostDetailView: View {
    let post: DiscoverPost
    var service: FriendService = .shared

    @Environment(\.dismiss) private var dismiss

    @State private var note: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    /// FRD: note hard cap shared with `FriendService.sendRequest`.
    private static let noteLimit = 120

    private var relation: FriendRelationState {
        service.relationState(with: post.id)
    }

    private var canAdd: Bool {
        relation == .none && !isSending && !didSend
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !post.categories.isEmpty { categoryPills }
                    noteField
                    addFriendButton
                    if let msg = errorMessage {
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityLabel(msg)
                    }
                }
                .padding(20)
            }
            .navigationTitle(NSLocalizedString("companion.discover.detail.title", comment: "Discover post detail title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(post.handle)
                .font(.system(size: 48))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(post.blurb)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let from = post.activeFrom, let to = post.activeTo {
                    Text("\(from) – \(to)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(post.categories, id: \.self) { cat in
                    Text(cat.capitalized)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("friend.discover.note.label", comment: "Add a note label"))
                .font(.subheadline.weight(.medium))
            TextField(
                NSLocalizedString("friend.discover.note.placeholder", comment: "Note placeholder"),
                text: $note,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .disabled(!canAdd)
            // Enforce the 120-char cap as the user types.
            .onChange(of: note) { _, newValue in
                if newValue.count > Self.noteLimit {
                    note = String(newValue.prefix(Self.noteLimit))
                }
            }
            Text("\(note.count)/\(Self.noteLimit)")
                .font(.caption2)
                .foregroundStyle(note.count >= Self.noteLimit ? .orange : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(
                    String(
                        format: NSLocalizedString("friend.discover.note.count.a11y", comment: "Note character count"),
                        note.count, Self.noteLimit
                    )
                )
        }
    }

    @ViewBuilder
    private var addFriendButton: some View {
        Button(action: send) {
            Label(
                buttonTitle,
                systemImage: didSend || relation == .pending ? "clock.fill" : "person.badge.plus"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canAdd)
        .accessibilityLabel(buttonTitle)
    }

    private var buttonTitle: String {
        if didSend || relation == .pending {
            return NSLocalizedString("friend.add.state.pending", comment: "Pending")
        }
        if relation == .accepted {
            return NSLocalizedString("friend.add.state.friends", comment: "Friends")
        }
        return NSLocalizedString("friend.add.state.add", comment: "Add Friend")
    }

    // MARK: - Action

    private func send() {
        guard canAdd else { return }
        isSending = true
        errorMessage = nil
        Haptics.selection()
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await service.sendDiscoverRequest(
                to: post.id,
                reporterWeight: post.reporterWeight,
                note: trimmed.isEmpty ? nil : trimmed
            )
            isSending = false
            switch result {
            case .success:
                didSend = true
                Haptics.notify(.success)
            case .failure(let err):
                errorMessage = err.localizedDescription
                Haptics.notify(.error)
            }
        }
    }
}

// MARK: - Preview

#Preview("Discover post detail") {
    DiscoverPostDetailView(
        post: DiscoverPost(
            id: "post_preview",
            handle: "🦊",
            blurb: "Hiking the old town this weekend — looking for a walking buddy.",
            categories: ["hiking", "coffee"],
            cityCode: "TYO",
            mode: "city",
            activeFrom: "2026-06-10",
            activeTo: "2026-06-14",
            reporterWeight: 0.9
        )
    )
}
