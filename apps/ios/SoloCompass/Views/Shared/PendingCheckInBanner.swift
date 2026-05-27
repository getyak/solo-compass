import SwiftUI

/// Floating banner shown when the user enters a geofenced experience zone.
/// Tapping "Yes, I was there" calls onConfirm; dismissing calls onDismiss.
/// Shown from CompassMapView when MapViewModel.pendingCheckIn is non-nil.
public struct PendingCheckInBanner: View {
    let experienceTitle: String
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var crossedThreshold = false
    private let dismissThreshold: CGFloat = 80

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("checkin.banner.title", comment: "Did you visit?"))
                    .font(.subheadline.weight(.semibold))
                Text(experienceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    #if canImport(UIKit)
                    Haptics.notify(.success)
                    #endif
                    onConfirm()
                } label: {
                    Text(NSLocalizedString("checkin.banner.yes", comment: "Yes!"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.blue))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.secondarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "Dismiss")))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    dragOffset = min(0, gesture.translation.height * 0.85)
                    let overThreshold = -gesture.translation.height > dismissThreshold
                    if overThreshold && !crossedThreshold {
                        crossedThreshold = true
                        #if canImport(UIKit)
                        Haptics.selection()
                        #endif
                    } else if !overThreshold && crossedThreshold {
                        crossedThreshold = false
                    }
                }
                .onEnded { gesture in
                    if gesture.translation.height < -dismissThreshold {
                        #if canImport(UIKit)
                        Haptics.impact(.soft)
                        #endif
                        crossedThreshold = false
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = -200 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
                    } else {
                        crossedThreshold = false
                        withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                    }
                }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("checkin.banner.a11y", comment: "Did you visit %@?"),
            experienceTitle
        )))
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        PendingCheckInBanner(
            experienceTitle: "Watch the monks collect alms at dawn",
            onConfirm: {},
            onDismiss: {}
        )
        .padding(.bottom, 40)
    }
}
