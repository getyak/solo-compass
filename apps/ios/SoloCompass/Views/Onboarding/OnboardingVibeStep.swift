import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Onboarding step that bootstraps the user's TasteProfile from up to three
/// vibe photos (P1.2 #120). The step is intentionally skippable —
/// `AIService.generateTasteProfile` already returns a deterministic fallback
/// when no photos arrive, so skipping just lands the user at the lower-
/// confidence floor instead of blocking onboarding entirely.
///
/// Why deterministic fallback matters: onboarding must never wait on a cloud
/// LLM. The contract for #120 is that this view always lets the user move
/// on (Continue or Skip), and writing the profile is best-effort under it.
public struct OnboardingVibeStep: View {

    /// Called once the user finishes (with or without photos) so the parent
    /// flow can advance to the next step.
    public let onContinue: () -> Void

    /// Optional override so previews and tests can inject a fake AIService
    /// without touching the shared singleton.
    public let aiService: AIService

    @Environment(\.modelContext) private var modelContext
    @Environment(UserPreferences.self) private var preferences

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    @State private var freeformVibe: String = ""
    @State private var isWorking: Bool = false
    @State private var lastError: String? = nil

    public init(
        aiService: AIService = AIService(),
        onContinue: @escaping () -> Void
    ) {
        self.aiService = aiService
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            photoGrid
            vibeField
            Spacer(minLength: 8)
            actions
            if let lastError = lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(CT.savedRed)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .onChange(of: pickerItems) { _, newValue in
            Task { await loadPickedImages(newValue) }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("onboarding.vibe.title", comment: "Vibe step title"))
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(NSLocalizedString("onboarding.vibe.subtitle", comment: "Vibe step explainer"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var photoGrid: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { idx in
                photoSlot(at: idx)
            }
        }
    }

    @ViewBuilder
    private func photoSlot(at idx: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            if idx < pickedImages.count {
                Image(uiImage: pickedImages[idx])
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(white: 0.65))
            }
        }
        .frame(width: 96, height: 96)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if idx == 0 {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(CT.accent)
                        .background(Color(.systemBackground), in: Circle())
                }
                .padding(4)
            }
        }
    }

    private var vibeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("onboarding.vibe.field.label", comment: "Free-form vibe label"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                NSLocalizedString("onboarding.vibe.field.placeholder", comment: "Free-form vibe placeholder"),
                text: $freeformVibe
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await commit(skip: false) }
            } label: {
                Text(NSLocalizedString("onboarding.vibe.continue", comment: "Continue button"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)

            Button {
                Task { await commit(skip: true) }
            } label: {
                Text(NSLocalizedString("onboarding.vibe.skip", comment: "Skip button"))
                    .font(.footnote)
            }
            .disabled(isWorking)
            Text(NSLocalizedString("onboarding.vibe.skip.hint", comment: "Skip hint about lower quality"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Photo loading

    private func loadPickedImages(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items.prefix(3) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                images.append(ui)
            }
        }
        pickedImages = images
    }

    // MARK: - Commit

    private func commit(skip: Bool) async {
        isWorking = true
        defer { isWorking = false }

        let photos: [Data] = skip ? [] : pickedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        let vibeText = skip ? nil : (freeformVibe.isEmpty ? nil : freeformVibe)

        let result = await aiService.generateTasteProfile(
            photos: photos,
            style: preferences.soloTravelStyle,
            freeformVibe: vibeText
        )

        do {
            try await persistProfile(
                embedding: result.embedding,
                descriptors: result.descriptors,
                confidence: result.confidence,
                photoCount: photos.count
            )
        } catch {
            lastError = error.localizedDescription
        }

        onContinue()
    }

    private func persistProfile(
        embedding: [Float],
        descriptors: [String],
        confidence: Double,
        photoCount: Int
    ) async throws {
        let embeddingBlob = TasteProfile.encodeEmbedding(embedding)
        let descriptorsBlob = try TasteProfile.encodeDescriptors(descriptors)
        let photosBlob: Data? = photoCount > 0
            ? try? JSONEncoder().encode(Array(repeating: "vibe_photo", count: photoCount))
            : nil

        let existing = try modelContext.fetch(FetchDescriptor<TasteProfile>())
        if let row = existing.first {
            row.embedding = embeddingBlob
            row.descriptorsBlob = descriptorsBlob
            row.confidence = confidence
            row.updatedAt = Date()
            row.sourceVibePhotosBlob = photosBlob
        } else {
            let row = TasteProfile(
                embedding: embeddingBlob,
                descriptorsBlob: descriptorsBlob,
                confidence: confidence,
                sourceVibePhotosBlob: photosBlob
            )
            modelContext.insert(row)
        }
        try modelContext.save()
    }
}
