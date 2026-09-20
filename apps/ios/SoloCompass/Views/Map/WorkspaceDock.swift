import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Three-item floating dock: 地图 · 问问 · 发现.
///
/// The dock is the workspace's stable navigation. It replaces the legacy
/// bottom sheet + amber "+" FAB with one control row that keeps every
/// destination reachable while the conversation panel is open. The centre item
/// reuses the existing `PlusActionButton` / `SoloMascotView` brand mark (tap =
/// chat, hold = talk) instead of introducing a generic AI orb.
@MainActor
struct WorkspaceDock: View {
    @Bindable var workspace: ConversationWorkspaceState
    /// Select a non-ask surface (map / discover). The dock fires the selection
    /// haptic itself; the ask item's haptic is owned by `PlusActionButton`.
    let onSelect: (ConversationWorkspaceState.Surface) -> Void
    /// Long-press on the centre item: open the chat with the mic pre-armed.
    let onVoiceAsk: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            surfaceItem(.map, icon: "map", labelKey: "workspace.dock.map")
            Spacer(minLength: 10)
            askItem
            Spacer(minLength: 10)
            surfaceItem(.discover, icon: "binoculars", labelKey: "workspace.dock.discover")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassSurface(.control, in: Capsule(), opaqueFallback: CT.cardAdaptive)
        .overlay(
            Capsule().strokeBorder(dockBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(WorkspaceAccessibility.dock)
    }

    // MARK: - Surface item

    private func surfaceItem(
        _ surface: ConversationWorkspaceState.Surface,
        icon: String,
        labelKey: String
    ) -> some View {
        let selected = workspace.surface == surface
        return Button {
            // A no-op tap (already on this surface) must not buzz.
            guard !selected else { return }
            #if canImport(UIKit)
            Haptics.selection()
            #endif
            onSelect(surface)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? CT.accent : (colorScheme == .dark ? CT.fgMutedDark : CT.fgMuted))
                    .frame(width: 44, height: 26)
                Text(NSLocalizedString(labelKey, comment: "Workspace dock item label"))
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? CT.accent : (colorScheme == .dark ? CT.fgMutedDark : CT.fgMuted))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(selected ? CT.accentSoft : Color.clear)
            )
            .frame(minWidth: 56, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(WorkspaceAccessibility.dockItem(surface))
        .accessibilityLabel(Text(NSLocalizedString(labelKey, comment: "Workspace dock item label")))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Ask item

    private var askItem: some View {
        let selected = workspace.surface == .ask
        return VStack(spacing: 1) {
            PlusActionButton(
                onShortTap: {
                    guard !selected else { return }
                    onSelect(.ask)
                },
                onLongPress: {
                    onSelect(.ask)
                    onVoiceAsk()
                },
                diameter: 46,
                // The dashed ring pulse belongs to the full-size map FAB; in the
                // compact dock it reads as noise, and the mascot + label already
                // carry the affordance.
                showsPressRing: false
            )
            // The identifier lives on the real Button so AX and touch both find
            // an actionable `workspace.dock.ask` element.
            .accessibilityIdentifier(WorkspaceAccessibility.dockItem(.ask))
            Text(NSLocalizedString("workspace.dock.ask", comment: "Ask Solo dock label"))
                .font(.system(size: 10, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? CT.accent : (colorScheme == .dark ? CT.fgMutedDark : CT.fgMuted))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(selected ? CT.accentSoft : Color.clear)
        )
        .frame(minWidth: 64, minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    private var dockBorder: Color {
        colorScheme == .dark ? Color(.separator) : CT.borderSubtle
    }
}

#Preview("Dock") {
    ZStack {
        Color(.systemTeal).ignoresSafeArea()
        WorkspaceDock(
            workspace: ConversationWorkspaceState(),
            onSelect: { _ in },
            onVoiceAsk: {}
        )
        .padding(.horizontal, 24)
    }
}
